//
// Copyright (c) 2019, Intel Corporation
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
// Export a platform host_chan interface to an AFU as CCI-P.
//
// The "as CCI-P" abstraction here allows an AFU to request the host connection
// using a particular interface. The platform may offer multiple interfaces
// to the same underlying PR wires, instantiating protocol conversion
// shims as needed.
//

//
// This version of ofs_plat_host_chan_as_ccip works only on platforms
// where the native interface is already CCI-P.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_as_ccip
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should unpacked write responses be merged into a single packed
    // response, guaranteeing exactly one response per write request?
    parameter MERGE_UNPACKED_WRITE_RESPONSES = 0,

    // Should read or write responses be returned in the order they were
    // requested? By default, CCI-P is unordered.
    parameter SORT_READ_RESPONSES = 0,
    parameter SORT_WRITE_RESPONSES = 0
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,
    ofs_plat_host_ccip_if.to_afu to_afu,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    //
    // How many register stages should be inserted for timing?
    //
    function automatic int numTimingRegStages();
        // Were timing registers requested?
        int n_stages = ADD_TIMING_REG_STAGES;

        // Override the register request if a clock crossing is being
        // inserted here.
        if (ADD_CLOCK_CROSSING)
        begin
            // Use at least the recommended number of stages.  We can afford
            // to do this automatically without violating the CCI-P almost
            // full sending limit when there is a clock crossing.  The clock
            // crossing FIFO will leave enough extra space to accommodate
            // the extra messages.
            if (ccip_cfg_pkg::SUGGESTED_TIMING_REG_STAGES > n_stages)
            begin
                n_stages = ccip_cfg_pkg::SUGGESTED_TIMING_REG_STAGES;
            end
        end

        return n_stages;
    endfunction

    localparam NUM_TIMING_REG_STAGES = numTimingRegStages();


    // ====================================================================
    //
    //  Add CCI-P register stages for timing, as requested by setting
    //  NUM_TIMING_REG_STAGES.
    //
    //  For AFUs with both register stages and a clock crossing, we
    //  add register stages on the AFU side. Extra space is left in the
    //  clock crossing FIFO so that the almost full contract with the AFU
    //  remains unchanged, despite the added latency of almost full and
    //  the extra requests in flight.
    //
    //  NOTE: When no clock crossing is instantiated, register stages
    //  added here count against the almost full sending limits!
    //
    // ====================================================================

    ofs_plat_host_ccip_if afu_clk_ccip_if();

    ofs_plat_shim_ccip_reg
      #(
        .N_REG_STAGES(NUM_TIMING_REG_STAGES)
        )
      ccip_reg
       (
        .to_afu(to_afu),
        .to_fiu(afu_clk_ccip_if)
        );


    // ====================================================================
    //  Throttle write credits
    // ====================================================================

    //
    // With PCIe TLP interfaces, writes have neither tags nor completions.
    // This enables them to fill the request pipeline, starving reads.
    // Blocking the write pipeline here when the read pipeline is blocked
    // solves the problem.
    //

    ofs_plat_host_ccip_if wr_credit_ccip_if();

    assign afu_clk_ccip_if.clk = wr_credit_ccip_if.clk;
    assign afu_clk_ccip_if.reset_n = wr_credit_ccip_if.reset_n;
    assign afu_clk_ccip_if.error = wr_credit_ccip_if.error;
    assign afu_clk_ccip_if.instance_number = wr_credit_ccip_if.instance_number;

    // Only force c1TxAlmFull on SOP
    logic wr_credit_is_sop, wr_credit_is_eop;

    always_comb
    begin
        wr_credit_ccip_if.sTx = afu_clk_ccip_if.sTx;

        afu_clk_ccip_if.sRx = wr_credit_ccip_if.sRx;
        afu_clk_ccip_if.sRx.c1TxAlmFull = wr_credit_ccip_if.sRx.c1TxAlmFull ||
                                          (wr_credit_ccip_if.sRx.c0TxAlmFull && wr_credit_is_sop);
    end

    always_ff @(posedge wr_credit_ccip_if.clk)
    begin
        if (wr_credit_ccip_if.sTx.c1.valid)
        begin
            wr_credit_is_sop <= wr_credit_is_eop;
        end

        if (!wr_credit_ccip_if.reset_n)
        begin
            wr_credit_is_sop <= 1'b1;
        end
    end

    ofs_plat_utils_ccip_track_multi_write track_eop
       (
        .clk(wr_credit_ccip_if.clk),
        .reset_n(wr_credit_ccip_if.reset_n),
        .c1Tx(wr_credit_ccip_if.sTx.c1),
        .c1Tx_en(1'b1),
        .eop(wr_credit_is_eop),
        .packetActive(),
        .nextBeatNum()
        );


    // ====================================================================
    //  Convert CCI-P signals from the AFU to the FIU clock domain.
    // ====================================================================

    ofs_plat_host_ccip_if rd_ccip_if();

    generate
        if (ADD_CLOCK_CROSSING == 0)
        begin : nc
            // No clock crossing
            ofs_plat_ccip_if_connect conn
               (
                .to_afu(wr_credit_ccip_if),
                .to_fiu(rd_ccip_if)
                );
        end
        else
        begin : ofs_plat_clock_crossing
            // Cross to the target clock
            ofs_plat_shim_ccip_async
              #(
                .EXTRA_ALMOST_FULL_STAGES(2 * NUM_TIMING_REG_STAGES)
                )
              ccip_async_shim
               (
                .afu_clk,
                .afu_reset_n,
                .to_afu(wr_credit_ccip_if),

                .to_fiu(rd_ccip_if),

                .async_shim_error()
                );
        end
    endgenerate


    // ====================================================================
    //  Sort read responses in request order?
    // ====================================================================

    ofs_plat_host_ccip_if wr_ccip_if();

    generate
        if (SORT_READ_RESPONSES == 0)
        begin : nrs
            ofs_plat_ccip_if_connect conn
               (
                .to_afu(rd_ccip_if),
                .to_fiu(wr_ccip_if)
                );
        end
        else
        begin : rs
            ofs_plat_shim_ccip_rob_rd
              #(
                .MAX_ACTIVE_RD_REQS(ccip_@group@_cfg_pkg::C0_MAX_BW_ACTIVE_LINES[0])
                )
              rob_rd
               (
                .to_afu(rd_ccip_if),
                .to_fiu(wr_ccip_if)
                );
        end
    endgenerate


    // ====================================================================
    //  Sort write responses in request order?
    // ====================================================================

    ofs_plat_host_ccip_if#(.LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)) fiu_ccip_if();

    generate
        if (SORT_WRITE_RESPONSES == 0)
        begin : nws
            ofs_plat_ccip_if_connect conn
               (
                .to_afu(wr_ccip_if),
                .to_fiu(fiu_ccip_if)
                );
        end
        else
        begin : ws
            // Sort write responses
            ofs_plat_shim_ccip_rob_wr
              #(
                .MAX_ACTIVE_WR_REQS(ccip_@group@_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0])
                )
              rob_wr
               (
                .to_afu(wr_ccip_if),
                .to_fiu(fiu_ccip_if)
                );
        end
    endgenerate


    // ====================================================================
    //  Basic mapping of TLPs to CCI-P, all in the FIU clock domain
    // ====================================================================

    ofs_plat_host_chan_@group@_map_as_ccip tlp_as_ccip
       (
        .to_afu_ccip(fiu_ccip_if),
        .to_fiu_tlp(to_fiu)
        );

endmodule // ofs_plat_host_chan_as_ccip
