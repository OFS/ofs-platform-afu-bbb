//
// Copyright (c) 2020, Intel Corporation
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
// Compute the fairness of arbitration between two channels over time.
// Each channel takes a burst count each cycle. The difference between
// burst counts over a window in time is tracked. Binary signals
// are emitted indicating when to favor a channel in order to
// even out traffic.
//

module ofs_plat_prim_burstcount1_fairness
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

    // Track burst count as a signed value since the difference between
    // one channel and the other will be tracked.
    typedef logic signed [BURST_CNT_WIDTH:0] t_burstcount_delta;

    // Difference in active bursts between channels. Channel 0 is positive,
    // channel 1 is negative. This counter must have space for the largest
    // delta over HISTORY_DEPTH devents.
    typedef logic signed [BURST_CNT_WIDTH + $clog2(HISTORY_DEPTH+1) : 0] t_active_delta;
    t_active_delta ch_active_delta;

    // Updates for new traffic
    t_burstcount_delta new_delta;
    logic new_delta_valid;

    // Shift vector - history of burst deltas used to age out traffic over time
    t_burstcount_delta [HISTORY_DEPTH-1:0] delta_history_vec;

    // Track whether each channel has been active over the last few cycles.
    // Never favor an inactive channel.
    logic [HISTORY_DEPTH-1:0] ch0_active;
    logic [HISTORY_DEPTH-1:0] ch1_active;

    always_ff @(posedge clk)
    begin
        // New traffic
        new_delta <= (ch0_valid ? t_burstcount_delta'(ch0_burstcount) : '0) -
                     (ch1_valid ? t_burstcount_delta'(ch1_burstcount) : '0);
        new_delta_valid <= (ch0_valid || ch1_valid);

        // Update 
        if (new_delta_valid)
        begin
            // Add new delta and drop oldest history delta
            ch_active_delta <= ch_active_delta + new_delta - delta_history_vec[0];

            // Shift history vector and push the latest delta to it
            delta_history_vec[HISTORY_DEPTH-2:0] <= delta_history_vec[HISTORY_DEPTH-1:1];
            delta_history_vec[HISTORY_DEPTH-1] <= new_delta;
        end

        // Record whether channels are active
        if (ch0_valid || ch1_valid)
        begin
            ch0_active <= { ch0_active[HISTORY_DEPTH-2 : 0], ch0_valid };
            ch1_active <= { ch1_active[HISTORY_DEPTH-2 : 0], ch1_valid };
        end

        if (!reset_n)
        begin
            ch_active_delta <= '0;
            new_delta_valid <= 1'b0;
            delta_history_vec <= '0;

            ch0_active <= '0;
            ch1_active <= '0;
        end
    end

    // Compute fairness flags
    always_ff @(posedge clk)
    begin
        favor_ch0 <= (|(ch0_active)) && (ch_active_delta < -(t_active_delta'(FAIRNESS_THRESHOLD)));
        favor_ch1 <= (|(ch1_active)) && (ch_active_delta > t_active_delta'(FAIRNESS_THRESHOLD));
    end

endmodule // ofs_plat_prim_burstcount1_fairness
