// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// A simple clock crossing register that can be used only with values that
// change very slowly relative to both clocks. Signals such as reset_n or
// a power event can be passed here and timing constraints will be generated
// automatically.
//

module ofs_plat_prim_clock_crossing_reg
  #(
    parameter WIDTH = 1,
    parameter [WIDTH-1 : 0] INITIAL_VALUE = '0
    )
   (
    input  logic clk_src,
    input  logic clk_dst,

    input  logic [WIDTH-1 : 0] r_in,
    output logic [WIDTH-1 : 0] r_out
    );

    (* preserve *) logic [WIDTH-1:0] ofs_plat_cc_reg_vec[3:0] =
                                                    { INITIAL_VALUE,
                                                      INITIAL_VALUE,
                                                      INITIAL_VALUE,
                                                      INITIAL_VALUE };

    always @(posedge clk_src)
    begin
        ofs_plat_cc_reg_vec[0] <= r_in;
    end

    always @(posedge clk_dst)
    begin
        ofs_plat_cc_reg_vec[3:1] <= ofs_plat_cc_reg_vec[2:0];
    end

    assign r_out = ofs_plat_cc_reg_vec[3];

endmodule // ofs_plat_prim_clock_crossing_reg


//
// Convenience wrapper around the crossing register primitive
// for standard reset.
//
module ofs_plat_prim_clock_crossing_reset
  #(
    parameter ACTIVE_LOW = 1,
    parameter MAX_FANOUT = 50,
    parameter DUP_TREE_DEPTH = 6
    )
   (
    input  logic clk_src,
    input  logic clk_dst,

    input  logic reset_in,
    output logic reset_out
    );

    localparam bit INIT_VALUE = ACTIVE_LOW ? 1'b0 : 1'b1;

    logic reset_cc;

    ofs_plat_prim_clock_crossing_reg
      #(
        .WIDTH(1),
        .INITIAL_VALUE(INIT_VALUE)
        )
      cc
       (
        .clk_src(clk_src),
        .clk_dst(clk_dst),
        .r_in(reset_in),
        .r_out(reset_cc)
        );

    // Generate an automatically duplicated tree (minimum depth 2)
    localparam TREE_DEPTH = (DUP_TREE_DEPTH >= 2) ? DUP_TREE_DEPTH : 2;
    localparam MAX_FANOUT_STR = {"-name MAX_FANOUT ", $sformatf("%0d", MAX_FANOUT)};
    localparam DUP_HIERARCHY_STR = {"-name DUPLICATE_HIERARCHY_DEPTH ", $sformatf("%0d", TREE_DEPTH)};

    (* altera_attribute = {"-name DONT_MERGE_REGISTER ON; ", MAX_FANOUT_STR} *)
    reg [TREE_DEPTH-1:0] dup_tree = {TREE_DEPTH{INIT_VALUE}};

    (* altera_attribute = {"-name DONT_MERGE_REGISTER ON; ", MAX_FANOUT_STR, "; ", DUP_HIERARCHY_STR} *)
    reg dup_leaf = INIT_VALUE;

    always @(posedge clk_dst) begin
        dup_tree <= { dup_tree[TREE_DEPTH-2:0], reset_cc };
        dup_leaf <= dup_tree[TREE_DEPTH-1];
    end

    assign reset_out = dup_leaf;

endmodule // ofs_plat_prim_clock_crossing_reset


//
// A fake clock crossing constraint is applied to the
// output of this reset implementation. It is typically
// used to force Quartus to ignore timing of asynchronous
// resets on clock crossing FIFOs.
//
module ofs_plat_prim_clock_crossing_reset_async
  #(
    parameter ACTIVE_LOW = 1
    )
   (
    input  logic clk,

    input  logic reset_in,
    output logic reset_out
    );

    (* preserve *) logic ofs_plat_cc_reg_async = (ACTIVE_LOW ? 1'b0 : 1'b1);

    always @(posedge clk)
    begin
        ofs_plat_cc_reg_async <= reset_in;
    end

    assign reset_out = ofs_plat_cc_reg_async;

endmodule // ofs_plat_prim_clock_crossing_reset_async
