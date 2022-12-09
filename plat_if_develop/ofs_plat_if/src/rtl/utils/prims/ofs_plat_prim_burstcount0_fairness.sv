// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Compute the fairness of arbitration between two channels over time.
// Each channel takes a burst count each cycle. The difference between
// burst counts over a window in time is tracked. Binary signals
// are emitted indicating when to favor a channel in order to
// even out traffic.
//

module ofs_plat_prim_burstcount0_fairness
  #(
    parameter BURST_CNT_WIDTH = 0,
    parameter HISTORY_DEPTH = 31,

    // Threshold at which a difference between channels is considered unfair
    parameter FAIRNESS_THRESHOLD = 3 << BURST_CNT_WIDTH
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Channel 0 - usually reads
    input  logic ch0_valid,
    input  logic [BURST_CNT_WIDTH-1:0] ch0_burstcount,

    // Channel 1 - usually writes
    input  logic ch1_valid,
    input  logic [BURST_CNT_WIDTH-1:0] ch1_burstcount,

    // Favor channel 0 because it has fewer outstanding requests than channel 1?
    output logic favor_ch0,
    // Favor channel 1 because it has fewer outstanding requests than channel 0?
    output logic favor_ch1
    );

    // Convert to burstcount1
    typedef logic [BURST_CNT_WIDTH:0] t_burstcount;
    logic ch0_burstcount1_valid, ch1_burstcount1_valid;
    t_burstcount ch0_burstcount1, ch1_burstcount1;

    always_ff @(posedge clk)
    begin
        ch0_burstcount1_valid <= ch0_valid;
        ch0_burstcount1 <= t_burstcount'(ch0_burstcount) + 1;

        ch1_burstcount1_valid <= ch1_valid;
        ch1_burstcount1 <= t_burstcount'(ch1_burstcount) + 1;

        if (!reset_n)
        begin
            ch0_burstcount1_valid <= 1'b0;
            ch1_burstcount1_valid <= 1'b0;
        end
    end

    ofs_plat_prim_burstcount1_fairness
      #(
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH+1),
        .HISTORY_DEPTH(HISTORY_DEPTH),
        .FAIRNESS_THRESHOLD(3 << (BURST_CNT_WIDTH+1))
        )
      f1
       (
        .clk,
        .reset_n,

        .ch0_valid(ch0_burstcount1_valid),
        .ch0_burstcount(ch0_burstcount1),

        .ch1_valid(ch1_burstcount1_valid),
        .ch1_burstcount(ch1_burstcount1),

        .favor_ch0,
        .favor_ch1
        );

endmodule // ofs_plat_prim_burstcount0_fairness
