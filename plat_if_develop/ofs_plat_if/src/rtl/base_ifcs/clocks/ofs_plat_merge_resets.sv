// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Combine resets from a pair of clock domains.
//

module ofs_plat_join_resets
   (
    input  logic a_clk,
    input  logic a_reset_n,

    input  logic b_clk,
    input  logic b_reset_n,

    // Joined reset is in clock domain "a"
    output logic a_joined_reset_n
    );

    logic joined_reset_n = 1'b0;
    assign a_joined_reset_n = joined_reset_n;

    logic b_reset_n_in_a;

    ofs_plat_prim_clock_crossing_reset b_to_a
       (
        .clk_src(b_clk),
        .clk_dst(a_clk),
        .reset_in(b_reset_n),
        .reset_out(b_reset_n_in_a)
        );

    always @(posedge a_clk)
    begin
        joined_reset_n <= a_reset_n && b_reset_n_in_a;
    end

endmodule // ofs_plat_join_resets
