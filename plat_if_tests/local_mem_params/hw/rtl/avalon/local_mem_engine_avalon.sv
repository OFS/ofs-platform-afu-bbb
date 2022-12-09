// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
//       [55:45] - Reserved
//       [44]    - Writer esponse user error
//       [43]    - Read response user error
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
//   4: Number of write responses received
//
//   5: Read validation information
//       [63: 0] - Hash of lines read (for ordered memory interfaces)
//

module local_mem_engine_avalon
  #(
    parameter ENGINE_NUMBER = 0,
    parameter LM_AFU_USER_WIDTH = 4
    )
   (
    // Local memory (Avalon)
    ofs_plat_avalon_mem_if.to_sink local_mem_if,

    // Control
    engine_csr_if.engine csrs
    );

    import ofs_plat_local_mem_avalon_mem_pkg::*;

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

    localparam USER_WIDTH = local_mem_if.USER_WIDTH;
    localparam LM_AFU_USER_START = USER_WIDTH - LM_AFU_USER_WIDTH;
    // Device (PIM + FIM) user flags
    typedef logic [LM_AFU_USER_START-1 : 0] t_user_dev;
    // Portion of user field that doesn't include command flags (like FENCE)
    typedef logic [LM_AFU_USER_WIDTH-1 : 0] t_user_afu;

    localparam COUNTER_WIDTH = 48;
    typedef logic [COUNTER_WIDTH-1 : 0] t_counter;

    // Number of bursts to request in a run (limiting run length)
    typedef logic [15:0] t_num_burst_reqs;

    logic [63:0] rd_data_hash;
    t_counter rd_bursts_req, rd_lines_req, rd_lines_resp;
    t_counter wr_bursts_req, wr_lines_req, wr_bursts_resp;

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
    logic rd_user_error, wr_user_error;

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
                            11'h0,		   // Reserved
                            wr_user_error,         // 44: writeresponseuser error
                            rd_user_error,	   // 43: readresponseuser error
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
        csrs.rd_data[4] = 64'(wr_bursts_resp);
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
    t_user_afu rd_req_user, wr_req_user;
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
            rd_req_user <= rd_req_user + 1;
            rd_done <= ! rd_unlimited && (rd_num_burst_reqs_left == t_num_burst_reqs'(1));
        end

        if (state_reset)
        begin
            rd_cur_addr <= t_addr'(rd_start_addr);

            rd_num_burst_reqs_left <= rd_num_burst_reqs;
            rd_unlimited <= ~(|(rd_num_burst_reqs));

            // Pick some non-zero start value for the incrementing user tag so
            // it doesn't sync with the address or request ID. The test will
            // confirm that the user-tag extension is returned with the request.
            rd_req_user <= t_user_afu'(29);
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
    // Check that readresponseuser matches user on the request. The
    // request logic above incremenets the user field by one for each
    // request.
    //
    t_burst_cnt rd_rsp_burst_rem;
    t_user_afu rd_rsp_user;
    logic rd_rsp_sop;

    always_ff @(posedge clk)
    begin
        if (local_mem_if.readdatavalid)
        begin
            // Increment the expected value at the end of each burst.
            rd_rsp_burst_rem <= rd_rsp_burst_rem - 1;
            rd_rsp_sop <= 1'b0;

            if (rd_rsp_burst_rem == t_burst_cnt'(1))
            begin
                rd_rsp_user <= rd_rsp_user + 1;
                rd_rsp_burst_rem <= rd_req_burst_len;
                rd_rsp_sop <= 1'b1;
            end
        end

        if (state_reset)
        begin
            // Initial value of requests
            rd_rsp_user <= t_user_afu'(29);
            rd_rsp_burst_rem <= rd_req_burst_len;
            rd_rsp_sop <= 1'b1;
        end
    end


    //
    // Check the user response field.
    //
    always_ff @(posedge clk)
    begin
        if (reset_n && !state_reset)
        begin
            // synthesis translate_off
            if (rd_user_error) $fatal(2, "Aborting due to error");
            // synthesis translate_on

            if (local_mem_if.readdatavalid)
            begin
                // Only check the part of readresponseuser above the flag bits.
                // Flags are used (mostly by write requests) to trigger fences,
                // interrupts, etc. and are not guaranteed to be returned.
                if (local_mem_if.readresponseuser[USER_WIDTH-1 : LM_AFU_USER_START] !== rd_rsp_user)
                begin
                    // synthesis translate_off
                    $display("** ERROR ** %m: readresponseuser is 0x%x, expected 0x%x",
                             { local_mem_if.readresponseuser[USER_WIDTH-1 : LM_AFU_USER_START], t_user_dev'(0) },
                             { rd_rsp_user, t_user_dev'(0) });
                    // synthesis translate_on

                    rd_user_error <= 1'b1;
                end
            end
        end
        else
        begin
            rd_user_error <= 1'b0;
        end
    end


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

            if (wr_sop)
            begin
                wr_req_user <= wr_req_user + 1;
            end

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

            // Pick some non-zero start value for the incrementing user tag so
            // it doesn't sync with the address or request ID. The test will
            // confirm that the user-tag extension is returned with the request.
            wr_req_user <= t_user_afu'(13);
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
    // Check that writeresponseuser matches user on the request.
    //
    t_user_afu wr_rsp_user;

    always_ff @(posedge clk)
    begin
        if (local_mem_if.writeresponsevalid)
        begin
            wr_rsp_user <= wr_rsp_user + 1;
        end

        if (state_reset)
        begin
            // Initial value of requests
            wr_rsp_user <= t_user_afu'(13);
        end
    end


    //
    // Check the user response field.
    //
    always_ff @(posedge clk)
    begin
        if (reset_n && !state_reset)
        begin
            // synthesis translate_off
            if (wr_user_error) $fatal(2, "Aborting due to error");
            // synthesis translate_on

            if (local_mem_if.writeresponsevalid)
            begin
                // Only check the part of writeresponseuser above the flag bits.
                // Flags are used to trigger fences, interrupts, etc. and are not
                // guaranteed to be returned.
                if (local_mem_if.writeresponseuser[USER_WIDTH-1 : LM_AFU_USER_START] !== wr_rsp_user)
                begin
                    // synthesis translate_off
                    $display("** ERROR ** %m: writeresponseuser is 0x%x, expected 0x%x",
                             { local_mem_if.writeresponseuser[USER_WIDTH-1 : LM_AFU_USER_START], t_user_dev'(0) },
                             { wr_rsp_user, t_user_dev'(0) });
                    // synthesis translate_on

                    wr_user_error <= 1'b1;
                end
            end
        end
        else
        begin
            wr_user_error <= 1'b0;
        end
    end


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
            local_mem_if.user = { rd_req_user, t_user_dev'(0) };
        end
        else
        begin
            local_mem_if.address = wr_cur_addr;
            local_mem_if.read = 1'b0;
            local_mem_if.write = (state_run && ! wr_done) || ! wr_sop;
            local_mem_if.burstcount = wr_flits_left;
            local_mem_if.byteenable = wr_byteenable;
            local_mem_if.user = { wr_req_user, t_user_dev'(0) };
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
                              (rd_lines_req != rd_lines_resp) ||
                              (wr_bursts_req != wr_bursts_resp);
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
    logic incr_wr_resp;

    always_ff @(posedge clk)
    begin
        incr_rd_req <= local_mem_if.read && ! local_mem_if.waitrequest;
        incr_rd_req_lines <= (local_mem_if.read && ! local_mem_if.waitrequest) ?
                             local_mem_if.burstcount : t_burst_cnt'(0);
        incr_rd_resp <= local_mem_if.readdatavalid;

        incr_wr_req <= local_mem_if.write && ! local_mem_if.waitrequest &&
                       (local_mem_if.burstcount == wr_req_burst_len);
        incr_wr_req_lines <= local_mem_if.write && ! local_mem_if.waitrequest;
        incr_wr_resp <= local_mem_if.writeresponsevalid;
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

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) wr_resp
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_wr_resp)),
        .value(wr_bursts_resp)
        );

endmodule // local_mem_engine_avalon
