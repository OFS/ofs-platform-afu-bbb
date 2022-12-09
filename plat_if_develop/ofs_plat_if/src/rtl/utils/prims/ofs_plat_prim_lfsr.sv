// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

module ofs_plat_prim_lfsr12
  #(
    parameter INITIAL_VALUE = 12'b101001101011
    )
   (
    input  logic clk,
    input  logic reset_n,
    input  logic en,
    output logic [11:0] value
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            value <= INITIAL_VALUE;
        end
        else if (en)
        begin
            value[11] <= value[0];
            value[10] <= value[11];
            value[9]  <= value[10];
            value[8]  <= value[9];
            value[7]  <= value[8];
            value[6]  <= value[7];
            value[5]  <= value[6] ^ value[0];
            value[4]  <= value[5];
            value[3]  <= value[4] ^ value[0];
            value[2]  <= value[3];
            value[1]  <= value[2];
            value[0]  <= value[1] ^ value[0];
        end
    end

endmodule // ofs_plat_prim_lfsr12


module ofs_plat_prim_lfsr32
  #(
    parameter INITIAL_VALUE = 32'b1010011010110
    )
   (
    input  logic clk,
    input  logic reset_n,
    input  logic en,
    output logic [31:0] value
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            value <= INITIAL_VALUE;
        end
        else if (en)
        begin
            value[31] <= value[0];
            value[30] <= value[31];
            value[29] <= value[30];
            value[28] <= value[29];
            value[27] <= value[28];
            value[26] <= value[27];
            value[25] <= value[26];
            value[24] <= value[25];
            value[23] <= value[24];
            value[22] <= value[23];
            value[21] <= value[22];
            value[20] <= value[21];
            value[19] <= value[20];
            value[18] <= value[19];
            value[17] <= value[18];
            value[16] <= value[17];
            value[15] <= value[16];
            value[14] <= value[15];
            value[13] <= value[14];
            value[12] <= value[13];
            value[11] <= value[12];
            value[10] <= value[11];
            value[9]  <= value[10];
            value[8]  <= value[9];
            value[7]  <= value[8];
            value[6]  <= value[7] ^ value[0];
            value[5]  <= value[6];
            value[4]  <= value[5] ^ value[0];
            value[3]  <= value[4];
            value[2]  <= value[3] ^ value[0];
            value[1]  <= value[2] ^ value[0];
            value[0]  <= value[1] ^ value[0];
        end
    end

endmodule // ofs_plat_prim_lfsr32
