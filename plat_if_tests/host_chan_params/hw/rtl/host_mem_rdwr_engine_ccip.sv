// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// CCI-P host memory test engine.
//

//
// Write control registers:
//
//   0: Base address of read buffer, assumed to be aligned to the address mask in
//      register 4. Addresses will be construct using OR of a small page-level
//      counter in order to avoid large addition -- hence the alignment
//      requirement.
//
//   1: Base address of write buffer. Same alignment requirement as register 0.
//
//   2: Read control:
//       [63:48] - Maximum active lines in flight (unlimited if 0)
//       [47:32] - Number of bursts (unlimited if 0)
//       [31:16] - Start address offset (relative to base address)
//       [15: 0] - Burst size
//
//   3: Write control (same as read control)
//
//   4: Address mask, applied to incremented address counters to limit address
//      ranges.
//
//   5: Byte-level write data mask. (Using a data mask makes the interface
//      consistent on CCI-P, Avalon and AXI.) The selected bytes must be
//      contiguous, with zeros only at the beginning and end.
//
//
// Read status registers:
//
//   0: Engine configuration
//       [63:51] - Reserved
//       [50]    - Masked write supported?
//       [49:47] - Engine group
//       [46:42] - Engine number
//       [41:40] - Address space (0 for IOADDR, 1 for host physical, 2 reserved, 3 virtual)
//       [39]    - Read responses are ordered (when 1)
//       [38]    - Write response count is bursts or lines (bursts 0 / lines 1)
//       [37:35] - Engine type (0 for CCI-P)
//       [34]    - Engine active
//       [33]    - Engine running
//       [32]    - Engine in reset
//       [31:16] - Maximum mask size
//       [15]    - Burst must be natural size and address alignment
//       [14: 0] - Maximum burst size
//
//   1: Number of read bursts requested
//
//   2: Number of read line responses
//
//   3: Number of write lines sent
//
//   4: Number of write burst responses
//
//   5: Read validation information
//       [63:32] - Simple checksum portions of lines read (for OOO memory)
//       [31: 0] - Hash of portions of lines read (for ordered memory interfaces)
//
//   8: Total active read lines in flight summed over each active cycle. This is
//      used to compute latency using Little's Law.
//
//   9: Total write lines in flight, similar to 8.
//
//  10: Number of read requests at the edge of the PR boundary to the FIM,
//      used for separating the read latency of the PIM vs. the FIM.
//      The units are FIM-dependent (e.g. lines for CCI-P and DWORDS for
//      PCIe TLP), but all that matters is the ratio of registers 11 and 10.
//       [63]    - Error flag. When set, indicates a mismatch between read
//                 requests and read responses.
//       [62: 0] - Counter value
//
//  11: Total active read requests at the FIM boundary, similar the AFU count
//      in register 8. Latency is register 11 / register 10 (in FIM clock cycles).
//
//  12: Measured maximum number of outstanding read lines.
//
//  13: Measured maximum number of outstanding requests (lines for CCI-P and
//      DWORDS for PCIe TLP).
//       [63]    - Unit is DWORDS if 1, lines of 0
//       [62: 0] - Counter value
//
//  14: FIM clock cycle counter, used along with register 15 to compute the FIM
//      clock's frequency.
//
//  15: AFU clock cycle counter, running along with the FIM counter in 14.
//

`default_nettype none

module host_mem_rdwr_engine_ccip
  #(
    parameter ENGINE_NUMBER = 0,
    parameter ENGINE_GROUP = 0,
    parameter WRITE_FENCE_SUPPORTED = 1,
    parameter string ADDRESS_SPACE = "IOADDR"
    )
   (
    // Host memory (CCI-P)
    ofs_plat_host_ccip_if.to_fiu host_mem_if,

    // Events, used for tracking latency through the FIM
    host_chan_events_if.engine host_chan_events_if,

    // Control
    engine_csr_if.engine csrs
    );

    import ccip_if_pkg::*;

    logic clk;
    assign clk = host_mem_if.clk;
    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= host_mem_if.reset_n;
    end

    // C2 unused (MMIO is handled in a different interface)
    assign host_mem_if.sTx.c2 = t_if_ccip_c2_Tx'(0);

    typedef logic [$bits(t_ccip_clLen) : 0] t_burst_cnt;

    // Address is to a line
    localparam ADDR_WIDTH = CCIP_CLADDR_WIDTH;
    typedef logic [ADDR_WIDTH-1 : 0] t_addr;
    localparam DATA_WIDTH = CCIP_CLDATA_WIDTH;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    localparam ADDR_OFFSET_WIDTH = 32;
    typedef logic [ADDR_OFFSET_WIDTH-1 : 0] t_addr_offset;

    localparam COUNTER_WIDTH = 48;
    typedef logic [COUNTER_WIDTH-1 : 0] t_counter;

    localparam LINE_COUNTER_WIDTH = 12;
    typedef logic [LINE_COUNTER_WIDTH-1 : 0] t_line_counter;

    // Number of bursts to request in a run (limiting run length)
    typedef logic [15:0] t_num_burst_reqs;

    logic [31:0] rd_data_sum, rd_data_hash;
    t_counter rd_bursts_req, rd_lines_req, rd_lines_resp;
    t_counter wr_bursts_req, wr_lines_req, wr_lines_resp;
    t_counter rd_total_active_lines, wr_total_active_lines;
    t_counter rd_measured_max_active_lines;

    //
    // Write configuration registers
    //

    t_addr rd_base_addr, wr_base_addr;
    t_addr_offset rd_start_addr_offset, wr_start_addr_offset;
    t_burst_cnt rd_req_burst_len, wr_req_burst_len;
    t_line_counter rd_max_active_lines, wr_max_active_lines;
    t_num_burst_reqs rd_num_burst_reqs, wr_num_burst_reqs;
    t_addr_offset base_addr_offset_mask;
    logic [63:0] wr_data_mask;

    always_ff @(posedge clk)
    begin
        if (csrs.wr_req)
        begin
            case (csrs.wr_idx)
                4'h0: rd_base_addr <= t_addr'(csrs.wr_data);
                4'h1: wr_base_addr <= t_addr'(csrs.wr_data);
                4'h2:
                    begin
                        rd_max_active_lines <= csrs.wr_data[48 +: LINE_COUNTER_WIDTH] - 1;
                        rd_num_burst_reqs <= csrs.wr_data[47:32];
                        rd_start_addr_offset <= csrs.wr_data[31:16];
                        rd_req_burst_len <= t_burst_cnt'(csrs.wr_data[15:0]);
                    end
                4'h3:
                    begin
                        wr_max_active_lines <= csrs.wr_data[48 +: LINE_COUNTER_WIDTH] - 1;
                        wr_num_burst_reqs <= csrs.wr_data[47:32];
                        wr_start_addr_offset <= csrs.wr_data[31:16];
                        wr_req_burst_len <= t_burst_cnt'(csrs.wr_data[15:0]);
                    end
                4'h4: base_addr_offset_mask <= t_addr_offset'(csrs.wr_data);
                4'h5: wr_data_mask <= csrs.wr_data;
            endcase // case (csrs.wr_idx)
        end

        if (!reset_n)
        begin
            wr_data_mask <= ~64'b0;
        end
    end


    //
    // Read status registers
    //

    function logic [1:0] address_space_info(string info);
        if (ADDRESS_SPACE == "HPA")
            // Host physical addresses
            return 2'h1;
        else if (ADDRESS_SPACE == "VA")
            // Process virtual addresses
            return 2'h3;
        else
            // Standard IOADDR (through IOMMU, probably)
            return 2'h0;
    endfunction // address_space_info

    always_comb
    begin
        for (int e = 0; e < csrs.NUM_CSRS; e = e + 1)
        begin
            csrs.rd_data[e] = 64'h0;
        end

        csrs.rd_data[0] = { 13'h0,
                            1'(ccip_cfg_pkg::BYTE_EN_SUPPORTED),
                            3'(ENGINE_GROUP),
                            5'(ENGINE_NUMBER),
                            address_space_info(ADDRESS_SPACE),
`ifdef TEST_PARAM_SORT_RD_RESP
                            1'b1,		   // Read responses are sorted
`else
                            1'b0,                  // Read responses are not sorted
`endif
                            1'b1,                  // Write resopnse count is lines
                            3'b0,                  // Engine type (CCI-P)
                            csrs.status_active,
                            csrs.state_run,
                            csrs.state_reset,
                            16'(ADDR_OFFSET_WIDTH),
                            1'b1,                  // Natural size/alignment required
                            15'(1 << ($bits(t_burst_cnt) - 1)) };
        csrs.rd_data[1] = 64'(rd_bursts_req);
        csrs.rd_data[2] = 64'(rd_lines_resp);
        csrs.rd_data[3] = 64'(wr_lines_req);
        csrs.rd_data[4] = 64'(wr_lines_resp);
        csrs.rd_data[5] = { rd_data_sum, rd_data_hash };

        csrs.rd_data[8] = 64'(rd_total_active_lines);
        csrs.rd_data[9] = 64'(wr_total_active_lines);
        csrs.rd_data[10] = { host_chan_events_if.notEmpty, 63'(host_chan_events_if.num_rd_reqs) };
        csrs.rd_data[11] = 64'(host_chan_events_if.active_rd_req_sum);
        csrs.rd_data[12] = 64'(rd_measured_max_active_lines);
        csrs.rd_data[13] = { host_chan_events_if.unit_is_dwords, 63'(host_chan_events_if.max_active_rd_reqs) };

        csrs.rd_data[14] = 64'(host_chan_events_if.fim_clk_cycle_count);
        csrs.rd_data[15] = 64'(host_chan_events_if.eng_clk_cycle_count);
    end


    // ====================================================================
    //
    // Engine execution. Generate memory traffic.
    //
    // ====================================================================

    logic state_reset;
    logic state_run;
    t_addr_offset rd_cur_addr_offset, wr_cur_addr_offset;
    t_num_burst_reqs rd_num_burst_reqs_left, wr_num_burst_reqs_left;
    logic rd_unlimited, wr_unlimited;
    logic rd_done, wr_done;

    // Track the number of lines in flight
    t_line_counter rd_cur_active_lines, wr_cur_active_lines;
    logic rd_line_quota_exceeded, wr_line_quota_exceeded;

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
    logic rd_valid;
    assign rd_valid = state_run && !rd_done && !rd_line_quota_exceeded &&
                      !host_mem_if.sRx.c0TxAlmFull;
    logic [7:0] rd_mdata;

    always_ff @(posedge clk)
    begin
        host_mem_if.sTx.c0.valid <= rd_valid;

        host_mem_if.sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
        host_mem_if.sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
        host_mem_if.sTx.c0.hdr.cl_len <= t_ccip_clLen'(rd_req_burst_len - t_burst_cnt'(1));
        host_mem_if.sTx.c0.hdr.address <= rd_base_addr + rd_cur_addr_offset;
        host_mem_if.sTx.c0.hdr.mdata <= t_ccip_mdata'(rd_mdata);

        if (!reset_n)
        begin
            host_mem_if.sTx.c0.valid <= 1'b0;
        end
    end

    always_ff @(posedge clk)
    begin
        // Was the read request accepted?
        if (rd_valid)
        begin
            rd_cur_addr_offset <= (rd_cur_addr_offset + rd_req_burst_len) & base_addr_offset_mask;
            rd_num_burst_reqs_left <= rd_num_burst_reqs_left - 1;
            rd_done <= ! rd_unlimited && (rd_num_burst_reqs_left == t_num_burst_reqs'(1));
            rd_mdata <= rd_mdata + 8'b1;
        end

        if (state_reset)
        begin
            rd_cur_addr_offset <= rd_start_addr_offset;

            rd_num_burst_reqs_left <= rd_num_burst_reqs;
            rd_unlimited <= ~(|(rd_num_burst_reqs));
            rd_mdata <= '0;
        end

        if (!reset_n || state_reset)
        begin
            rd_done <= 1'b0 || (rd_base_addr == t_addr'(0));
        end
    end

    //
    // Hash some of the data from each read line response for validating
    // correctness. Register the inputs and outputs for timing.
    //
    logic hash32_en;
    logic [31:0] hash32_value, hash32_new_data;

    hash32 hash_read_resps
       (
        .clk,
        .reset_n(!state_reset),
        .en(hash32_en),
        .new_data(hash32_new_data),
        .value(hash32_value)
        );

    always_ff @(posedge clk)
    begin
        hash32_en <= host_mem_if.sRx.c0.rspValid;
        // Hash the high 16 bits and the low 16 bits of each line
        hash32_new_data <= { host_mem_if.sRx.c0.data[DATA_WIDTH-1 -: 16],
                             host_mem_if.sRx.c0.data[0 +: 16] };
        rd_data_hash <= hash32_value;

        if (hash32_en)
        begin
            rd_data_sum <= rd_data_sum + hash32_new_data;
        end

        if (state_reset)
        begin
            rd_data_sum <= 32'b0;
        end
    end


    //
    // Generate write requests
    //
    t_burst_cnt wr_flits_left;
    logic wr_sop;
    logic wr_fence_done;
    logic [7:0] wr_mdata;

    // Masked write config
    t_ccip_mem_access_mode wr_mode;
    t_ccip_clByteIdx wr_byte_start, wr_byte_end, wr_byte_len;

    logic wr_valid;
    assign wr_valid = ((state_run && (!wr_done || !wr_fence_done) && !wr_line_quota_exceeded) || !wr_sop) &&
                      ! host_mem_if.sRx.c1TxAlmFull;

    always_ff @(posedge clk)
    begin
        host_mem_if.sTx.c1.valid <= wr_valid;

        host_mem_if.sTx.c1.hdr <= t_if_ccip_c1_Tx'(0);
        host_mem_if.sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
        host_mem_if.sTx.c1.hdr.address <= wr_base_addr + wr_cur_addr_offset;
        host_mem_if.sTx.c1.hdr.cl_len <= t_ccip_clLen'(wr_req_burst_len - t_burst_cnt'(1));
        host_mem_if.sTx.c1.hdr.sop <= wr_sop;
        host_mem_if.sTx.c1.hdr.mdata <= t_ccip_mdata'(wr_mdata);

        // Emit a write fence at the end
        if (wr_done && !wr_fence_done && !wr_line_quota_exceeded)
        begin
            host_mem_if.sTx.c1.hdr.req_type <= eREQ_WRFENCE;
            host_mem_if.sTx.c1.hdr.address <= t_addr'(0);
            host_mem_if.sTx.c1.hdr.cl_len <= eCL_LEN_1;
            host_mem_if.sTx.c1.hdr.sop <= 1'b0;
        end
        else
        begin
            host_mem_if.sTx.c1.hdr.mode <= wr_mode;
            host_mem_if.sTx.c1.hdr.byte_start <= wr_byte_start;
            host_mem_if.sTx.c1.hdr.byte_len <= wr_byte_len;
        end

        host_mem_if.sTx.c1.data <= t_data'(0);
        host_mem_if.sTx.c1.data[$bits(t_data)-1 -: 64] <= 64'hdeadbeef;
        host_mem_if.sTx.c1.data[63 : 0] <= 64'(wr_base_addr + wr_cur_addr_offset);
    end

    always_ff @(posedge clk)
    begin
        // Was the write request accepted?
        if (wr_valid && !wr_done)
        begin
            // Advance one line, reduce the flit count by one
            wr_cur_addr_offset <= (wr_cur_addr_offset + t_addr_offset'(1)) & base_addr_offset_mask;
            wr_flits_left <= wr_flits_left - t_burst_cnt'(1);
            wr_sop <= 1'b0;

            // Done with all flits in the burst?
            if (wr_flits_left == t_burst_cnt'(1))
            begin
                wr_num_burst_reqs_left <= wr_num_burst_reqs_left - 1;
                wr_done <= ! wr_unlimited && (wr_num_burst_reqs_left == t_num_burst_reqs'(1));
                wr_flits_left <= wr_req_burst_len;
                wr_sop <= 1'b1;
                wr_mdata <= wr_mdata + 8'b1;
            end
        end

        if (wr_done && !wr_fence_done && !wr_line_quota_exceeded)
        begin
            wr_fence_done <= ! host_mem_if.sRx.c1TxAlmFull;
        end

        if (state_reset)
        begin
            wr_cur_addr_offset <= wr_start_addr_offset;
            wr_flits_left <= wr_req_burst_len;
            wr_num_burst_reqs_left <= wr_num_burst_reqs;
            wr_unlimited <= ~(|(wr_num_burst_reqs));
            wr_mdata <= '0;
        end

        if (!reset_n || state_reset)
        begin
            wr_done <= (wr_base_addr == t_addr'(0));
            wr_fence_done <= (wr_base_addr == t_addr'(0)) || (WRITE_FENCE_SUPPORTED == 0);
            wr_sop <= 1'b1;
        end
    end

    // Convert mask for writes into byte_start/byte_len
    always_ff @(posedge clk)
    begin
        // Masked write will have a zero in either the low or high bit
        wr_mode <= (wr_data_mask[63] & wr_data_mask[0]) ? eMOD_CL : eMOD_BYTE;

        // First byte to write
        for (int i = 0; i <= 63; i = i + 1)
        begin
            if (wr_data_mask[i])
            begin
                wr_byte_start <= t_ccip_clByteIdx'(i);
                break;
            end
        end

        // Last byte to write
        for (int i = 0; i <= 63; i = i + 1)
        begin
            if (wr_data_mask[i])
            begin
                wr_byte_end <= t_ccip_clByteIdx'(i);
            end
        end

        // Length. This takes an extra cycle to converge. There will be at
        // least a cycle between mask update and the write command.
        wr_byte_len <= wr_byte_end - wr_byte_start + 1;
    end


    // ====================================================================
    //
    // Engine state
    //
    // ====================================================================

    always_ff @(posedge clk)
    begin
        csrs.status_active <= (state_run && ! (rd_done && wr_done && wr_fence_done)) ||
                              ! wr_sop ||
                              (rd_lines_req != rd_lines_resp) ||
                              (wr_lines_req != wr_lines_resp);
    end


    // ====================================================================
    //
    // Events from FIM latency tracking
    //
    // ====================================================================

    assign host_chan_events_if.eng_clk = clk;

    logic [2:0] eng_reset_n = '0;
    assign host_chan_events_if.eng_reset_n = eng_reset_n[0];
    always @(posedge clk)
    begin
        eng_reset_n[2] <= reset_n && !state_reset;
        eng_reset_n[1:0] <= eng_reset_n[2:1];
    end

    always_ff @(posedge clk)
    begin
        host_chan_events_if.enable_cycle_counter <= csrs.status_active;
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
    t_burst_cnt incr_wr_resp_lines;

    // New lines requested this cycle
    t_burst_cnt rd_new_req_lines;
    assign rd_new_req_lines = rd_valid ? rd_req_burst_len : t_burst_cnt'(0);
    t_burst_cnt wr_new_req_lines;
    assign wr_new_req_lines = t_burst_cnt'(host_mem_if.sTx.c1.valid);

    always_ff @(posedge clk)
    begin
        incr_rd_req <= rd_valid;
        incr_rd_req_lines <= rd_new_req_lines;
        incr_rd_resp <= host_mem_if.sRx.c0.rspValid;

        incr_wr_req <= host_mem_if.sTx.c1.valid &&
                       (host_mem_if.sTx.c1.hdr.sop ||
                        (host_mem_if.sTx.c1.hdr.req_type == eREQ_WRFENCE));
        incr_wr_req_lines <= host_mem_if.sTx.c1.valid;
        if (host_mem_if.sRx.c1.rspValid)
        begin
            if (host_mem_if.sRx.c1.hdr.format && (host_mem_if.sRx.c1.hdr.resp_type == eRSP_WRLINE))
                incr_wr_resp_lines <= t_burst_cnt'(host_mem_if.sRx.c1.hdr.cl_num) + 1;
            else
                incr_wr_resp_lines <= t_burst_cnt'(1);
        end
        else
        begin
            incr_wr_resp_lines <= t_burst_cnt'(0);
        end
    end

    // Track the number of lines in flight
    always_ff @(posedge clk)
    begin
        rd_cur_active_lines <= rd_cur_active_lines + rd_new_req_lines - host_mem_if.sRx.c0.rspValid;
        rd_line_quota_exceeded <= ((rd_cur_active_lines + rd_new_req_lines) > rd_max_active_lines);

        wr_cur_active_lines <= wr_cur_active_lines + wr_new_req_lines - incr_wr_resp_lines;
        wr_line_quota_exceeded <= ((wr_cur_active_lines + wr_new_req_lines) > wr_max_active_lines);

        if (rd_cur_active_lines > rd_measured_max_active_lines)
        begin
            rd_measured_max_active_lines <= rd_cur_active_lines;
        end

        if (!reset_n || state_reset)
        begin
            rd_cur_active_lines <= '0;
            rd_line_quota_exceeded <= 1'b0;

            rd_measured_max_active_lines <= '0;

            wr_cur_active_lines <= '0;
            wr_line_quota_exceeded <= 1'b0;
        end
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
        .incr_by(COUNTER_WIDTH'(incr_wr_resp_lines)),
        .value(wr_lines_resp)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_active_lines
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(rd_cur_active_lines)),
        .value(rd_total_active_lines)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) wr_active_lines
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(wr_cur_active_lines)),
        .value(wr_total_active_lines)
        );

endmodule // host_mem_rdwr_engine_ccip
