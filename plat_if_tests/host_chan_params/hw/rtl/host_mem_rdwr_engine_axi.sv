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
// AXI host memory test engine.
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
//   5: Byte-level write data mask. (Using a data mask makes the interface
//      consistent on CCI-P, Avalon and AXI.) The selected bytes must be
//      contiguous, with zeros only at the beginning and end.
//
//   6: Ready mask (for limiting receive rate on B and R channels.
//      Low bit of each range is the current cycle's ready value.
//      The mask rotates every cycle.
//       [63:32] - B mask
//       [31: 0] - R mask
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
//       [37:35] - Engine type (2 for AXI-MM)
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
//   6: Number of read burst responses (using AXI RLAST flag)
//

module host_mem_rdwr_engine_axi
  #(
    parameter ENGINE_NUMBER = 0,
    parameter ENGINE_GROUP = 0,
    parameter WRITE_FENCE_SUPPORTED = 0,
    parameter string ADDRESS_SPACE = "IOADDR"
    )
   (
    // Host memory (AXI)
    ofs_plat_axi_mem_if.to_slave host_mem_if,

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

    localparam ADDR_OFFSET_WIDTH = 32;
    typedef logic [ADDR_OFFSET_WIDTH-1 : 0] t_addr_offset;

    // Number of address bits that index a byte within a single bus-sized
    // line of data. This is the encoding of the AXI size field.
    localparam ADDR_BYTE_IDX_WIDTH = host_mem_if.ADDR_BYTE_IDX_WIDTH;
    typedef logic [ADDR_BYTE_IDX_WIDTH-1 : 0] t_byte_idx;

    localparam USER_WIDTH = host_mem_if.USER_WIDTH;
    typedef logic [USER_WIDTH-1 : 0] t_user;
    localparam RID_WIDTH = host_mem_if.RID_WIDTH;
    typedef logic [RID_WIDTH-1 : 0] t_rid;
    localparam WID_WIDTH = host_mem_if.WID_WIDTH;
    typedef logic [WID_WIDTH-1 : 0] t_wid;

    localparam COUNTER_WIDTH = 48;
    typedef logic [COUNTER_WIDTH-1 : 0] t_counter;

    // Number of bursts to request in a run (limiting run length)
    typedef logic [15:0] t_num_burst_reqs;

    logic [31:0] rd_data_sum, rd_data_hash;
    t_counter rd_bursts_req, rd_lines_req, rd_bursts_resp, rd_lines_resp;
    t_counter wr_bursts_req, wr_lines_req, wr_bursts_resp;

    //
    // Write configuration registers
    //

    t_addr rd_base_addr, wr_base_addr;
    t_addr_offset rd_start_addr_offset, wr_start_addr_offset;
    t_burst_cnt rd_req_burst_len, wr_req_burst_len;
    t_num_burst_reqs rd_num_burst_reqs, wr_num_burst_reqs;
    t_addr_offset base_addr_offset_mask;
    logic [63:0] wr_data_mask;
    logic [63:0] ready_mask;

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
                        rd_start_addr_offset <= csrs.wr_data[31:16];
                        rd_req_burst_len <= csrs.wr_data[15:0];
                    end
                4'h3:
                    begin
                        wr_num_burst_reqs <= csrs.wr_data[47:32];
                        wr_start_addr_offset <= csrs.wr_data[31:16];
                        wr_req_burst_len <= csrs.wr_data[15:0];
                    end
                4'h4: base_addr_offset_mask <= t_addr_offset'(csrs.wr_data);
                4'h5: wr_data_mask <= csrs.wr_data;
                4'h6: ready_mask <= csrs.wr_data;
            endcase // case (csrs.wr_idx)
        end

        if (!reset_n)
        begin
            wr_data_mask <= ~64'b0;
            ready_mask <= ~64'b0;
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
        csrs.rd_data[0] = { 13'h0,
                            1'(ccip_cfg_pkg::BYTE_EN_SUPPORTED),
                            3'(ENGINE_GROUP),
                            5'(ENGINE_NUMBER),
                            address_space_info(ADDRESS_SPACE),
                            1'b1,		   // Read responses are ordered
                            1'b0,                  // Write resopnse count is bursts
                            3'd2,                  // Engine type (AXI-MM)
                            csrs.status_active,
                            csrs.state_run,
                            csrs.state_reset,
                            16'(ADDR_OFFSET_WIDTH),
                            1'b0,
                            15'(1 << (host_mem_if.BURST_CNT_WIDTH-1)) };
        csrs.rd_data[1] = 64'(rd_bursts_req);
        csrs.rd_data[2] = 64'(rd_lines_resp);
        csrs.rd_data[3] = 64'(wr_lines_req);
        csrs.rd_data[4] = 64'(wr_bursts_resp);
        csrs.rd_data[5] = { rd_data_sum, rd_data_hash };
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
    t_addr_offset rd_cur_addr_offset, wr_cur_addr_offset;
    t_num_burst_reqs rd_num_burst_reqs_left, wr_num_burst_reqs_left;
    logic rd_unlimited, wr_unlimited;
    logic rd_done, wr_done;
    t_rid rd_id;
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
        host_mem_if.arvalid = (state_run && ! rd_done);

        host_mem_if.ar = '0;
        host_mem_if.ar.addr = { rd_base_addr + rd_cur_addr_offset,
                                t_byte_idx'(0) };
        host_mem_if.ar.size = host_mem_if.ADDR_BYTE_IDX_WIDTH;
        host_mem_if.ar.len = rd_req_burst_len - 1;
        host_mem_if.ar.id = rd_id;
        host_mem_if.ar.user = ~t_user'(rd_id);
    end

    always_ff @(posedge clk)
    begin
        // Was the read request accepted?
        if (state_run && ! rd_done && host_mem_if.arready)
        begin
            rd_cur_addr_offset <= (rd_cur_addr_offset + rd_req_burst_len) & base_addr_offset_mask;
            rd_num_burst_reqs_left <= rd_num_burst_reqs_left - 1;
            rd_id <= rd_id + 1;
            rd_done <= ! rd_unlimited && (rd_num_burst_reqs_left == t_num_burst_reqs'(1));
        end

        if (state_reset)
        begin
            rd_cur_addr_offset <= rd_start_addr_offset;
            rd_id <= 0;

            rd_num_burst_reqs_left <= rd_num_burst_reqs;
            rd_unlimited <= ~(|(rd_num_burst_reqs));
        end

        if (!reset_n || state_reset)
        begin
            rd_done <= 1'b0 || (rd_base_addr == t_addr'(0));
        end
    end

    // Rotate mask governing ready signal on R channel
    assign host_mem_if.rready = r_ready_mask[0];

    always_ff @(posedge clk)
    begin
        r_ready_mask <= { r_ready_mask[30:0], r_ready_mask[31] };

        if (!reset_n || state_reset)
        begin
            r_ready_mask <= ready_mask[31:0];
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
        hash32_en <= host_mem_if.rvalid && host_mem_if.rready;
        // Hash the high 16 bits and the low 16 bits of each line
        hash32_new_data <= { host_mem_if.r.data[DATA_WIDTH-1 -: 16],
                             host_mem_if.r.data[0 +: 16] };
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
    logic wr_sop, wr_eop;
    logic wr_fence_done;
    t_wid wr_id;
    logic [31:0] b_ready_mask;
    logic do_write_line;

    always_comb
    begin
        host_mem_if.awvalid = (state_run && (! wr_done || ! wr_fence_done)) &&
                               wr_sop && host_mem_if.wready;
        host_mem_if.aw = '0;
        host_mem_if.aw.addr = { wr_base_addr + wr_cur_addr_offset,
                                t_byte_idx'(0) };
        host_mem_if.aw.size = host_mem_if.ADDR_BYTE_IDX_WIDTH;
        host_mem_if.aw.len = wr_flits_left - 1;
        host_mem_if.aw.id = wr_id;
        host_mem_if.aw.user = ~t_user'(wr_id);

        // Emit a write fence at the end
        if (wr_done && ! wr_fence_done)
        begin
            host_mem_if.aw.addr = t_addr'(0);
            host_mem_if.aw.len = t_burst_cnt'(1);
            // Need to encode a fence -- not implemented yet
        end

        host_mem_if.wvalid = do_write_line;
        host_mem_if.w = '0;
        host_mem_if.w.data = t_data'(0);
        host_mem_if.w.data[$bits(t_data)-1 -: 64] = 64'hdeadbeef;
        host_mem_if.w.data[63 : 0] = 64'(wr_base_addr + wr_cur_addr_offset);
        host_mem_if.w.strb = wr_data_mask;
        host_mem_if.w.last = wr_eop;
    end

    assign do_write_line = ((state_run && !wr_done) || !wr_sop) &&
                           (!wr_sop || host_mem_if.awready) && host_mem_if.wready;

    always_ff @(posedge clk)
    begin
        // Was the write request accepted?
        if (do_write_line)
        begin
            // Advance one line, reduce the flit count by one
            wr_cur_addr_offset <= (wr_cur_addr_offset + t_addr_offset'(1)) & base_addr_offset_mask;
            wr_flits_left <= wr_flits_left - t_burst_cnt'(1);
            wr_eop <= (wr_flits_left == t_burst_cnt'(2));
            wr_sop <= 1'b0;
            wr_id <= wr_id + wr_sop;

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

        if (wr_done && ! wr_fence_done)
        begin
            wr_fence_done <= host_mem_if.awready && host_mem_if.wready;
        end

        if (state_reset)
        begin
            wr_cur_addr_offset <= wr_start_addr_offset;
            wr_flits_left <= wr_req_burst_len;
            wr_eop <= (wr_req_burst_len == t_burst_cnt'(1));
            wr_num_burst_reqs_left <= wr_num_burst_reqs;
            wr_unlimited <= ~(|(wr_num_burst_reqs));
            wr_id <= 0;
        end

        if (!reset_n || state_reset)
        begin
            wr_done <= (wr_base_addr == t_addr'(0));
            wr_fence_done <= (wr_base_addr == t_addr'(0)) || (WRITE_FENCE_SUPPORTED == 0);
            wr_sop <= 1'b1;
        end
    end

    // Rotate mask governing ready signal on B channel
    assign host_mem_if.bready = b_ready_mask[0];

    always_ff @(posedge clk)
    begin
        b_ready_mask <= { b_ready_mask[30:0], b_ready_mask[31] };

        if (!reset_n || state_reset)
        begin
            b_ready_mask <= ready_mask[63:32];
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
    t_burst_cnt incr_wr_resp_lines;

    always_ff @(posedge clk)
    begin
        incr_rd_req <= host_mem_if.arvalid && host_mem_if.arready;
        incr_rd_req_lines <= (host_mem_if.arvalid && host_mem_if.arready) ?
                             rd_req_burst_len : t_burst_cnt'(0);
        incr_rd_resp <= host_mem_if.rvalid && host_mem_if.r.last && host_mem_if.rready;
        incr_rd_resp_lines <= host_mem_if.rvalid && host_mem_if.rready;

        incr_wr_req <= host_mem_if.awvalid && host_mem_if.awready;
        incr_wr_req_lines <= host_mem_if.wvalid && host_mem_if.wready;
        incr_wr_resp <= host_mem_if.bvalid && host_mem_if.bready;
        incr_wr_resp_lines <= host_mem_if.bvalid && host_mem_if.bready ?
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

endmodule // host_mem_rdwr_engine_axi
