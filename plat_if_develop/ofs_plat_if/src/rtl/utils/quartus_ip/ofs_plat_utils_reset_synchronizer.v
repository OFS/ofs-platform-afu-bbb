// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

// $Id: //acds/rel/24.1/ip/iconnect/merlin/altera_reset_controller/altera_reset_synchronizer.v#1 $
// $Revision: #1 $
// $Date: 2024/02/01 $

// -----------------------------------------------
// Reset Synchronizer
// -----------------------------------------------
`timescale 1 ns / 1 ns

module ofs_plat_utils_reset_synchronizer
#(
    parameter ASYNC_RESET = 1,
    parameter DEPTH       = 2
)
(
    input   reset_in /* synthesis ALTERA_ATTRIBUTE = "SUPPRESS_DA_RULE_INTERNAL=R101" */,

    input   clk,
    output  reset_out
);

    // -----------------------------------------------
    // Synchronizer register chain. We cannot reuse the
    // standard synchronizer in this implementation 
    // because our timing constraints are different.
    //
    // Instead of cutting the timing path to the d-input 
    // on the first flop we need to cut the aclr input.
    // 
    // We omit the "preserve" attribute on the final
    // output register, so that the synthesis tool can
    // duplicate it where needed.
    // -----------------------------------------------
    (*preserve*) reg [DEPTH-1:0] ofs_plat_utils_reset_synchronizer_int_chain;
    reg ofs_plat_utils_reset_synchronizer_int_chain_out;

    generate if (ASYNC_RESET) begin

        // -----------------------------------------------
        // Assert asynchronously, deassert synchronously.
        // -----------------------------------------------
        always @(posedge clk or posedge reset_in) begin
            if (reset_in) begin
                ofs_plat_utils_reset_synchronizer_int_chain <= {DEPTH{1'b1}};
                ofs_plat_utils_reset_synchronizer_int_chain_out <= 1'b1;
            end
            else begin
                ofs_plat_utils_reset_synchronizer_int_chain[DEPTH-2:0] <= ofs_plat_utils_reset_synchronizer_int_chain[DEPTH-1:1];
                ofs_plat_utils_reset_synchronizer_int_chain[DEPTH-1] <= 0;
                ofs_plat_utils_reset_synchronizer_int_chain_out <= ofs_plat_utils_reset_synchronizer_int_chain[0];
            end
        end

        assign reset_out = ofs_plat_utils_reset_synchronizer_int_chain_out;
     
    end else begin

        // -----------------------------------------------
        // Assert synchronously, deassert synchronously.
        // -----------------------------------------------
        always @(posedge clk) begin
            ofs_plat_utils_reset_synchronizer_int_chain[DEPTH-2:0] <= ofs_plat_utils_reset_synchronizer_int_chain[DEPTH-1:1];
            ofs_plat_utils_reset_synchronizer_int_chain[DEPTH-1] <= reset_in;
            ofs_plat_utils_reset_synchronizer_int_chain_out <= ofs_plat_utils_reset_synchronizer_int_chain[0];
        end

        assign reset_out = ofs_plat_utils_reset_synchronizer_int_chain_out;
 
    end
    endgenerate

endmodule

