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

interface host_chan_events_if
  #(
    parameter COUNTER_WIDTH = 48
    );

    typedef logic [COUNTER_WIDTH-1 : 0] t_counter;

    // Clock in the engine's clock domain (the engine is the consumer of
    // the sampling data connected here. All other signals in the interface
    // are clocked by eng_clk.
    wire eng_clk;
    logic eng_reset_n;

    // notEmpty indicates that requests are still active. A quiet system
    // should eventually transition to !notEmpty once all responses arrive.
    logic notEmpty;

    // Cycles in the host channel's clock domain and in eng_clk, used for
    // determining the frequency of the FIM interface's clock.
    t_counter eng_clk_cycle_count;
    t_counter fim_clk_cycle_count;
    logic enable_cycle_counter;

    // Number of read request elements (lines or DWORDS, depending on
    // the host channel type).
    t_counter num_rd_reqs;

    // Sum of the number of active read elements (same unit as the
    // host channel type). The sum can be used to compute average latency
    // in cycles using Little's Law: active_rd_req_sum / num_rd_reqs.
    t_counter active_rd_req_sum;

    // Maximum number of active read requests (lines or DWORDS)
    t_counter max_active_rd_reqs;

    logic unit_is_dwords;

    // Interface for the host channel monitor
    modport monitor
       (
        input  eng_clk,
        input  eng_reset_n,
        input  enable_cycle_counter,

        output notEmpty,
        output fim_clk_cycle_count, eng_clk_cycle_count,
        output num_rd_reqs, active_rd_req_sum, max_active_rd_reqs,
        output unit_is_dwords
        );

    // Interface for the host channel monitor
    modport engine
       (
        output eng_clk,
        output eng_reset_n,
        output enable_cycle_counter,

        input  notEmpty,
        input  fim_clk_cycle_count, eng_clk_cycle_count,
        input  num_rd_reqs, active_rd_req_sum, max_active_rd_reqs,
        input  unit_is_dwords
        );

endinterface // host_chan_events_if
