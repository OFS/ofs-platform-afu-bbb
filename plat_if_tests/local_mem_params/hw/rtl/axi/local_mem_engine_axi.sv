// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// AXI local memory test engine.
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
//   5: Ready mask (for limiting receive rate on B and R channels.
//      Low bit of each range is the current cycle's ready value.
//      The mask rotates every cycle.
//       [63:32] - B mask
//       [31: 0] - R mask
//
// Read status registers:
//
//   0: Engine configuration
//       [63:56] - Number of data bytes
//       [55:47] - Reserved
//       [46]    - Writer esponse ID error
//       [45]    - Read response ID error
//       [44]    - Writer esponse user error
//       [43]    - Read response user error
//       [42:40] - Request wait signals { wready, awready, arready }
//       [39]    - Read responses are ordered (when 1)
//       [38]    - Reserved
//       [37:35] - Engine type (2 for AXI)
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
//   6: Number of read burst responses (using AXI RLAST flag)
//

module local_mem_engine_axi
  #(
    parameter GROUP_ENGINE_NUMBER = 0,
    parameter LM_AFU_USER_WIDTH = 4,

    // Setting NUM_UNIQUE_MEM_REGIONS to a value great than one partitions the
    // address space into multiple unique address ranges by forcing a constant
    // value in the high address bits. The value comes from GROUP_ENGINE_NUMBER.
    parameter NUM_UNIQUE_MEM_REGIONS = 1
    )
   (
    // Local memory (AXI)
    ofs_plat_axi_mem_if.to_sink local_mem_if,

    // Control
    engine_csr_if.engine csrs
    );

    import ofs_plat_local_mem_axi_mem_pkg::*;

    logic clk;
    assign clk = local_mem_if.clk;

    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= local_mem_if.reset_n;
    end

    // AXI stores burst count - 1, unlike Avalon. Add an extra bit to the
    // counter so in the test code 1 means 1 beat.
    typedef logic [local_mem_if.BURST_CNT_WIDTH : 0] t_burst_cnt;

    // Forced high bits of the address, when enabled. A zero is left in the low bit
    // of UNIQUE_REGION_ID so that the test can be sloppy with address management
    // and a burst can wrap into the unused space.
    localparam UNIQUE_REGION_ID_SIZE = $clog2(NUM_UNIQUE_MEM_REGIONS) + 1;
    localparam bit [UNIQUE_REGION_ID_SIZE-1 : 0] UNIQUE_REGION_ID = { GROUP_ENGINE_NUMBER, 1'b0 };

    // Number of address bits that index a byte within a single bus-sized
    // line of data. This is the encoding of the AXI size field.
    localparam ADDR_BYTE_IDX_WIDTH = local_mem_if.ADDR_BYTE_IDX_WIDTH;
    typedef logic [ADDR_BYTE_IDX_WIDTH-1 : 0] t_byte_idx;

    // Address is to a line
    localparam ADDR_WIDTH = local_mem_if.ADDR_WIDTH - ADDR_BYTE_IDX_WIDTH -
                            (NUM_UNIQUE_MEM_REGIONS > 1 ? UNIQUE_REGION_ID_SIZE : 0);
    typedef logic [ADDR_WIDTH-1 : 0] t_addr;
    typedef logic [local_mem_if.ADDR_WIDTH - ADDR_BYTE_IDX_WIDTH - 1 : 0] t_line_addr;
    localparam DATA_WIDTH = local_mem_if.DATA_WIDTH;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    localparam USER_WIDTH = local_mem_if.USER_WIDTH;
    localparam LM_AFU_USER_START = USER_WIDTH - LM_AFU_USER_WIDTH;
    // Device (PIM + FIM) user flags
    typedef logic [LM_AFU_USER_START-1 : 0] t_user_dev;
    // Portion of user field that doesn't include command flags (like FENCE)
    typedef logic [LM_AFU_USER_WIDTH-1 : 0] t_user_afu;

    localparam RID_WIDTH = local_mem_if.RID_WIDTH;
    typedef logic [RID_WIDTH-1 : 0] t_rid;
    localparam WID_WIDTH = local_mem_if.WID_WIDTH;
    typedef logic [WID_WIDTH-1 : 0] t_wid;

    localparam COUNTER_WIDTH = 48;
    typedef logic [COUNTER_WIDTH-1 : 0] t_counter;

    // Number of bursts to request in a run (limiting run length)
    typedef logic [15:0] t_num_burst_reqs;

    logic [63:0] rd_data_hash;
    t_counter rd_bursts_req, rd_lines_req, rd_bursts_resp, rd_lines_resp;
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
    logic rd_id_error, wr_id_error;
    logic rd_user_error, wr_user_error;

    logic [63:0] ready_mask;

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
                4'h5: ready_mask <= csrs.wr_data;
            endcase // case (csrs.wr_idx)
        end

        if (!reset_n)
        begin
            rd_enabled <= 1'b0;
            wr_enabled <= 1'b0;
            wr_start_byteenable <= ~128'b0;
            ready_mask <= ~64'b0;
        end
    end


    //
    // Read status registers
    //
    always_comb
    begin
        csrs.rd_data[0] = { 8'(DATA_WIDTH / 8),
                            9'h0,                  // Reserved
                            wr_id_error,           // 46: b.id error
                            rd_id_error,           // 45: r.id error
                            wr_user_error,         // 44: b.user error
                            rd_user_error,         // 43: r.user error
                            local_mem_if.wready,
                            local_mem_if.awready,
                            local_mem_if.arready,
                            1'b1,                  // Read responses are ordered
                            1'b0,                  // Reserved
                            3'd2,                  // Engine type (AXI)
                            csrs.status_active,
                            csrs.state_run,
                            csrs.state_reset,
                            16'(ADDR_WIDTH),
                            1'b0,
                            15'(1 << (local_mem_if.BURST_CNT_WIDTH)) };
        csrs.rd_data[1] = 64'(rd_bursts_req);
        csrs.rd_data[2] = 64'(rd_lines_resp);
        csrs.rd_data[3] = 64'(wr_lines_req);
        csrs.rd_data[4] = 64'(wr_bursts_resp);
        csrs.rd_data[5] = rd_data_hash;
        csrs.rd_data[6] = 64'(rd_bursts_resp);

        for (int e = 7; e < csrs.NUM_CSRS; e = e + 1)
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
    t_rid rd_req_id;
    t_user_afu rd_req_user;
    logic [31:0] r_ready_mask;

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
    always_comb
    begin
        local_mem_if.arvalid = (state_run && ! rd_done);

        local_mem_if.ar = '0;
        local_mem_if.ar.addr = { t_line_addr'({UNIQUE_REGION_ID, rd_cur_addr}), t_byte_idx'(0) };
        local_mem_if.ar.size = local_mem_if.ADDR_BYTE_IDX_WIDTH;
        local_mem_if.ar.len = rd_req_burst_len - 1;
        local_mem_if.ar.id = rd_req_id;
        local_mem_if.ar.user = { rd_req_user, t_user_dev'(0) };
    end

    always_ff @(posedge clk)
    begin
        // Was the read request accepted?
        if (state_run && ! rd_done && local_mem_if.arready)
        begin
            rd_cur_addr <= rd_cur_addr + rd_req_burst_len;
            rd_num_burst_reqs_left <= rd_num_burst_reqs_left - 1;
            rd_req_id <= rd_req_id + 1;
            rd_req_user <= rd_req_user + 1;
            rd_done <= ! rd_unlimited && (rd_num_burst_reqs_left == t_num_burst_reqs'(1));
        end

        if (state_reset)
        begin
            rd_cur_addr <= t_addr'(rd_start_addr);

            // Pick some non-zero start value for the incrementing user tag and id
            // so they don't sync with the address. The test will confirm that
            // the user-tag extension is returned with the request.
            rd_req_id <= t_rid'(37);
            rd_req_user <= t_user_afu'(29);

            rd_num_burst_reqs_left <= rd_num_burst_reqs;
            rd_unlimited <= ~(|(rd_num_burst_reqs));
        end

        if (!reset_n || state_reset)
        begin
            rd_done <= ! rd_enabled;
        end
    end

    // Rotate mask governing ready signal on R channel
    assign local_mem_if.rready = r_ready_mask[0];

    always_ff @(posedge clk)
    begin
        r_ready_mask <= { r_ready_mask[30:0], r_ready_mask[31] };

        if (!reset_n || state_reset)
        begin
            r_ready_mask <= ready_mask[31:0];
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
        .new_data_en(local_mem_if.rvalid && local_mem_if.rready),
        .new_data(local_mem_if.r.data),
        .hash(rd_data_hash)
        );

    //
    // Check that the user and id fields in read responses match the
    // values that were passed with requests. This code assumes responses
    // are ordered.
    //
    t_rid rd_rsp_id;
    t_user_afu rd_rsp_user;

    always_ff @(posedge clk)
    begin
        if (local_mem_if.rvalid && local_mem_if.r.last && local_mem_if.rready)
        begin
            rd_rsp_id <= rd_rsp_id + 1;
            rd_rsp_user <= rd_rsp_user + 1;
        end

        if (state_reset)
        begin
            // Initial value of requests
            rd_rsp_id <= t_rid'(37);
            rd_rsp_user <= t_user_afu'(29);
        end
    end


    //
    // Check the user and id response fields.
    //
    always_ff @(posedge clk)
    begin
        if (reset_n && !state_reset)
        begin
            // synthesis translate_off
            if (rd_id_error) $fatal(2, "Aborting due to READ response id field error");
            if (rd_user_error) $fatal(2, "Aborting due to READ response user field error");
            // synthesis translate_on

            if (local_mem_if.rvalid && local_mem_if.rready)
            begin
                if (local_mem_if.r.id !== rd_rsp_id)
                begin
                    // synthesis translate_off
                    $display("** ERROR ** %m: r.id is 0x%x, expected 0x%x", local_mem_if.r.id, rd_rsp_id);
                    // synthesis translate_on

                    rd_id_error <= 1'b1;
                end

                // Only check the part of user field above the flag bits.
                // Flags are used (mostly by write requests) to trigger fences,
                // interrupts, etc. and are not guaranteed to be returned.
                if (local_mem_if.r.user[USER_WIDTH-1 : LM_AFU_USER_START] !== rd_rsp_user)
                begin
                    // synthesis translate_off
                    $display("** ERROR ** %m: r.user is 0x%x, expected 0x%x",
                             { local_mem_if.r.user[USER_WIDTH-1 : LM_AFU_USER_START], t_user_dev'(0) },
                             { rd_rsp_user, t_user_dev'(0) });
                    // synthesis translate_on

                    rd_user_error <= 1'b1;
                end
            end
        end
        else
        begin
            rd_id_error <= 1'b0;
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
    t_wid wr_req_id;
    t_user_afu wr_req_user;
    logic [31:0] b_ready_mask;

    logic do_write_line;
    assign do_write_line = ((state_run && !wr_done) || !wr_sop) &&
                           (!wr_sop || local_mem_if.awready) && local_mem_if.wready;

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
            wr_req_id <= wr_req_id + wr_sop;
            wr_req_user <= wr_req_user + wr_sop;

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

            // Pick some non-zero start value for the incrementing user tag and id
            // so they don't sync with the address. The test will confirm that
            // the user-tag extension is returned with the request.
            wr_req_id <= t_wid'(7);
            wr_req_user <= t_user_afu'(13);
        end

        if (!reset_n || state_reset)
        begin
            wr_done <= ! wr_enabled;
            wr_sop <= 1'b1;
        end
    end

    // Rotate mask governing ready signal on B channel
    assign local_mem_if.bready = b_ready_mask[0];

    always_ff @(posedge clk)
    begin
        b_ready_mask <= { b_ready_mask[30:0], b_ready_mask[31] };

        if (!reset_n || state_reset)
        begin
            b_ready_mask <= ready_mask[63:32];
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
        local_mem_if.awvalid = (state_run && ! wr_done) && wr_sop && local_mem_if.wready;
        local_mem_if.aw = '0;
        local_mem_if.aw.addr = { t_line_addr'({UNIQUE_REGION_ID, wr_cur_addr}), t_byte_idx'(0) };
        local_mem_if.aw.size = local_mem_if.ADDR_BYTE_IDX_WIDTH;
        local_mem_if.aw.len = wr_flits_left - 1;
        local_mem_if.aw.id = wr_req_id;
        local_mem_if.aw.user = { wr_req_user, t_user_dev'(0) };

        local_mem_if.wvalid = do_write_line;
        local_mem_if.w = '0;
        local_mem_if.w.data = wr_zeros ? '0 : wr_data;
        local_mem_if.w.strb = wr_byteenable;
        local_mem_if.w.last = wr_eop;
    end


    //
    // Check that user and id fields in write responses match the requests.
    //
    t_wid wr_rsp_id;
    t_user_afu wr_rsp_user;

    always_ff @(posedge clk)
    begin
        if (local_mem_if.bvalid && local_mem_if.bready)
        begin
            wr_rsp_id <= wr_rsp_id + 1;
            wr_rsp_user <= wr_rsp_user + 1;
        end

        if (state_reset)
        begin
            // Initial value of requests
            wr_rsp_id <= t_wid'(7);
            wr_rsp_user <= t_user_afu'(13);
        end
    end


    //
    // Test user response field.
    //
    always_ff @(posedge clk)
    begin
        if (reset_n && !state_reset)
        begin
            // synthesis translate_off
            if (wr_id_error) $fatal(2, "Aborting due to WRITE response id field error");
            if (wr_user_error) $fatal(2, "Aborting due to WRITE response user field error");
            // synthesis translate_on

            if (local_mem_if.bvalid && local_mem_if.bready)
            begin
                if (local_mem_if.b.id !== wr_rsp_id)
                begin
                    // synthesis translate_off
                    $display("** ERROR ** %m: b.id is 0x%x, expected 0x%x", local_mem_if.b.id, wr_rsp_id);
                    // synthesis translate_on

                    wr_id_error <= 1'b1;
                end

                // Only check the part of b.user above the flag bits.
                // Flags are used to trigger fences, interrupts, etc. and are not
                // guaranteed to be returned.
                if (local_mem_if.b.user[USER_WIDTH-1 : LM_AFU_USER_START] !== wr_rsp_user)
                begin
                    // synthesis translate_off
                    $display("** ERROR ** %m: b.user is 0x%x, expected 0x%x",
                             { local_mem_if.b.user[USER_WIDTH-1 : LM_AFU_USER_START], t_user_dev'(0) },
                             { wr_rsp_user, t_user_dev'(0) });
                    // synthesis translate_on

                    wr_user_error <= 1'b1;
                end
            end
        end
        else
        begin
            wr_id_error <= 1'b0;
            wr_user_error <= 1'b0;
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
                              (rd_bursts_req != rd_bursts_resp) ||
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
    logic incr_rd_resp, incr_rd_resp_lines;

    logic incr_wr_req;
    logic incr_wr_req_lines;
    logic incr_wr_resp;

    always_ff @(posedge clk)
    begin
        incr_rd_req <= local_mem_if.arvalid && local_mem_if.arready;
        incr_rd_req_lines <= (local_mem_if.arvalid && local_mem_if.arready) ?
                             rd_req_burst_len : t_burst_cnt'(0);
        incr_rd_resp <= local_mem_if.rvalid && local_mem_if.r.last && local_mem_if.rready;
        incr_rd_resp_lines <= local_mem_if.rvalid && local_mem_if.rready;

        incr_wr_req <= local_mem_if.awvalid && local_mem_if.awready;
        incr_wr_req_lines <= local_mem_if.wvalid && local_mem_if.wready;
        incr_wr_resp <= local_mem_if.bvalid && local_mem_if.bready;
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
        .value(rd_bursts_resp)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_resp_lines
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_rd_resp_lines)),
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

endmodule // local_mem_engine_axi
