//
// Copyright (c) 2021, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.


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

module ofs_plat_host_chan_@group@_align_rx_tlps
   (
    ofs_plat_axi_stream_if.to_source stream_source,

    // Stream of PCIe_PUReqHdr_t or PCIePUCplHdr_t. (They are the
    // same size, type depends on fmt_type field.)
    ofs_plat_axi_stream_if.to_sink hdr_stream_sink,
    // Stream of raw TLP data.
    ofs_plat_axi_stream_if.to_sink data_stream_sink
    );

    import ofs_plat_host_chan_@group@_fim_gasket_pkg::*;

    logic clk;
    assign clk = stream_source.clk;
    logic reset_n;
    assign reset_n = stream_source.reset_n;

    // synthesis translate_off
    initial
    begin
        // The code below assumes that a header is encoded as exactly
        // half of the data bus width.
        assert($bits(t_ofs_fim_axis_pcie_tdata) == 2 * $bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t)) else
          $fatal(2, "PCIe SS header size is not half the data bus width. Code below will not work.");
    end
    // synthesis translate_on

    localparam HALF_TDATA_WIDTH = ofs_pcie_ss_cfg_pkg::TDATA_WIDTH / 2;


    // ====================================================================
    //
    //  Add a skid buffer on input for timing
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(t_ofs_fim_axis_pcie_tuser)
        )
      source_skid();

    ofs_plat_axi_stream_if_skid_source_clk entry_skid
       (
        .stream_source(stream_source),
        .stream_sink(source_skid)
        );


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
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(logic)    // Not used
        )
      data_stream();

    // New message available and there is somewhere to put it?
    logic process_msg;
    assign process_msg = hdr_stream.tready && data_stream.tready &&
                         source_skid.tvalid;

    assign source_skid.tready = hdr_stream.tready && data_stream.tready;

    generate
        if (ofs_pcie_ss_cfg_pkg::NUM_OF_SEG == 1)
        begin : seg1
            //
            // This is a very simple case:
            //  - There is at most one header (SOP) in the incoming tdata stream.
            //  - All headers begin at tdata[0].
            //  - All headers or stored in exactly half the width of tdata.
            //  - The last beat of data in a multi-beat message takes exactly half
            //    the width of tdata. We know this because multi-beat messages
            //    are either completions requested by the PIM (which only asks
            //    for multiples of the data bus width) or are wide MMIO writes,
            //    which are also assumed to be multiples of the bus width.
            //    (Most MMIO writes fit in a single beat.)
            //

            // Header - only when SOP in the incoming stream
            assign hdr_stream.tvalid = process_msg && source_skid.t.user[0].sop;
            always_comb
            begin
                hdr_stream.t = '0;
                hdr_stream.t.data = pcie_ss_hdr_pkg::PCIe_PUReqHdr_t'(source_skid.t.data.payload);
                hdr_stream.t.user = source_skid.t.user[0].dm_mode;
                hdr_stream.t.last = 1'b1;
            end


            // Data - either directly from the stream for short messages or
            // by combining the current and previous messages.

            // Record the previous data in case it is needed later.
            logic [ofs_pcie_ss_cfg_pkg::TDATA_WIDTH-1:0] prev_payload;
            always_ff @(posedge clk)
            begin
                if (process_msg)
                begin
                    prev_payload <= source_skid.t.data.payload;
                end
            end

            // Continuation of multi-cycle data?
            logic payload_is_pure_data;
            assign payload_is_pure_data = !source_skid.t.user[0].sop;

            // SOP and EOP both in the same source message? No realignment is required.
            // A message is sent on the data channel even when the header indicates there
            // is no data payload because always pushing a data channel message
            // simplifies logic for the consumer.
            logic payload_is_short;
            assign payload_is_short = source_skid.t.user[0].sop && source_skid.t.last;

            assign data_stream.tvalid = process_msg &&
                                        (payload_is_pure_data || payload_is_short);
            always_comb
            begin
                data_stream.t = '0;
                data_stream.t.last = source_skid.t.last;
                // The PIM doesn't care about tkeep
                data_stream.t.keep = ~'0;

                if (payload_is_short)
                begin
                    // Short data - header low half, payload high half
                    data_stream.t.data[0 +: HALF_TDATA_WIDTH-1] =
                        source_skid.t.data.payload[HALF_TDATA_WIDTH +: HALF_TDATA_WIDTH];
                end
                else
                begin
                    // Long data - low half from previous flit, high half from current
                    data_stream.t.data =
                        { source_skid.t.data.payload[0 +: HALF_TDATA_WIDTH],
                          prev_payload[HALF_TDATA_WIDTH +: HALF_TDATA_WIDTH] };
                end
            end


            // synthesis translate_off
            // Check the integrity of the incoming SOP and tlast bits
            logic expect_sop;

            always_ff @(posedge clk)
            begin
                if (process_msg)
                begin
                    expect_sop <= source_skid.t.last;

                    if (reset_n)
                    begin
                        assert(expect_sop == source_skid.t.user[0].sop) else
                          $fatal(2, "expect_sop (%0d) != actual SOP flag", expect_sop);
                    end
                end

                if (!reset_n)
                begin
                    expect_sop <= 1'b1;
                end
            end
            // synthesis translate_on
        end
        else
        begin : fail
            // synthesis translate_off
            initial
            begin
                $fatal(2, "%0d segments per PCIe data segment not yet supported.",
                       ofs_pcie_ss_cfg_pkg::NUM_OF_SEG);
            end
            // synthesis translate_on
        end
    endgenerate


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
