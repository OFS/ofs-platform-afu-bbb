// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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

    // AFU side
    ofs_plat_host_ccip_if.to_afu to_afu
    );

    logic clk;
    assign clk = to_fiu.clk;
    assign to_afu.clk = to_fiu.clk;

    assign to_afu.instance_number = to_fiu.instance_number;

    genvar s;
    generate
        //
        // Register reset_n
        //
        if (REGISTER_RESET && N_REG_STAGES)
        begin : reg_reset_n
            (* altera_attribute = {"-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PRESERVE_REGISTER ON"} *)
            logic reset_n[N_REG_STAGES] = '{N_REG_STAGES{1'b0}};

            always @(posedge clk)
            begin
                reset_n[0] <= to_fiu.reset_n;
            end

            for (s = 0; s < N_REG_STAGES - 1; s = s + 1)
            begin
                always @(posedge clk)
                begin
                    reset_n[s+1] <= reset_n[s];
                end
            end

            assign to_afu.reset_n = reset_n[N_REG_STAGES - 1];
        end
        else
        begin : wire_reset_n
            assign to_afu.reset_n = to_fiu.reset_n;
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

                    // Don't put a long delay on almost full
                    reg_cp2af_sRx[s+1].c0TxAlmFull <= reg_cp2af_sRx[0].c0TxAlmFull;
                    reg_cp2af_sRx[s+1].c1TxAlmFull <= reg_cp2af_sRx[0].c1TxAlmFull;
                end
            end

            assign to_afu.sRx = reg_cp2af_sRx[N_REG_STAGES - 1];
        end
        else
        begin : wire_rx
            assign to_afu.sRx = to_fiu.sRx;
        end


        //
        // Register error signals
        //
        if (REGISTER_ERROR && N_REG_STAGES)
        begin : reg_err
            (* altera_attribute = {"-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PRESERVE_REGISTER ON"} *)
            logic reg_cp2af_error[N_REG_STAGES];

            always_ff @(posedge clk)
            begin
                reg_cp2af_error[0] <= to_fiu.error;
            end

            // Intermediate stages
            for (s = 0; s < N_REG_STAGES - 1; s = s + 1)
            begin
                always_ff @(posedge clk)
                begin
                    reg_cp2af_error[s+1] <= reg_cp2af_error[s];
                end
            end

            assign to_afu.error = reg_cp2af_error[N_REG_STAGES - 1];
        end
        else
        begin : wire_err
            assign to_afu.error = to_fiu.error;
        end
    endgenerate

endmodule // ofs_plat_shim_ccip_reg

