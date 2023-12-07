// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Transform the PIM's FPGA->host TLP TX stream to the PCIe SS TLP vector.
// The incoming headers from the PIM have already been tranformed to
// PCIe SS format when they reach this module. However, headers are
// still out of band and must be embedded into the PCIe SS TLP stream
// along with data.
//

module ofs_plat_host_chan_@group@_align_tx_tlps
   (
    ofs_plat_axi_stream_if.to_sink stream_sink,

    // Stream of PCIe SS headers
    ofs_plat_axi_stream_if.to_source hdr_stream_source,
    // Stream of raw TLP data
    ofs_plat_axi_stream_if.to_source data_stream_source
    );

    logic clk;
    assign clk = stream_sink.clk;
    logic reset_n;
    assign reset_n = stream_sink.reset_n;

    localparam TDATA_WIDTH = stream_sink.TDATA_WIDTH;
    localparam TUSER_WIDTH = stream_sink.TUSER_WIDTH;
    localparam TKEEP_WIDTH = TDATA_WIDTH/8;

    // Size of a header. All header types are the same size.
    localparam HDR_WIDTH = $bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t);
    localparam HDR_TKEEP_WIDTH = HDR_WIDTH / 8;

    // Size of the data portion when a header that starts at tdata[0] is also present.
    localparam DATA_AFTER_HDR_WIDTH = TDATA_WIDTH - HDR_WIDTH;
    localparam DATA_AFTER_HDR_TKEEP_WIDTH = DATA_AFTER_HDR_WIDTH / 8;


    // ====================================================================
    //
    //  Register input for timing
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t),
        .TUSER_TYPE(logic)    // pu mode (0) / dm mode (1)
        )
      hdr_source();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(logic)    // Not used
        )
      data_source();

    ofs_plat_axi_stream_if_reg_source_clk hdr_entry_reg
       (
        .stream_source(hdr_stream_source),
        .stream_sink(hdr_source)
        );

    ofs_plat_axi_stream_if_reg_source_clk data_entry_reg
       (
        .stream_source(data_stream_source),
        .stream_sink(data_source)
        );


    // ====================================================================
    //
    //  Split the headers and data streams
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      sink_skid();

    //
    // Track EOP/SOP of the outgoing stream in order to handle
    // hdr and data messages in order.
    //
    logic source_is_sop;

    always_ff @(posedge clk)
    begin
        if (data_source.tready && data_source.tvalid)
        begin
            source_is_sop <= data_source.t.last;
        end

        if (!reset_n)
        begin
            source_is_sop <= 1'b1;
        end
    end

    generate
        if (ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_OF_SEG == 1)
        begin : seg1
            //
            // This is a very simple case:
            //  - There is at most one header (SOP) in the incoming tdata stream.
            //  - All headers begin at tdata[0].
            //

            // Track data remaining from the previous cycle
            logic prev_data_valid;
            logic [TDATA_WIDTH-1:0] prev_data;
            logic [(TDATA_WIDTH/8)-1:0] prev_data_keep;

            wire source_is_single_beat =
                 !pcie_ss_hdr_pkg::func_has_data(hdr_source.t.data.fmt_type) ||
                 !data_source.t.keep[DATA_AFTER_HDR_TKEEP_WIDTH];

            always_ff @(posedge clk)
            begin
                if (sink_skid.tvalid && sink_skid.tready)
                begin
                    if (data_source.tready)
                    begin
                        // Does the current cycle's source data fit completely in the
                        // sink data vector? If this isn't the SOP beat then the
                        // last beat fits if it is shorter than the injected header.
                        // If this is an SOP beat then there will be previous data
                        // if the message doesn't fit in a single beat.
                        prev_data_valid <= ((!source_is_sop && data_source.t.keep[DATA_AFTER_HDR_TKEEP_WIDTH]) ||
                                            (source_is_sop && !source_is_single_beat));
                    end
                    else
                    begin
                        // Must have written out prev_data to sink_skid this cycle, since
                        // a message was passed to sink_skid but nothing was consumed
                        // from data_source.
                        prev_data_valid <= 1'b0;
                    end
                end

                if (!reset_n)
                begin
                    prev_data_valid <= 1'b0;
                end
            end

            // Update the stored data
            always_ff @(posedge clk)
            begin
                // As long as something is written to the outbound stream it is safe
                // to update the stored data. If the input data stream is unconsumed
                // this cycle then the stored data is being flushed out with nothing
                // new to replace it. (prev_data_valid will be 0.)
                if (sink_skid.tvalid && sink_skid.tready)
                begin
                    // Stored data is always shifted by the same amount: the size
                    // of the TLP header.
                    prev_data <= { '0, data_source.t.data[DATA_AFTER_HDR_WIDTH +: HDR_WIDTH] };
                    prev_data_keep <= { '0, data_source.t.keep[DATA_AFTER_HDR_TKEEP_WIDTH +: HDR_TKEEP_WIDTH] };
                end
            end


            // Consume incoming header? If the previous partial data is not yet
            // emitted, then no. Otherwise, yes if header and data are valid and the
            // outbound stream is ready.
            assign hdr_source.tready = hdr_source.tvalid &&
                                       data_source.tvalid &&
                                       sink_skid.tready &&
                                       source_is_sop &&
                                       !prev_data_valid;

            // Consume incoming data? If SOP, then only if the header is ready and
            // all previous data has been emitted. If not SOP, then yes as long
            // as the outbound stream is ready.
            assign data_source.tready = (!source_is_sop || hdr_source.tvalid) &&
                                        data_source.tvalid &&
                                        sink_skid.tready &&
                                        (!source_is_sop || !prev_data_valid);

            // Write outbound TLP traffic? Yes if consuming incoming data or if
            // the previous packet is complete and data from it remains.
            assign sink_skid.tvalid = data_source.tready ||
                                      (source_is_sop && prev_data_valid);

            // Generate the outbound payload
            always_comb
            begin
                sink_skid.t = '0;

                if (hdr_source.tready)
                begin
                    // SOP: payload is first portion of data + header
                    sink_skid.t.data = { data_source.t.data[0 +: DATA_AFTER_HDR_WIDTH],
                                        hdr_source.t.data[0 +: HDR_WIDTH] };
                    sink_skid.t.keep = { data_source.t.keep[0 +: DATA_AFTER_HDR_TKEEP_WIDTH],
                                        {(HDR_TKEEP_WIDTH){1'b1}} };
                    sink_skid.t.last = source_is_single_beat;
                    sink_skid.t.user[0].dm_mode = hdr_source.t.user;
                    sink_skid.t.user[0].sop = 1'b1;
                    sink_skid.t.user[0].eop = sink_skid.t.last;
                end
                else
                begin
                    sink_skid.t.data = { data_source.t.data[0 +: DATA_AFTER_HDR_WIDTH],
                                        prev_data[0 +: HDR_WIDTH] };
                    sink_skid.t.keep = { data_source.t.keep[0 +: DATA_AFTER_HDR_TKEEP_WIDTH],
                                        prev_data_keep[0 +: HDR_TKEEP_WIDTH] };
                    if (source_is_sop)
                    begin
                        // New data isn't being being consumed -- only the prev_data is
                        // valid.
                        sink_skid.t.data[HDR_WIDTH +: DATA_AFTER_HDR_WIDTH] = '0;
                        sink_skid.t.keep[HDR_TKEEP_WIDTH +: DATA_AFTER_HDR_TKEEP_WIDTH] = '0;
                    end

                    sink_skid.t.last = source_is_sop || !data_source.t.keep[DATA_AFTER_HDR_TKEEP_WIDTH];
                    sink_skid.t.user[0].dm_mode = 1'b0;
                    sink_skid.t.user[0].sop = 1'b0;
                    sink_skid.t.user[0].eop = sink_skid.t.last;
                end
            end
        end
        else
        begin : fail
            // synthesis translate_off
            initial
            begin
                $fatal(2, "%0d segments per PCIe data segment not yet supported.",
                       ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_OF_SEG);
            end
            // synthesis translate_on
        end
    endgenerate


    // ====================================================================
    //
    //  Outbound skid buffers
    //
    // ====================================================================

    ofs_plat_axi_stream_if_skid_sink_clk exit_skid
       (
        .stream_source(sink_skid),
        .stream_sink(stream_sink)
        );

endmodule // ofs_plat_host_chan_@group@_align_tx_tlps
