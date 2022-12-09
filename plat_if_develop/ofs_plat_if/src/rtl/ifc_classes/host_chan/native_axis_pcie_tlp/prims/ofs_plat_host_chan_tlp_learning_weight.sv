// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// When mapping a memory interface to TLPs, arbitration is required.
// The PIM's TLP arbitration monitors reads and writes in flight to determine
// fairness. Some randomness is required to cover a variety of workloads.
// The weighting of the random decisions depends on traffic patterns.
// This module picks weights dynamically by sampling fixed-length epochs.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_tlp_learning_weight
  #(
    parameter N_SAMPLE_CYCLES = 11171,
    parameter BURST_CNT_WIDTH = 0,

    // Shift factors can be used either to smooth traffic count sampling
    // or to change the relative weights of reads and writes. Traffic
    // counts are shifted right by the amount specified. E.g., shifting
    // RD by 1 and WR by 2 drops the low bit from both counts and gives
    // RD twice the weight of WR.
    parameter RD_TRAFFIC_CNT_SHIFT = 1,
    parameter WR_TRAFFIC_CNT_SHIFT = 1,

    parameter ENABLE_MASK_WIDTH = 32
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Reads
    input  logic rd_valid,
    input  logic [BURST_CNT_WIDTH-1:0] rd_burstcount,

    // Writes
    input  logic wr_valid,
    input  logic [BURST_CNT_WIDTH-1:0] wr_burstcount,

    input  logic update_favoring,
    output logic rd_enable_favoring,
    output logic wr_enable_favoring
    );

    typedef logic [$clog2(ENABLE_MASK_WIDTH)-1 : 0] t_enable_idx;

    // Counter of cycles within a sampling window
    typedef logic [$clog2(N_SAMPLE_CYCLES+1)-1 : 0] t_sample_cycle_cnt;

    // Total activity within a sampling window. Add a bit to avoid overflow
    // when summing traffic on both channels.
    localparam TOTAL_TRAFFIC_WIDTH = $clog2(N_SAMPLE_CYCLES) + BURST_CNT_WIDTH + 1;
    typedef logic [TOTAL_TRAFFIC_WIDTH-1:0] t_traffic_cnt;

    t_traffic_cnt prev_traffic_total;
    t_traffic_cnt cur_traffic_total;
    t_traffic_cnt cur_traffic_cnt[2];

    t_enable_idx cur_threshold[2];

    // Manage sampling windows
    logic start_new_window, start_new_window_q, start_new_window_qq;
    t_sample_cycle_cnt cycle_cnt;

    always_ff @(posedge clk)
    begin
        cycle_cnt <= cycle_cnt + 1;
        start_new_window <= (cycle_cnt == t_sample_cycle_cnt'(N_SAMPLE_CYCLES-1));

        start_new_window_q <= start_new_window;
        start_new_window_qq <= start_new_window_q;

        if (start_new_window)
        begin
            start_new_window <= 1'b0;
            cycle_cnt <= '0;
        end

        if (!reset_n)
        begin
            start_new_window <= 1'b0;
            cycle_cnt <= '0;
        end
    end

    //
    // Traffic counter
    //
    logic traffic_present[2];

    always_ff @(posedge clk)
    begin
        if (rd_valid)
        begin
            cur_traffic_cnt[0] <= cur_traffic_cnt[0] + rd_burstcount;
        end
        if (wr_valid)
        begin
            cur_traffic_cnt[1] <= cur_traffic_cnt[1] + wr_burstcount;
        end

        // Drop low bits, both to avoid overflow and to reduce jitter.
        cur_traffic_total <=
            t_traffic_cnt'(cur_traffic_cnt[0][TOTAL_TRAFFIC_WIDTH-1:RD_TRAFFIC_CNT_SHIFT]) +
            t_traffic_cnt'(cur_traffic_cnt[1][TOTAL_TRAFFIC_WIDTH-1:WR_TRAFFIC_CNT_SHIFT]);

        traffic_present[0] <= (cur_traffic_cnt[0] != t_traffic_cnt'(0));
        traffic_present[1] <= (cur_traffic_cnt[1] != t_traffic_cnt'(0));

        if (start_new_window)
        begin
            prev_traffic_total <= cur_traffic_total;
            cur_traffic_cnt[0] <= '0;
            cur_traffic_cnt[1] <= '0;
        end

        if (!reset_n)
        begin
            prev_traffic_total <= '0;
            cur_traffic_cnt[0] <= '0;
            cur_traffic_cnt[1] <= '0;
        end
    end


    //
    // Learn separate thresholds for read and write.
    //
    // Each channel is updated independently, with only one updated at a time
    // in order to isolate the effect of each change.
    //

    localparam MIN_THRESHOLD = 0;
    localparam MAX_THRESHOLD = ENABLE_MASK_WIDTH-1;

    logic learn_on_rd;
    logic next_is_learn_on_rd;
    logic [2:0] window_ctr;
    t_enable_idx wr_delta_up, wr_delta_down;
    logic [11:0] rand_val;

    always_ff @(posedge clk)
    begin
        if (start_new_window)
        begin
            learn_on_rd <= next_is_learn_on_rd;
            window_ctr <= window_ctr + 1;

            // Normal case -- change weight by one up or down per sampling interval
            wr_delta_up <= t_enable_idx'(1);
            wr_delta_down <= t_enable_idx'(1);

            // Infrequently, use a larger change in weight in order to climb out
            // of local bandwidth maximums.
            if (rand_val[3:1] == 3'b101)
            begin
                // More reads than writes? Allow more writes. Pick larger delta
                // when the read/write difference is large.
                if (cur_traffic_cnt[0] > (cur_traffic_cnt[1] + (cur_traffic_cnt[1] >> 3)))
                begin
                    wr_delta_up <= t_enable_idx'(4);
                end
                else if (!traffic_present[0] ||
                         (cur_traffic_cnt[0] > (cur_traffic_cnt[1] + (cur_traffic_cnt[1] >> 5))))
                begin
                    wr_delta_up <= t_enable_idx'(2);
                end

                // More writes than reads? Suppress writes.
                if (traffic_present[0])
                begin
                    if ((cur_traffic_cnt[0] + (cur_traffic_cnt[0] >> 3)) < cur_traffic_cnt[1])
                    begin
                        wr_delta_down <= t_enable_idx'(5);
                    end
                    else if ((cur_traffic_cnt[0] + (cur_traffic_cnt[0] >> 5)) < cur_traffic_cnt[1])
                    begin
                        wr_delta_down <= t_enable_idx'(3);
                    end
                end
            end
        end

        // Learn on read infrequently compared to learning on the write
        // channel. Often the read channel threshold is unused, and its
        // range is quite limited. Tuning the write channel is more
        // important for performance.
        next_is_learn_on_rd <= &(window_ctr);

        if (!reset_n)
        begin
            learn_on_rd <= 1'b0;
            next_is_learn_on_rd <= 1'b0;
            window_ctr <= '0;
            wr_delta_up <= '0;
            wr_delta_down <= '0;
        end
    end

    // 12 bit random number generator
    ofs_plat_prim_lfsr12 lfsr
       (
        .clk,
        .reset_n,
        .en(1'b1),
        .value(rand_val)
        );

    ofs_plat_host_chan_tlp_learning_weight_mgr
      #(
        .ENABLE_MASK_WIDTH(ENABLE_MASK_WIDTH),
        .TOTAL_TRAFFIC_WIDTH(TOTAL_TRAFFIC_WIDTH),
        // Reads are mostly unlimited
        .MIN_THRESHOLD(MAX_THRESHOLD - 4),
        .MAX_THRESHOLD(MAX_THRESHOLD)
        )
      weight_mgr_rd
       (
        .clk,
        .reset_n,

        // At the beginning of a new learning phase on read channel, change the
        // read channel threshold based on the previous read learning phase.
        .update_en(start_new_window && next_is_learn_on_rd),
        // During the read learning phase, update the learned new threshold
        // continuously. Only the final value will be used. The new
        // threshold will only be applied when update_en is set at the
        // start of the next read learning phase. Until then, the new
        // value is merely recorded in a side register.
        .learn_en(learn_on_rd && traffic_present[0]),

        .prev_traffic_total,
        .cur_traffic_total,

        .threshold_delta_up(t_enable_idx'(1)),
        .threshold_delta_down(t_enable_idx'(1)),

        .cur_threshold(cur_threshold[0])
        );

    ofs_plat_host_chan_tlp_learning_weight_mgr
      #(
        .ENABLE_MASK_WIDTH(ENABLE_MASK_WIDTH),
        .TOTAL_TRAFFIC_WIDTH(TOTAL_TRAFFIC_WIDTH),
        .MIN_THRESHOLD(MIN_THRESHOLD),
        .MAX_THRESHOLD(MAX_THRESHOLD)
        )
      weight_mgr_wr
       (
        .clk,
        .reset_n,

        // These fire in opposite phases from the RD control above.
        .update_en(start_new_window && !next_is_learn_on_rd),
        .learn_en(!learn_on_rd && traffic_present[1]),

        .prev_traffic_total,
        .cur_traffic_total,

        .threshold_delta_up(wr_delta_up),
        .threshold_delta_down(wr_delta_down),

        .cur_threshold(cur_threshold[1])
        );


    //
    // The enable mask array holds a collection of patterns that can be
    // applied to enable or disable reads or writes. The patterns range
    // from low density at index 0 (only one bit set) to high density at
    // index ENABLE_MASK_WIDTH-1 (all bits set). Enabled bits are spread
    // as evenly as possible throughout the available width.
    //
    typedef logic [ENABLE_MASK_WIDTH-1 : 0] t_enable_mask;

    t_enable_mask enable_mask_patterns[ENABLE_MASK_WIDTH];

    initial
    begin
        // The first half of the pattern sets only even bits, spreading
        // the enabled bits out as far as possible.
        enable_mask_patterns[0] = t_enable_mask'(1);
        for (int i = 1, b = ENABLE_MASK_WIDTH/2, s = ENABLE_MASK_WIDTH; i < ENABLE_MASK_WIDTH/2; i = i + 1)
        begin
            enable_mask_patterns[i] = enable_mask_patterns[i-1];
            enable_mask_patterns[i][b] = 1'b1;
            b = b + s;
            if (b >= ENABLE_MASK_WIDTH)
            begin
                s = s / 2;
                b = s / 2;
            end
        end

        // The second half of the array starts with all even bits set
        // (from index ENABLE_MASK_WIDTH/2-1) and repeats the pattern
        // from the first half in the odd bits. The pattern is easy
        // to repeat: take the corresponding entry from the first half
        // and shift it by one bit.
        for (int i = ENABLE_MASK_WIDTH/2; i < ENABLE_MASK_WIDTH; i = i + 1)
        begin
            enable_mask_patterns[i] =
                enable_mask_patterns[ENABLE_MASK_WIDTH/2-1] |
                (enable_mask_patterns[i-ENABLE_MASK_WIDTH/2] << 1);
        end
    end


    // The active enable mask for each channel
    t_enable_mask cur_mask[2];

    always_ff @(posedge clk)
    begin
        // Rotate masks
        if (update_favoring)
        begin
            cur_mask[0] <= { cur_mask[0][0], cur_mask[0][ENABLE_MASK_WIDTH-1:1] };
            cur_mask[1] <= { cur_mask[1][0], cur_mask[1][ENABLE_MASK_WIDTH-1:1] };
        end

        // Threshold changed? If so, pick up a new mask pattern.
        if (start_new_window_q)
        begin
            cur_mask[1] <= enable_mask_patterns[cur_threshold[1]];
        end

        // The read pattern is updated one cycle after the write
        // pattern. In sparse mask patterns, this reduces enable bit
        // overlaps between reads and writes. It also has reads follow
        // writes, which is an optimized pattern on some PCIe hardware.
        if (start_new_window_qq)
        begin
            cur_mask[0] <= enable_mask_patterns[cur_threshold[0]];
        end

        if (!reset_n)
        begin
            cur_mask[0] <= ~'0;
            cur_mask[1] <= ~'0;
        end
    end


    // All the logic in this module ultimately drives this output.
    always_ff @(posedge clk)
    begin
        rd_enable_favoring <= cur_mask[0][0];
        wr_enable_favoring <= cur_mask[1][0];
    end

endmodule // ofs_plat_host_chan_tlp_learning_weight


//
// Manage the learning and update phases for a single channel. The module
// is instantiated twice in the parent above, once per channel.
//
module ofs_plat_host_chan_tlp_learning_weight_mgr
  #(
    parameter ENABLE_MASK_WIDTH = 32,
    parameter TOTAL_TRAFFIC_WIDTH,

    parameter MIN_THRESHOLD = 0,
    parameter MAX_THRESHOLD = ENABLE_MASK_WIDTH-1
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Choose the next threshold (at the end of a sampling window). The new
    // choice isn't written to cur_threshold until update_en is set.
    input  logic learn_en,
    // Update cur_threshold based on the most recent learn_en cycle.
    // The update is driven by registered state, so set learn_en at
    // least one cycle before update_en.
    input  logic update_en,

    input  logic [TOTAL_TRAFFIC_WIDTH-1:0] prev_traffic_total,
    input  logic [TOTAL_TRAFFIC_WIDTH-1:0] cur_traffic_total,

    input  logic [$clog2(ENABLE_MASK_WIDTH)-1:0] threshold_delta_up,
    input  logic [$clog2(ENABLE_MASK_WIDTH)-1:0] threshold_delta_down,

    // Current threshold (index into mask pattern)
    output logic [$clog2(ENABLE_MASK_WIDTH)-1:0] cur_threshold
    );

    typedef logic [$clog2(ENABLE_MASK_WIDTH)-1:0] t_enable_idx;
    typedef logic [TOTAL_TRAFFIC_WIDTH-1:0] t_traffic_cnt;

    t_enable_idx next_threshold;

    t_enable_idx next_threshold_up, next_threshold_down;
    logic threshold_up_ok, threshold_down_ok;
    logic cur_delta_direction, next_delta_direction;

    always_ff @(posedge clk)
    begin
        // Pre-compute these to avoid addition in the same cycle as a decision.
        // cur_threshold only changes when start_new_window is true.
        next_threshold_up <= cur_threshold + threshold_delta_up;
        threshold_up_ok <= (cur_threshold <= (t_enable_idx'(MAX_THRESHOLD) - threshold_delta_up));

        next_threshold_down <= cur_threshold - threshold_delta_down;
        threshold_down_ok <= (cur_threshold >= (t_enable_idx'(MIN_THRESHOLD) + threshold_delta_down));

        if (learn_en)
        begin
            if (!threshold_down_ok)
            begin
                // Force upward threshold changes if at minimum
                next_threshold <= next_threshold_up;
                next_delta_direction <= 1'b1;
            end
            else if (!threshold_up_ok)
            begin
                // Force downward threshold changes if at maximum
                next_threshold <= next_threshold_down;
                next_delta_direction <= 1'b0;
            end
            else if (cur_traffic_total > prev_traffic_total)
            begin
                // Moving in the right direction.
                next_threshold <= (cur_delta_direction ? next_threshold_up : next_threshold_down);
                next_delta_direction <= cur_delta_direction;
            end
            else
            begin
                // Less traffic this window than previous. Try the other direction.
                next_threshold <= (cur_delta_direction ? next_threshold_down : next_threshold_up);
                next_delta_direction <= ~cur_delta_direction;
            end
        end

        if (update_en)
        begin
            cur_threshold <= next_threshold;
            cur_delta_direction <= next_delta_direction;
        end

        if (!reset_n)
        begin
            cur_delta_direction <= 1'b0;
            next_delta_direction <= 1'b0;
            cur_threshold <= t_enable_idx'((MIN_THRESHOLD + MAX_THRESHOLD + 1) / 2);
            next_threshold <= t_enable_idx'((MIN_THRESHOLD + MAX_THRESHOLD + 1) / 2);
        end
    end

endmodule // ofs_plat_host_chan_tlp_learning_weight_mgr
