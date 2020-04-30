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
// Avalon host memory test engine.
//

//
// Write control registers:
//
//   0: Base address of read buffer, assumed to aligned to the address mask in
//      register 2. Addresses will be construct using OR of a small page-level
//      counter in order to avoid large addition -- hence the alignment
//      requirement.
//
//   1: Base address of write buffer. Same alignment requirement as register 0.
//
//   2: Read control:
//       [63:48] - Reserved
//       [47:32] - Number of bursts (unlimited if 0)
//       [31:16] - Start address offset (relative to base address)
//       [15: 0] - Burst size
//
//   3: Write control (same as read control)
//
//   4: Address mask, applied to incremented address counters to limit address
//      ranges.
//
//
// Read status registers:
//
//   0: Engine configuration
//       [63:42] - Reserved
//       [41:40] - Address space (0 for IOVA, 1 for host physical, 2 reserved, 3 virtual)
//       [39]    - Read responses are ordered (when 1)
//       [38]    - Write response count is bursts or lines (bursts 0 / lines 1)
//       [37:35] - Engine type (1 for Avalon)
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

`default_nettype none

module host_mem_rdwr_engine_avalon
  #(
    parameter ENGINE_NUMBER = 0,
    parameter WRITE_FENCE_SUPPORTED = 1,
    parameter string ADDRESS_SPACE = "IOVA"
    )
   (
    // Host memory (Avalon)
    ofs_plat_avalon_mem_rdwr_if.to_slave host_mem_if,

    // Control
    engine_csr_if.engine csrs
    );

    logic clk;
    assign clk = host_mem_if.clk;
    logic reset_n;
    assign reset_n = host_mem_if.reset_n;

    typedef logic [host_mem_if.BURST_CNT_WIDTH-1 : 0] t_burst_cnt;

    // Address is to a line
    localparam ADDR_WIDTH = host_mem_if.ADDR_WIDTH;
    typedef logic [ADDR_WIDTH-1 : 0] t_addr;
    localparam DATA_WIDTH = host_mem_if.DATA_WIDTH;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    localparam ADDR_LOW_WIDTH = 32;
    typedef logic [ADDR_LOW_WIDTH-1 : 0] t_addr_low;

    localparam COUNTER_WIDTH = 48;
    typedef logic [COUNTER_WIDTH-1 : 0] t_counter;

    // Number of bursts to request in a run (limiting run length)
    typedef logic [15:0] t_num_burst_reqs;

    logic [31:0] rd_data_sum, rd_data_hash;
    t_counter rd_bursts_req, rd_lines_req, rd_lines_resp;
    t_counter wr_bursts_req, wr_lines_req, wr_bursts_resp;

    //
    // Write configuration registers
    //

    t_addr rd_base_addr, wr_base_addr;
    t_addr_low rd_start_addr_low, wr_start_addr_low;
    t_burst_cnt rd_req_burst_len, wr_req_burst_len;
    t_num_burst_reqs rd_num_burst_reqs, wr_num_burst_reqs;
    t_addr_low base_addr_low_mask;

    always_ff @(posedge clk)
    begin
        if (csrs.wr_req)
        begin
            case (csrs.wr_idx)
                4'h0: rd_base_addr <= t_addr'(csrs.wr_data);
                4'h1: wr_base_addr <= t_addr'(csrs.wr_data);
                4'h2:
                    begin
                        rd_num_burst_reqs <= csrs.wr_data[47:32];
                        rd_start_addr_low <= csrs.wr_data[31:16];
                        rd_req_burst_len <= csrs.wr_data[15:0];
                    end
                4'h3:
                    begin
                        wr_num_burst_reqs <= csrs.wr_data[47:32];
                        wr_start_addr_low <= csrs.wr_data[31:16];
                        wr_req_burst_len <= csrs.wr_data[15:0];
                    end
                4'h4: base_addr_low_mask <= t_addr_low'(csrs.wr_data);
            endcase // case (csrs.wr_idx)
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
            // Standard IOVA (through IOMMU, probably)
            return 2'h0;
    endfunction // address_space_info

    always_comb
    begin
        csrs.rd_data[0] = { 22'h0,
                            address_space_info(ADDRESS_SPACE),
                            1'b1,		   // Read responses are ordered
                            1'b0,                  // Write resopnse count is bursts
                            3'b1,                  // Engine type (Avalon)
                            csrs.status_active,
                            csrs.state_run,
                            csrs.state_reset,
                            16'(ADDR_LOW_WIDTH),
                            1'b0,
                            15'(1 << (host_mem_if.BURST_CNT_WIDTH-1)) };
        csrs.rd_data[1] = 64'(rd_bursts_req);
        csrs.rd_data[2] = 64'(rd_lines_resp);
        csrs.rd_data[3] = 64'(wr_lines_req);
        csrs.rd_data[4] = 64'(wr_bursts_resp);
        csrs.rd_data[5] = { rd_data_sum, rd_data_hash };

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
    t_addr_low rd_cur_addr_low, wr_cur_addr_low;
    t_num_burst_reqs rd_num_burst_reqs_left, wr_num_burst_reqs_left;
    logic rd_unlimited, wr_unlimited;
    logic rd_done, wr_done;

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
        host_mem_if.rd_address = rd_base_addr | (rd_cur_addr_low & base_addr_low_mask);
        host_mem_if.rd_read = (state_run && ! rd_done);
        host_mem_if.rd_burstcount = rd_req_burst_len;
        host_mem_if.rd_byteenable = ~64'b0;
        host_mem_if.rd_function = 1'b0;
    end

    always_ff @(posedge clk)
    begin
        // Was the read request accepted?
        if (state_run && ! rd_done && ! host_mem_if.rd_waitrequest)
        begin
            rd_cur_addr_low <= rd_cur_addr_low + rd_req_burst_len;
            rd_num_burst_reqs_left <= rd_num_burst_reqs_left - 1;
            rd_done <= ! rd_unlimited && (rd_num_burst_reqs_left == t_num_burst_reqs'(1));
        end

        if (state_reset)
        begin
            rd_cur_addr_low <= rd_start_addr_low;

            rd_num_burst_reqs_left <= rd_num_burst_reqs;
            rd_unlimited <= ~(|(rd_num_burst_reqs));
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
        hash32_en <= host_mem_if.rd_readdatavalid;
        // Hash the high 16 bits and the low 16 bits of each line
        hash32_new_data <= { host_mem_if.rd_readdata[DATA_WIDTH-1 -: 16],
                             host_mem_if.rd_readdata[0 +: 16] };
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

    always_comb
    begin
        host_mem_if.wr_address = wr_base_addr | (wr_cur_addr_low & base_addr_low_mask);
        host_mem_if.wr_write = (state_run && (! wr_done || ! wr_fence_done)) || ! wr_sop;
        host_mem_if.wr_burstcount = wr_flits_left;
        host_mem_if.wr_byteenable = ~64'b0;
        host_mem_if.wr_function = 1'b0;

        // Emit a write fence at the end
        if (wr_done && ! wr_fence_done)
        begin
            host_mem_if.wr_address = t_addr'(0);
            host_mem_if.wr_burstcount = t_burst_cnt'(1);
            host_mem_if.wr_function = 1'b1;
        end

        host_mem_if.wr_writedata = t_data'(0);
        host_mem_if.wr_writedata[$bits(t_data)-1 -: 64] = 64'hdeadbeef;
        host_mem_if.wr_writedata[63 : 0] = 64'(wr_base_addr | (wr_cur_addr_low & base_addr_low_mask));
    end

    always_ff @(posedge clk)
    begin
        // Was the write request accepted?
        if (((state_run && ! wr_done) || ! wr_sop) && ! host_mem_if.wr_waitrequest)
        begin
            // Advance one line, reduce the flit count by one
            wr_cur_addr_low <= wr_cur_addr_low + t_addr_low'(1);
            wr_flits_left <= wr_flits_left - t_burst_cnt'(1);
            wr_sop <= 1'b0;

            // Done with all flits in the burst?
            if (wr_flits_left == t_burst_cnt'(1))
            begin
                wr_num_burst_reqs_left <= wr_num_burst_reqs_left - 1;
                wr_done <= ! wr_unlimited && (wr_num_burst_reqs_left == t_num_burst_reqs'(1));
                wr_flits_left <= wr_req_burst_len;
                wr_sop <= 1'b1;
            end
        end

        if (wr_done && ! wr_fence_done)
        begin
            wr_fence_done <= ! host_mem_if.wr_waitrequest;
        end

        if (state_reset)
        begin
            wr_cur_addr_low <= wr_start_addr_low;
            wr_flits_left <= wr_req_burst_len;
            wr_num_burst_reqs_left <= wr_num_burst_reqs;
            wr_unlimited <= ~(|(wr_num_burst_reqs));
        end

        if (!reset_n || state_reset)
        begin
            wr_done <= (wr_base_addr == t_addr'(0));
            wr_fence_done <= (wr_base_addr == t_addr'(0)) || (WRITE_FENCE_SUPPORTED == 0);
            wr_sop <= 1'b1;
        end
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
    t_burst_cnt incr_wr_resp_lines;

    always_ff @(posedge clk)
    begin
        incr_rd_req <= host_mem_if.rd_read && ! host_mem_if.rd_waitrequest;
        incr_rd_req_lines <= (host_mem_if.rd_read && ! host_mem_if.rd_waitrequest) ?
                             host_mem_if.rd_burstcount : t_burst_cnt'(0);
        incr_rd_resp <= host_mem_if.rd_readdatavalid;

        incr_wr_req <= host_mem_if.wr_write && ! host_mem_if.wr_waitrequest &&
                       (host_mem_if.wr_function || (host_mem_if.wr_burstcount == wr_req_burst_len));
        incr_wr_req_lines <= host_mem_if.wr_write && ! host_mem_if.wr_waitrequest;
        incr_wr_resp <= host_mem_if.wr_writeresponsevalid;
        incr_wr_resp_lines <= host_mem_if.wr_writeresponsevalid ?
                              wr_req_burst_len : t_burst_cnt'(0);
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

endmodule // host_mem_rdwr_engine_avalon
