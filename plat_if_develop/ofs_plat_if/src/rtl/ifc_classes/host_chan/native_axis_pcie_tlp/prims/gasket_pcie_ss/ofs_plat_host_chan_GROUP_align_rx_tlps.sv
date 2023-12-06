// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Transform the source PCIe SS TLP vector to a vector in which the inband
// PCIe SS TLP headers are shunted to a sideband channel and the data is
// re-aligned to the width of the primary data stream.
//
// The sink streams guarantee:
//  1. At most one header per cycle in hdr_stream_sink.
//  2. Data aligned to the bus width in data_stream_sink.
//
// The consumer of the sink stream is responsible for consuming the two
// sink streams in the proper order. Namely, start with a header. If the
// header indicates there is data, consume data_stream_sink until EOP.
//

//
// This module is largely the same as the FIM's ofs_fim_pcie_hdr_extract(),
// modified to use ofs_plat_axi_stream_if.
//

module ofs_plat_host_chan_@group@_align_rx_tlps
   (
    ofs_plat_axi_stream_if.to_source stream_source,

    // Stream of PCIe_PUReqHdr_t or PCIePUCplHdr_t. (They are the
    // same size, type depends on fmt_type field.)
    ofs_plat_axi_stream_if.to_sink hdr_stream_sink,
    // Stream of raw TLP data.
    ofs_plat_axi_stream_if.to_sink data_stream_sink
    );

    logic clk;
    assign clk = stream_source.clk;
    logic reset_n;
    assign reset_n = stream_source.reset_n;

    localparam TDATA_WIDTH = stream_source.TDATA_WIDTH;
    localparam TUSER_WIDTH = stream_source.TUSER_WIDTH;
    localparam TKEEP_WIDTH = TDATA_WIDTH/8;

    // Size of a header. All header types are the same size.
    localparam HDR_WIDTH = $bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t);
    localparam HDR_TKEEP_WIDTH = HDR_WIDTH / 8;

    // Size of the data portion when a header that starts at tdata[0] is also present.
    localparam DATA_AFTER_HDR_WIDTH = TDATA_WIDTH - HDR_WIDTH;
    localparam DATA_AFTER_HDR_TKEEP_WIDTH = DATA_AFTER_HDR_WIDTH / 8;


    // ====================================================================
    //
    //  Add a skid buffer on input for timing
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      source_skid();

    ofs_plat_axi_stream_if_skid_source_clk entry_skid
       (
        .stream_source(stream_source),
        .stream_sink(source_skid)
        );

    wire source_skid_sop = source_skid.t.user[0].sop;


    // ====================================================================
    //
    //  Split the headers and data streams
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t),
        .TUSER_TYPE(logic)    // pu mode (0) / dm mode (1)
        )
      hdr_stream();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(logic)    // Not used
        )
      data_stream();

    logic prev_must_drain;

    // New message available and there is somewhere to put it?
    wire process_msg = source_skid.tvalid && source_skid.tready;
    wire process_drain = prev_must_drain && data_stream.tready;

    assign source_skid.tready = hdr_stream.tready && data_stream.tready;

    //
    // Requirements:
    //  - There is at most one header per beat in the incoming tdata stream.
    //  - All headers begin at tdata[0].
    //

    // Header - only when SOP in the incoming stream
    assign hdr_stream.tvalid = process_msg && source_skid_sop;
    assign hdr_stream.t.data = { '0, source_skid.t.data[$bits(pcie_ss_hdr_pkg::PCIe_CplHdr_t)-1 : 0] };
    assign hdr_stream.t.user = source_skid.t.user[0].dm_mode;
    assign hdr_stream.t.keep = 64'((65'h1 << ($bits(pcie_ss_hdr_pkg::PCIe_CplHdr_t)) / 8) - 1);
    assign hdr_stream.t.last = 1'b1;


    // Data - either directly from the stream for short messages or
    // by combining the current and previous messages.

    // Record the previous data in case it is needed later.
    logic [TDATA_WIDTH-1:0] prev_payload;
    logic [(TDATA_WIDTH/8)-1:0] prev_keep;
    always_ff @(posedge clk)
    begin
        if (process_drain)
        begin
            prev_must_drain <= 1'b0;
        end
        if (process_msg)
        begin
            prev_payload <= source_skid.t.data;
            prev_keep <= source_skid.t.keep;
            // Either there is data that won't fit in this beat or the data+header
            // is a single beat.
            prev_must_drain <= source_skid.t.last &&
                               (source_skid.t.keep[HDR_TKEEP_WIDTH] || source_skid_sop);
        end

        if (!reset_n)
        begin
            prev_must_drain <= 1'b0;
        end
    end

    // Continuation of multi-cycle data?
    logic payload_is_pure_data;
    assign payload_is_pure_data = !source_skid_sop;

    assign data_stream.tvalid = (process_msg && payload_is_pure_data) || process_drain;

    always_comb
    begin
        data_stream.t.last = (source_skid.t.last && !source_skid.t.keep[HDR_TKEEP_WIDTH]) ||
                            prev_must_drain;
        data_stream.t.user = '0;

        // Realign data - low part from previous flit, high part from current
        data_stream.t.data =
            { source_skid.t.data[0 +: HDR_WIDTH],
              prev_payload[HDR_WIDTH +: DATA_AFTER_HDR_WIDTH] };
        data_stream.t.keep =
            { source_skid.t.keep[0 +: HDR_TKEEP_WIDTH],
              prev_keep[HDR_TKEEP_WIDTH +: DATA_AFTER_HDR_TKEEP_WIDTH] };

        if (prev_must_drain)
        begin
            data_stream.t.data[DATA_AFTER_HDR_WIDTH +: HDR_WIDTH] = '0;
            data_stream.t.keep[DATA_AFTER_HDR_TKEEP_WIDTH +: HDR_TKEEP_WIDTH] = '0;
        end
    end


    // ====================================================================
    //
    //  Outbound buffers
    //
    // ====================================================================

    // Header must be a skid buffer to avoid deadlocks, as headers may arrive
    // before the payload.
    ofs_plat_axi_stream_if_skid_sink_clk exit_hdr_skid
       (
        .stream_source(hdr_stream),
        .stream_sink(hdr_stream_sink)
        );

    // Just a register for data to save space.
    ofs_plat_axi_stream_if_reg_sink_clk exit_data_reg
       (
        .stream_source(data_stream),
        .stream_sink(data_stream_sink)
        );

endmodule // ofs_plat_host_chan_@group@_align_rx_tlps
