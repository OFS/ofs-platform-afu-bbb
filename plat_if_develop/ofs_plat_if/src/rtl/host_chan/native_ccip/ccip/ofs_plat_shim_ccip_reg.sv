//
// Copyright (c) 2017, Intel Corporation
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
// Add buffer stages to CCI-P structs
//

`include "ofs_plat_if.vh"

import ccip_if_pkg::*;

module ofs_plat_shim_ccip_reg
  #(
    parameter REGISTER_RX = 1,
    parameter REGISTER_TX = 1,
    parameter REGISTER_RESET = 1,
    parameter REGISTER_ERROR = 1,

    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    // FIU side
    ofs_plat_host_ccip_if.to_fiu to_fiu,
    input  t_ofs_plat_power_state fiu_pwrState,   // CCI-P AFU Power State

    // AFU side
    ofs_plat_host_ccip_if.to_afu to_afu,
    output t_ofs_plat_power_state afu_pwrState
    );

    logic clk;
    assign clk = to_fiu.clk;
    assign to_afu.clk = to_fiu.clk;

    genvar s;
    generate
        //
        // Register reset
        //
        if (REGISTER_RESET && N_REG_STAGES)
        begin : reg_reset
            (* altera_attribute = {"-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PRESERVE_REGISTER ON"} *)
            logic reset[N_REG_STAGES] = '{N_REG_STAGES{1'b1}};

            always @(posedge clk)
            begin
                reset[0] <= to_fiu.reset;
            end

            for (s = 0; s < N_REG_STAGES - 1; s = s + 1)
            begin
                always @(posedge clk)
                begin
                    reset[s+1] <= reset[s];
                end
            end

            assign to_afu.reset = reset[N_REG_STAGES - 1];
        end
        else
        begin : wire_reset
            assign to_afu.reset = to_fiu.reset;
        end


        //
        // Register TX
        //
        if (REGISTER_TX && N_REG_STAGES)
        begin : reg_tx
            (* altera_attribute = {"-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PRESERVE_REGISTER ON"} *)
            t_if_ccip_Tx reg_af2cp_sTx[N_REG_STAGES];

            // Tx to register stages
            always_ff @(posedge clk)
            begin
                reg_af2cp_sTx[0] <= to_afu.sTx;
            end

            // Intermediate stages
            for (s = 0; s < N_REG_STAGES - 1; s = s + 1)
            begin
                always_ff @(posedge clk)
                begin
                    reg_af2cp_sTx[s+1] <= reg_af2cp_sTx[s];
                end
            end

            assign to_fiu.sTx = reg_af2cp_sTx[N_REG_STAGES - 1];
        end
        else
        begin : wire_tx
            assign to_fiu.sTx = to_afu.sTx;
        end


        //
        // Register RX
        //
        if (REGISTER_RX && N_REG_STAGES)
        begin : reg_rx
            (* altera_attribute = {"-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PRESERVE_REGISTER ON"} *)
            t_if_ccip_Rx reg_cp2af_sRx[N_REG_STAGES];

            always_ff @(posedge clk)
            begin
                reg_cp2af_sRx[0] <= to_fiu.sRx;
            end

            // Intermediate stages
            for (s = 0; s < N_REG_STAGES - 1; s = s + 1)
            begin
                always_ff @(posedge clk)
                begin
                    reg_cp2af_sRx[s+1] <= reg_cp2af_sRx[s];
                end
            end

            assign to_afu.sRx = reg_cp2af_sRx[N_REG_STAGES - 1];
        end
        else
        begin : wire_rx
            assign to_afu.sRx = to_fiu.sRx;
        end


        //
        // Register power state and error signals
        //
        if (REGISTER_ERROR && N_REG_STAGES)
        begin : reg_err
            (* altera_attribute = {"-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PRESERVE_REGISTER ON"} *)
            t_ofs_plat_power_state reg_cp2af_pwrState[N_REG_STAGES];
            (* altera_attribute = {"-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PRESERVE_REGISTER ON"} *)
            logic reg_cp2af_error[N_REG_STAGES];

            always_ff @(posedge clk)
            begin
                reg_cp2af_pwrState[0] <= fiu_pwrState;
                reg_cp2af_error[0] <= to_fiu.error;
            end

            // Intermediate stages
            for (s = 0; s < N_REG_STAGES - 1; s = s + 1)
            begin
                always_ff @(posedge clk)
                begin
                    reg_cp2af_pwrState[s+1] <= reg_cp2af_pwrState[s];
                    reg_cp2af_error[s+1] <= reg_cp2af_error[s];
                end
            end

            assign afu_pwrState = reg_cp2af_pwrState[N_REG_STAGES - 1];
            assign to_afu.error = reg_cp2af_error[N_REG_STAGES - 1];
        end
        else
        begin : wire_err
            assign afu_pwrState = fiu_pwrState;
            assign to_afu.error = to_fiu.error;
        end
    endgenerate

endmodule // ofs_plat_shim_ccip_reg

