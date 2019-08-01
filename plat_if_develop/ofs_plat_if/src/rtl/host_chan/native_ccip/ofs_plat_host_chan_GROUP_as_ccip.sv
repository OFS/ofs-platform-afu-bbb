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

module ofs_plat_host_chan_GROUP_as_ccip
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset pair passed in afu_clk/afu_reset.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,
    ofs_plat_host_ccip_if.to_afu to_afu,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,

    // Map pwrState to the target clock domain.
    input  t_ofs_plat_power_state fiu_pwrState,
    output t_ofs_plat_power_state afu_pwrState
    );

    assign to_afu.clk = (ADD_CLOCK_CROSSING == 0) ? to_fiu.clk : afu_clk;

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
    //  Convert CCI-P signals to the target clock domain.
    // ====================================================================

    // CCI-P signals in the AFU's requested clock domain
    logic cross_cp2af_softReset;
    t_if_ccip_Tx cross_af2cp_sTx;
    t_if_ccip_Rx cross_cp2af_sRx;
    t_ofs_plat_power_state cross_cp2af_pwrState;
    logic cross_cp2af_error;
    logic actual_afu_clk;

    generate
        if (ADD_CLOCK_CROSSING == 0)
        begin : nc
            // No clock crossing
            always_comb
            begin
                actual_afu_clk = to_fiu.clk;

                cross_cp2af_softReset = to_fiu.reset;
                to_fiu.sTx = cross_af2cp_sTx;
                cross_cp2af_sRx = to_fiu.sRx;

                cross_cp2af_pwrState = fiu_pwrState;
                cross_cp2af_error = to_fiu.error;
            end
        end
        else
        begin : ofs_plat_clock_crossing
            // Before crossing add some FIU-side register stages for timing.
            logic reg_cp2af_softReset;
            t_if_ccip_Tx reg_af2cp_sTx;
            t_if_ccip_Rx reg_cp2af_sRx;
            t_ofs_plat_power_state reg_cp2af_pwrState;
            logic reg_cp2af_error;

            // How many register stages should be inserted for timing?
            // At least one stage, perhaps more.
            localparam NUM_PRE_CROSS_REG_STAGES =
                (ccip_cfg_pkg::SUGGESTED_TIMING_REG_STAGES != 0) ?
                    ccip_cfg_pkg::SUGGESTED_TIMING_REG_STAGES : 1;

            ofs_plat_utils_ccip_reg
              #(
                .N_REG_STAGES(NUM_PRE_CROSS_REG_STAGES)
                )
            ccip_pre_cross_reg
               (
                .clk(to_fiu.clk),

                .fiu_reset(to_fiu.reset),
                .fiu_cp2af_sRx(to_fiu.sRx),
                .fiu_af2cp_sTx(to_fiu.sTx),
                .fiu_cp2af_pwrState(fiu_pwrState),
                .fiu_cp2af_error(to_fiu.error),

                .afu_reset(reg_cp2af_softReset),
                .afu_cp2af_sRx(reg_cp2af_sRx),
                .afu_af2cp_sTx(reg_af2cp_sTx),
                .afu_cp2af_pwrState(reg_cp2af_pwrState),
                .afu_cp2af_error(reg_cp2af_error)
                );

            // Cross to the target clock
            ofs_plat_utils_ccip_async_shim
              #(
                .EXTRA_ALMOST_FULL_STAGES(2 * NUM_TIMING_REG_STAGES)
                )
              ccip_async_shim
               (
                .bb_softreset(reg_cp2af_softReset),
                .bb_clk(to_fiu.clk),
                .bb_tx(reg_af2cp_sTx),
                .bb_rx(reg_cp2af_sRx),
                .bb_pwrState(reg_cp2af_pwrState),
                .bb_error(reg_cp2af_error),

                .afu_softreset(cross_cp2af_softReset),
                .afu_clk(afu_clk),
                .afu_tx(cross_af2cp_sTx),
                .afu_rx(cross_cp2af_sRx),
                .afu_pwrState(cross_cp2af_pwrState),
                .afu_error(cross_cp2af_error),

                .async_shim_error()
                );

            assign actual_afu_clk = afu_clk;

        end
    endgenerate


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

    ofs_plat_utils_ccip_reg
      #(
        .N_REG_STAGES(NUM_TIMING_REG_STAGES)
        )
      ccip_reg
       (
        .clk(actual_afu_clk),

        .fiu_reset(cross_cp2af_softReset),
        .fiu_cp2af_sRx(cross_cp2af_sRx),
        .fiu_af2cp_sTx(cross_af2cp_sTx),
        .fiu_cp2af_pwrState(cross_cp2af_pwrState),
        .fiu_cp2af_error(cross_cp2af_error),

        .afu_reset(to_afu.reset),
        .afu_cp2af_sRx(to_afu.sRx),
        .afu_af2cp_sTx(to_afu.sTx),
        .afu_cp2af_pwrState(afu_pwrState),
        .afu_cp2af_error(to_afu.error)
        );

endmodule // ofs_plat_host_chan_as_ccip
