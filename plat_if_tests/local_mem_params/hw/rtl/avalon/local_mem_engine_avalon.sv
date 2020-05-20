//
// Copyright (c) 2019, Intel Corporation
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
// Avalon local memory test engine.
//

//
// Write control registers:
//
//   0: Read control:
//       [63:49] - Reserved
//       [48]    - Enable reads
//       [47:32] - Number of bursts (unlimited if 0)
//       [31:16] - Start address offset
//       [15: 0] - Burst size
//
//   1: Write control:
//       [63:50] - Reserved
//       [49]    - Write zero instead of test data
//       [48]    - Enable write
//       [47:32] - Number of bursts (unlimited if 0)
//       [31:16] - Start address offset
//       [15: 0] - Burst size
//
//   2: Write seed value (input to initial state of write data)
//
//   3: Byte enable masks (63:0)
//
//   4: Byte enable masks (127:64)
//
// Read status registers:
//
//   0: Engine configuration
//       [63:56] - Number of data bytes
//       [56:43] - Reserved
//       [42:40] - Request wait signals { 0, 0, waitrequest }
//       [39]    - Read responses are ordered (when 1)
//       [38]    - Reserved
//       [37:35] - Engine type (1 for Avalon)
//       [34]    - Engine active
//       [33]    - Engine running
//       [32]    - Engine in reset
//       [31:16] - Number of address bits
//       [15]    - Burst must be natural size and address alignment
//       [14: 0] - Maximum burst size
//
//   1: Number of read bursts requested
//
//   2: Number of read line responses
//
//   3: Number of write lines sent
//
//   5: Read validation information
//       [63: 0] - Hash of lines read (for ordered memory interfaces)
//

module local_mem_engine
  #(
    parameter ENGINE_NUMBER = 0
    )
   (
    // Local memory (Avalon)
    ofs_plat_avalon_mem_if.to_slave local_mem_if,

    // Control
    engine_csr_if.engine csrs
    );

    logic clk;
    assign clk = local_mem_if.clk;

    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= local_mem_if.reset_n;
    end

    typedef logic [local_mem_if.BURST_CNT_WIDTH-1 : 0] t_burst_cnt;

    // Address is to a line
    localparam ADDR_WIDTH = local_mem_if.ADDR_WIDTH;
    typedef logic [ADDR_WIDTH-1 : 0] t_addr;
    localparam DATA_WIDTH = local_mem_if.DATA_WIDTH;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    localparam COUNTER_WIDTH = 48;
    typedef logic [COUNTER_WIDTH-1 : 0] t_counter;

    // Number of bursts to request in a run (limiting run length)
    typedef logic [15:0] t_num_burst_reqs;

    logic [63:0] rd_data_hash;
    t_counter rd_bursts_req, rd_lines_req, rd_lines_resp;
    t_counter wr_bursts_req, wr_lines_req;

    //
    // Write configuration registers
    //

    logic rd_enabled, wr_enabled;
    logic [15:0] rd_start_addr;
    logic [15:0] wr_start_addr;
    t_burst_cnt rd_req_burst_len, wr_req_burst_len;
    t_num_burst_reqs rd_num_burst_reqs, wr_num_burst_reqs;
    logic [63:0] wr_seed;
    logic [127:0] wr_start_byteenable;
    logic wr_zeros;
    logic waitrequest_q;

    always_ff @(posedge clk)
    begin
        if (csrs.wr_req)
        begin
            case (csrs.wr_idx)
                4'h0:
                    begin
                        rd_enabled <= csrs.wr_data[48];
                        rd_num_burst_reqs <= csrs.wr_data[47:32];
                        rd_start_addr <= csrs.wr_data[31:16];
                        rd_req_burst_len <= csrs.wr_data[15:0];
                    end
                4'h1:
                    begin
                        wr_zeros <= csrs.wr_data[49];
                        wr_enabled <= csrs.wr_data[48];
                        wr_num_burst_reqs <= csrs.wr_data[47:32];
                        wr_start_addr <= csrs.wr_data[31:16];
                        wr_req_burst_len <= csrs.wr_data[15:0];
                    end
                4'h2: wr_seed <= csrs.wr_data;
                4'h3: wr_start_byteenable[63:0] <= csrs.wr_data;
                4'h4: wr_start_byteenable[127:64] <= csrs.wr_data;
            endcase // case (csrs.wr_idx)
        end

        if (!reset_n)
        begin
            rd_enabled <= 1'b0;
            wr_enabled <= 1'b0;
            wr_start_byteenable <= ~128'b0;
        end
    end


    //
    // Read status registers
    //
    always_comb
    begin
        csrs.rd_data[0] = { 8'(DATA_WIDTH / 8),
                            13'h0,		   // Reserved
                            2'b0,		   // Unused wait request (AXI needs them)
                            waitrequest_q,
                            1'b1,		   // Read responses are ordered
                            1'b0,                  // Reserved
                            3'b1,                  // Engine type (Avalon)
                            csrs.status_active,
                            csrs.state_run,
                            csrs.state_reset,
                            16'(ADDR_WIDTH),
                            1'b0,
                            15'(1 << (local_mem_if.BURST_CNT_WIDTH-1)) };
        csrs.rd_data[1] = 64'(rd_bursts_req);
        csrs.rd_data[2] = 64'(rd_lines_resp);
        csrs.rd_data[3] = 64'(wr_lines_req);
        csrs.rd_data[4] = 64'h0;
        csrs.rd_data[5] = rd_data_hash;

        for (int e = 6; e < csrs.NUM_CSRS; e = e + 1)
        begin
            csrs.rd_data[e] = 64'h0;
        end
    end


    // ====================================================================
    //
    // Engine execution. Generate memory traffic.
    //
    // ====================================================================

    logic state_reset;
    logic state_run;
    t_addr rd_cur_addr, wr_cur_addr;
    t_num_burst_reqs rd_num_burst_reqs_left, wr_num_burst_reqs_left;
    logic rd_unlimited, wr_unlimited;
    logic rd_done, wr_done;
    logic arb_do_read;

    always_ff @(posedge clk)
    begin
        state_reset <= csrs.state_reset;
        state_run <= csrs.state_run;

        if (!reset_n)
        begin
            state_reset <= 1'b0;
            state_run <= 1'b0;
        end
    end


    //
    // Generate read requests
    //
    always_ff @(posedge clk)
    begin
        // Was the read request accepted?
        if (state_run && ! rd_done && ! local_mem_if.waitrequest && arb_do_read)
        begin
            rd_cur_addr <= rd_cur_addr + rd_req_burst_len;
            rd_num_burst_reqs_left <= rd_num_burst_reqs_left - 1;
            rd_done <= ! rd_unlimited && (rd_num_burst_reqs_left == t_num_burst_reqs'(1));
        end

        if (state_reset)
        begin
            rd_cur_addr <= t_addr'(rd_start_addr);

            rd_num_burst_reqs_left <= rd_num_burst_reqs;
            rd_unlimited <= ~(|(rd_num_burst_reqs));
        end

        if (!reset_n || state_reset)
        begin
            rd_done <= ! rd_enabled;
        end
    end

    // Generate a check hash of read responses
    test_data_chk
      #(
        .DATA_WIDTH(DATA_WIDTH)
        )
      rd_chk
       (
        .clk,
        .reset_n(!state_reset),
        .new_data_en(local_mem_if.readdatavalid),
        .new_data(local_mem_if.readdata),
        .hash(rd_data_hash)
        );


    //
    // Generate write requests
    //
    t_burst_cnt wr_flits_left;
    logic wr_eop;
    logic wr_sop;
    t_data wr_data;
    logic [127:0] wr_byteenable;

    logic do_write_line;
    assign do_write_line = ((state_run && ! wr_done) || ! wr_sop) &&
                           ! local_mem_if.waitrequest &&
                           ! arb_do_read;

    always_ff @(posedge clk)
    begin
        // Was the write request accepted?
        if (do_write_line)
        begin
            // Advance one line, reduce the flit count by one
            wr_cur_addr <= wr_cur_addr + t_addr'(1);
            wr_flits_left <= wr_flits_left - t_burst_cnt'(1);
            wr_eop <= (wr_flits_left == t_burst_cnt'(2));
            wr_sop <= 1'b0;
            // Rotate byte enable mask
            wr_byteenable <= { wr_byteenable[126:0], wr_byteenable[127] };

            // Done with all flits in the burst?
            if (wr_eop)
            begin
                wr_num_burst_reqs_left <= wr_num_burst_reqs_left - 1;
                wr_done <= ! wr_unlimited && (wr_num_burst_reqs_left == t_num_burst_reqs'(1));
                wr_flits_left <= wr_req_burst_len;
                wr_eop <= (wr_req_burst_len == t_burst_cnt'(1));
                wr_sop <= 1'b1;
            end
        end

        if (state_reset)
        begin
            wr_cur_addr <= t_addr'(wr_start_addr);
            wr_flits_left <= wr_req_burst_len;
            wr_eop <= (wr_req_burst_len == t_burst_cnt'(1));
            wr_num_burst_reqs_left <= wr_num_burst_reqs;
            wr_unlimited <= ~(|(wr_num_burst_reqs));
            wr_byteenable <= wr_start_byteenable;
        end

        if (!reset_n || state_reset)
        begin
            wr_done <= ! wr_enabled;
            wr_sop <= 1'b1;
        end
    end

    // Generate write data
    test_data_gen
      #(
        .DATA_WIDTH(DATA_WIDTH)
        )
      wr_data_gen
       (
        .clk,
        .reset_n(!state_reset),
        .gen_next(do_write_line),
        .seed(wr_seed),
        .data(wr_data)
        );


    //
    // Pass requests to local memory
    //
    always_comb
    begin
        if (arb_do_read)
        begin
            local_mem_if.address = rd_cur_addr;
            local_mem_if.read = (state_run && ! rd_done);
            local_mem_if.write = 1'b0;
            local_mem_if.burstcount = rd_req_burst_len;
            local_mem_if.byteenable = ~64'b0;
        end
        else
        begin
            local_mem_if.address = wr_cur_addr;
            local_mem_if.read = 1'b0;
            local_mem_if.write = (state_run && ! wr_done) || ! wr_sop;
            local_mem_if.burstcount = wr_flits_left;
            local_mem_if.byteenable = wr_byteenable;
        end

        local_mem_if.writedata = wr_zeros ? '0 : wr_data;
    end

    // Read/write arbiter
    always_ff @(posedge clk)
    begin
        // Did a request go out this cycle?
        if (! local_mem_if.waitrequest)
        begin
            if (arb_do_read)
            begin
                // Did a read. Switch to write unless writes are done.
                arb_do_read <= wr_done;
            end
            else
            begin
                // Did a write. Switch to read if reads are active and the
                // current write burst is complete.
                arb_do_read <= ! rd_done && (wr_eop);
            end
        end

        waitrequest_q <= local_mem_if.waitrequest;

        if (!reset_n || state_reset)
        begin
            arb_do_read <= rd_enabled;
        end
    end


    // ====================================================================
    //
    // Engine state
    //
    // ====================================================================

    always_ff @(posedge clk)
    begin
        csrs.status_active <= (state_run && ! (rd_done && wr_done)) ||
                              ! wr_sop ||
                              (rd_lines_req != rd_lines_resp);
    end


    // ====================================================================
    //
    // Counters. The multicycle counter breaks addition up into multiple
    // cycles for timing.
    //
    // ====================================================================

    logic incr_rd_req;
    t_burst_cnt incr_rd_req_lines;
    logic incr_rd_resp;

    logic incr_wr_req;
    logic incr_wr_req_lines;

    always_ff @(posedge clk)
    begin
        incr_rd_req <= local_mem_if.read && ! local_mem_if.waitrequest;
        incr_rd_req_lines <= (local_mem_if.read && ! local_mem_if.waitrequest) ?
                             local_mem_if.burstcount : t_burst_cnt'(0);
        incr_rd_resp <= local_mem_if.readdatavalid;

        incr_wr_req <= local_mem_if.write && ! local_mem_if.waitrequest &&
                       (local_mem_if.burstcount == wr_req_burst_len);
        incr_wr_req_lines <= local_mem_if.write && ! local_mem_if.waitrequest;
    end

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_req
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_rd_req)),
        .value(rd_bursts_req)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_req_lines
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_rd_req_lines)),
        .value(rd_lines_req)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_resp
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_rd_resp)),
        .value(rd_lines_resp)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) wr_req
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_wr_req)),
        .value(wr_bursts_req)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) wr_req_lines
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_wr_req_lines)),
        .value(wr_lines_req)
        );

endmodule // local_mem_engine
