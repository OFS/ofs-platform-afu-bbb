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
// Host channel event tracker common code
//

`include "ofs_plat_if.vh"

module host_chan_events_common
  #(
    // Width of the read event counter updates
    parameter READ_CNT_WIDTH = 3,
    parameter UNIT_IS_DWORDS = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic [READ_CNT_WIDTH-1 : 0] rdReqCnt,
    input  logic [READ_CNT_WIDTH-1 : 0] rdRespCnt,

    // Send counted events to a specific traffic generator engine
    host_chan_events_if.monitor events
    );

    localparam COUNTER_WIDTH = events.COUNTER_WIDTH;
    typedef logic [COUNTER_WIDTH-1 : 0] t_counter;

    assign events.unit_is_dwords = 1'(UNIT_IS_DWORDS);

    //
    // Move control signals from the engine to clk.
    //
    logic eng_reset_n;
    ofs_plat_prim_clock_crossing_reg cc_reset
       (
        .clk_src(events.eng_clk),
        .clk_dst(clk),
        .r_in(events.eng_reset_n),
        .r_out(eng_reset_n)
        );

    // Number of lines currently in flight
    logic [READ_CNT_WIDTH-1 : 0] rd_cur_active_lines;

    always_ff @(posedge clk)
    begin
        rd_cur_active_lines <= rd_cur_active_lines + rdReqCnt - rdRespCnt;

        if (!reset_n)
        begin
            rd_cur_active_lines <= '0;
        end
    end

    logic [READ_CNT_WIDTH-1 : 0] rd_max_active_lines;
    always_ff @(posedge clk)
    begin
        if (rd_cur_active_lines > rd_max_active_lines)
        begin
            rd_max_active_lines <= rd_cur_active_lines;
        end

        if (!reset_n || !eng_reset_n)
        begin
            rd_max_active_lines <= '0;
        end
    end

    // Count total requested lines
    t_counter rd_total_n_lines;

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_total_lines
       (
        .clk,
        .reset_n(reset_n && eng_reset_n),
        .incr_by(COUNTER_WIDTH'(rdReqCnt)),
        .value(rd_total_n_lines)
        );

    // Count active lines over time
    t_counter rd_total_active_lines;

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_active_lines
       (
        .clk,
        .reset_n(reset_n && eng_reset_n),
        .incr_by(COUNTER_WIDTH'(rd_cur_active_lines)),
        .value(rd_total_active_lines)
        );


    //
    // Forward event info to the engine, crossing to its clock domain.
    //

    ofs_plat_prim_clock_crossing_reg cc_notEmpty
       (
        .clk_src(clk),
        .clk_dst(events.eng_clk),
        .r_in(|(rd_cur_active_lines)),
        .r_out(events.notEmpty)
        );

    ofs_plat_prim_clock_crossing_reg#(.WIDTH(COUNTER_WIDTH)) cc_reqs
       (
        .clk_src(clk),
        .clk_dst(events.eng_clk),
        .r_in(rd_total_n_lines),
        .r_out(events.num_rd_reqs)
        );

    ofs_plat_prim_clock_crossing_reg#(.WIDTH(COUNTER_WIDTH)) cc_active_req
       (
        .clk_src(clk),
        .clk_dst(events.eng_clk),
        .r_in(rd_total_active_lines),
        .r_out(events.active_rd_req_sum)
        );

    ofs_plat_prim_clock_crossing_reg#(.WIDTH(COUNTER_WIDTH)) cc_max_active_reqs
       (
        .clk_src(clk),
        .clk_dst(events.eng_clk),
        .r_in(COUNTER_WIDTH'(rd_max_active_lines)),
        .r_out(events.max_active_rd_reqs)
        );


    //
    // Cycle counters, used for determining the FIM interface frequency.
    //
    clock_counter#(.COUNTER_WIDTH(COUNTER_WIDTH))
      count_eng_clk_cycles
       (
        .clk(events.eng_clk),
        .count_clk(events.eng_clk),
        .sync_reset_n(events.eng_reset_n),
        .enable(events.enable_cycle_counter),
        .count(events.eng_clk_cycle_count)
        );

    clock_counter#(.COUNTER_WIDTH(COUNTER_WIDTH))
      count_fim_clk_cycles
       (
        .clk(events.eng_clk),
        .count_clk(clk),
        .sync_reset_n(events.eng_reset_n),
        .enable(events.enable_cycle_counter),
        .count(events.fim_clk_cycle_count)
        );

endmodule // host_chan_events_common
