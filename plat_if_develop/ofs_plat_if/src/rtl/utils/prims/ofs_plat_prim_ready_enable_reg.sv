// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Generic ready/enable pipeline register. This implementation is a simple,
// systolic pipeline with control shared by all registers in a chain.
// For a version that breaks apart control flow into separate stages
// see ofs_plat_prim_ready_enable_skid().
//

module ofs_plat_prim_ready_enable_reg
  #(
    parameter N_DATA_BITS = 32
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic enable_from_src,
    input  logic [N_DATA_BITS-1 : 0] data_from_src,
    output logic ready_to_src,

    output logic enable_to_dst,
    output logic [N_DATA_BITS-1 : 0] data_to_dst,
    input  logic ready_from_dst
    );

    assign ready_to_src = ready_from_dst || !enable_to_dst;

    always_ff @(posedge clk)
    begin
        if (ready_to_src)
        begin
            enable_to_dst <= enable_from_src;
            data_to_dst <= data_from_src;
        end

        if (!reset_n)
        begin
            enable_to_dst <= 1'b0;
        end
    end

endmodule // ofs_plat_prim_ready_enable_reg
