// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
    //  Convert CCI-P signals from the AFU to the FIU clock domain.
    // ====================================================================

    ofs_plat_host_ccip_if rd_ccip_if();

    generate
        if (ADD_CLOCK_CROSSING == 0)
        begin : nc
            // No clock crossing
            ofs_plat_ccip_if_connect conn
               (
                .to_afu(afu_clk_ccip_if),
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
                .to_afu(afu_clk_ccip_if),

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
