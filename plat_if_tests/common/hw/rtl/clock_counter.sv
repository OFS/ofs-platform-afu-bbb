// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Count cycles of "count_clk", with all other ports in the "clk" domain.
//
module clock_counter
  #(
    parameter COUNTER_WIDTH = 16
    )
   (
    input  logic clk,
    input  logic count_clk,
    input  logic sync_reset_n,
    input  logic enable,
    output logic [COUNTER_WIDTH-1:0] count
    );

    // Convenient names that will be used to declare timing constraints for clock crossing
    (* preserve *) logic [COUNTER_WIDTH-1:0] cntclksync_count;
    (* preserve *) logic cntclksync_reset_n;
    (* preserve *) logic cntclksync_enable;

    logic [COUNTER_WIDTH-1:0] counter_value;

    always_ff @(posedge count_clk)
    begin
        cntclksync_count <= counter_value;
    end

    always_ff @(posedge clk)
    begin
        count <= cntclksync_count;
    end

    (* preserve *) logic reset_n_T1;
    (* preserve *) logic enable_T1;

    always_ff @(posedge count_clk)
    begin
        cntclksync_reset_n <= sync_reset_n;
        cntclksync_enable <= enable;

        reset_n_T1 <= cntclksync_reset_n;
        enable_T1 <= cntclksync_enable;
    end

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) counter
       (
        .clk(count_clk),
        .reset_n(reset_n_T1),
        .incr_by(COUNTER_WIDTH'(enable_T1)),
        .value(counter_value)
        );

endmodule
