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
    ofs_plat_host_ccip_if afu_clk_ccip_if();
    t_ofs_plat_power_state afu_clk_ccip_pwrState;

    generate
        if (ADD_CLOCK_CROSSING == 0)
        begin : nc
            // No clock crossing
            assign afu_clk_ccip_if.clk = to_fiu.clk;

            assign afu_clk_ccip_if.reset = to_fiu.reset;
            assign to_fiu.sTx = afu_clk_ccip_if.sTx;
            assign afu_clk_ccip_if.sRx = to_fiu.sRx;

            assign afu_clk_ccip_pwrState = fiu_pwrState;
            assign afu_clk_ccip_if.error = to_fiu.error;
        end
        else
        begin : ofs_plat_clock_crossing
            // Before crossing add some FIU-side register stages for timing.
            ofs_plat_host_ccip_if reg_ccip_if();
            t_ofs_plat_power_state reg_cp2af_pwrState;

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
                .to_fiu(to_fiu),
                .fiu_pwrState(fiu_pwrState),

                .to_afu(reg_ccip_if),
                .afu_pwrState(reg_cp2af_pwrState)
                );

            // Cross to the target clock
            ofs_plat_utils_ccip_async_shim
              #(
                .EXTRA_ALMOST_FULL_STAGES(2 * NUM_TIMING_REG_STAGES)
                )
              ccip_async_shim
               (
                .to_fiu(reg_ccip_if),
                .fiu_pwrState(reg_cp2af_pwrState),

                .afu_clk(afu_clk),
                .to_afu(afu_clk_ccip_if),
                .afu_pwrState(afu_clk_ccip_pwrState),

                .async_shim_error()
                );
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
        .to_fiu(afu_clk_ccip_if),
        .fiu_pwrState(afu_clk_ccip_pwrState),

        .to_afu(to_afu),
        .afu_pwrState(afu_pwrState)
        );

endmodule // ofs_plat_host_chan_as_ccip
