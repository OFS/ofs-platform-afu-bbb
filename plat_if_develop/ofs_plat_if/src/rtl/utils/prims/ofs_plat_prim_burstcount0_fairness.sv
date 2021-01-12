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
