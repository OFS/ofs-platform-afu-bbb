// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// AXI host memory atomics test engine. If all you want to do is see an example
// of updating a location atomically, this test is a overly complicated. Most
// of the code exists to validate that the behavior of the PIM and PCIe SS
// are correct. The actual atomic update is flagged below with asterisks.
//

//
// Write control registers:
//
//   0: Byte base address of atomic update buffer, assumed to be aligned to the
//      address mask in register 4. Addresses will be construct using OR of
//      a small page-level counter in order to avoid large addition -- hence
//      the alignment requirement.
//
//   1: Byte base address of write buffer. Same alignment requirement as register 0.
//      Read responses from atomic updates will be written to this buffer.
//
//   2: Byte base address of read buffer. Same alignment requirement as register 0.
//      Non-atomic read traffic from this buffer can be requested in order
//      to test mixed reads and atomic updates.
//
//   3: Test configuration:
//       [63:19] - Unused
//       [18]    - Enable read traffic (tests mixed normal/atomic traffic)
//       [17]    - Enable writes of atomic responses to write buffer
//       [16]    - 0: 32 bit requests, 1: 64 bit requests
//       [15: 8] - Number of read requests to generate
//       [ 7: 0] - Number of atomic requests to generate
//
//   4: Address mask, applied to incremented address counters to limit address
//      ranges.
//
//
// Read status registers:
//
//   0: Engine configuration
//       [63:52] - Reserved
//       [51]    - Read data error
//       [50]    - Atomic requests supported? (Give up if false!)
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
//       [14: 0] - Data bus width (bytes)
//
//   1: Number of atomic requests
//
//   2: Number of atomic read responses
//
//   3: Number of write requests
//
//   4: Number of write responses
//
//   5: Number of read requests
//
//   6: Number of read responses
//

`include "ofs_plat_if.vh"

module host_mem_atomic_engine_axi
  #(
    parameter ENGINE_NUMBER = 0,
    parameter ENGINE_GROUP = 0,
    parameter string ADDRESS_SPACE = "IOADDR"
    )
   (
    // Host memory (AXI)
    ofs_plat_axi_mem_if.to_sink host_mem_if,

    // Control
    engine_csr_if.engine csrs
    );

    import ofs_plat_host_chan_axi_mem_pkg::*;

    logic clk;
    assign clk = host_mem_if.clk;
    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= host_mem_if.reset_n;
    end

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

    typedef logic [7:0] t_num_reqs;

    //
    // Write configuration registers
    //

    t_addr atomic_base_addr, wb_base_addr, rd_base_addr;
    t_num_reqs atomic_num_reqs, rd_num_reqs;
    t_addr_offset base_addr_offset_mask;
    logic wb_req_enable, rd_req_enable;
    // 32 or 64 bit atomic request size flag
    logic mode_64bit;

    always_ff @(posedge clk)
    begin
        if (csrs.wr_req)
        begin
            case (csrs.wr_idx)
                4'h0: atomic_base_addr <= t_addr'(csrs.wr_data[63:ADDR_BYTE_IDX_WIDTH]);
                4'h1: wb_base_addr <= t_addr'(csrs.wr_data[63:ADDR_BYTE_IDX_WIDTH]);
                4'h2: rd_base_addr <= t_addr'(csrs.wr_data[63:ADDR_BYTE_IDX_WIDTH]);
                4'h3:
                    begin
                        rd_req_enable <= csrs.wr_data[18];
                        wb_req_enable <= csrs.wr_data[17];
                        mode_64bit <= csrs.wr_data[16];
                        rd_num_reqs <= csrs.wr_data[15:8];
                        atomic_num_reqs <= csrs.wr_data[7:0];
                    end
                4'h4: base_addr_offset_mask <= t_addr_offset'(csrs.wr_data[63:ADDR_BYTE_IDX_WIDTH]);
            endcase // case (csrs.wr_idx)
        end
    end


    //
    // Read status registers
    //

    logic rd_error_flag;
    t_counter num_atomic_reqs, num_atomic_rd_resps, num_atomic_wr_resps;
    t_counter num_wb_reqs, num_wb_resps;
    t_counter num_rd_reqs, num_rd_resps;

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

        csrs.rd_data[0] = { 12'h0,
                            rd_error_flag,
`ifdef OFS_PLAT_PARAM_HOST_CHAN_ATOMICS
                            1'b1,		   // Atomic requests supported by FIM
`else
                            1'b0,		   // Atomic requests not supported!
`endif
                            3'(ENGINE_GROUP),
                            5'(ENGINE_NUMBER),
                            address_space_info(ADDRESS_SPACE),
                            1'b1,		   // Read responses are ordered
                            1'b0,                  // Write response count is bursts
                            3'd2,                  // Engine type (AXI-MM)
                            csrs.status_active,
                            csrs.state_run,
                            csrs.state_reset,
                            16'(ADDR_OFFSET_WIDTH),
                            1'b0,
                            15'(DATA_WIDTH / 8) };
        csrs.rd_data[1] = 64'(num_atomic_reqs);
        csrs.rd_data[2] = 64'(num_atomic_rd_resps);
        csrs.rd_data[3] = 64'(num_wb_reqs);
        csrs.rd_data[4] = 64'(num_wb_resps);
        csrs.rd_data[5] = 64'(num_rd_reqs);
        csrs.rd_data[6] = 64'(num_rd_resps);
    end


    // ====================================================================
    //
    // Engine execution. Generate memory traffic.
    //
    // ====================================================================

    logic state_reset;
    logic state_run;
    t_addr_offset atomic_cur_addr_offset, rd_cur_addr_offset;
    t_num_reqs atomic_num_reqs_left, rd_num_reqs_left;
    logic atomic_done, rd_done;
    t_rid atomic_req_id, rd_req_id;
    ofs_plat_axi_mem_pkg::t_axi_atomic atomic_op;
    wire atomic_op_is_cas = (atomic_op == ofs_plat_axi_mem_pkg::ATOMIC_CAS);

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
    // Generate atomic requests
    //

    localparam BYTE_MASK_WIDTH = DATA_WIDTH / 8;

    t_addr_offset wb_addr_offset;
    logic [BYTE_MASK_WIDTH-1 : 0] wb_mask;
    logic [DATA_WIDTH-1 : 0] wb_data;
    logic wb_valid;

    // Arbiter for the write request AW and W streams. Either an atomic request
    // or a writeback of a previous atomic response to the writeback buffer
    // that will be used to validate responses.
    wire do_atomic_write = state_run && !atomic_done && !wb_valid &&
                           host_mem_if.awready && host_mem_if.wready;
    wire do_writeback = wb_valid &&
                        host_mem_if.awready && host_mem_if.wready;

    //
    // Given a byte-level address, generate a write data mask that enables
    // a single naturally aligned 32, 64 or 128 bit value. Only CAS can use
    // 128 bits: one for the compare and one for the swap.
    //
    function automatic logic [BYTE_MASK_WIDTH-1 : 0] maskFromByteAddr(
        input t_addr_offset addr,
        input logic mode_64bit,
        input logic is_cas
        );

        logic [BYTE_MASK_WIDTH-1 : 0] mask;
        unique case ({ mode_64bit, is_cas })
          { 1'b0, 1'b0 }: mask = BYTE_MASK_WIDTH'('hf)    << (4 * addr[$clog2(BYTE_MASK_WIDTH)-1:2]);
          { 1'b0, 1'b1 }: mask = BYTE_MASK_WIDTH'('hff)   << (8 * addr[$clog2(BYTE_MASK_WIDTH)-1:3]);
          { 1'b1, 1'b0 }: mask = BYTE_MASK_WIDTH'('hff)   << (8 * addr[$clog2(BYTE_MASK_WIDTH)-1:3]);
          default:        mask = BYTE_MASK_WIDTH'('hffff) << (16 * addr[$clog2(BYTE_MASK_WIDTH)-1:4]);
        endcase

        return mask;
    endfunction // maskFromByteAddr

    //
    // Shift 32 or 64 bit write data to the naturally aligned position on the
    // data bus, given the byte-level address.
    //
    function automatic logic [DATA_WIDTH-1 : 0] shiftAtomicWriteData(
        input logic [63:0] data,
        input t_addr_offset addr,
        input logic mode_64bit
        );

        if (mode_64bit)
            return DATA_WIDTH'(data) << (64 * addr[$clog2(BYTE_MASK_WIDTH)-1:3]);
        else
            return DATA_WIDTH'(data[31:0]) << (32 * addr[$clog2(BYTE_MASK_WIDTH)-1:2]);
    endfunction // shiftAtomicWriteData

    //
    // Compare and swap operand order depends on the position on the bus. AXI
    // expects the full payload to be naturally aligned for the size, which is
    // 2x the size of the returned value. The order of the compare operand and
    // the swap operand depends on the address being updated. The compare
    // operand is always at the spot on the bus corresponding to the address.
    // 
    function automatic logic atomicCASCompareIsLast(
        input t_addr_offset addr,
        input logic mode_64bit
        );

        return mode_64bit ? addr[3] : addr[2];
    endfunction // atomicCASCompareIsLast

    //
    // Similar to shiftAtomicWriteData(), but specific to atomic compare and swap,
    // which takes two operands and returns only one. The order of the operands
    // is address-dependent, computed by atomicCASCompareIsLast() above.
    //
    function automatic logic [DATA_WIDTH-1 : 0] shiftAtomicCASWriteData(
        input logic [63:0] data_cmp,
        input logic [63:0] data_swap,
        input t_addr_offset addr,
        input logic mode_64bit
        );

        logic swap_opers = atomicCASCompareIsLast(addr, mode_64bit);

        if (mode_64bit)
        begin
            return DATA_WIDTH'(swap_opers ? { data_cmp, data_swap } : { data_swap, data_cmp }) <<
                   (128 * addr[$clog2(BYTE_MASK_WIDTH)-1:4]);
        end
        else
        begin
            return DATA_WIDTH'(swap_opers ? { data_cmp[31:0], data_swap[31:0] } : { data_swap[31:0], data_cmp[31:0] }) <<
                   (64 * addr[$clog2(BYTE_MASK_WIDTH)-1:3]);
        end
    endfunction // shiftAtomicCASWriteData


    always_comb
    begin
        host_mem_if.awvalid = do_atomic_write || do_writeback;
        host_mem_if.aw = '0;

        if (!wb_valid)
        begin
            // *** Generate an atomic request on the write address bus. ***
            host_mem_if.aw.addr = { atomic_base_addr, t_byte_idx'(0) } +
                                  atomic_cur_addr_offset;
            host_mem_if.aw.id = atomic_req_id;
            host_mem_if.aw.atop = atomic_op;

            // The AXI5 standard says that burst for atomics should generally
            // be INCR (2'b01) except for CAS when the compare value follows the
            // swap value. The PIM ignores this.
            host_mem_if.aw.burst =
                (atomic_op_is_cas && atomicCASCompareIsLast(atomic_cur_addr_offset, mode_64bit)) ? 2'b10 : 2'b01;

            // The size is the full payload. For CAS, both compare and swap.
            if (atomic_op_is_cas)
                host_mem_if.aw.size = mode_64bit ? 3'b100 : 3'b011;
            else
                host_mem_if.aw.size = mode_64bit ? 3'b011 : 3'b010;
        end
        else
        begin
            // Write back atomic read response to the wb buffer
            host_mem_if.aw.addr = { wb_base_addr, t_byte_idx'(0) } +
                                  wb_addr_offset;
            host_mem_if.aw.size = mode_64bit ? 3'b011 : 3'b010;
        end

        host_mem_if.wvalid = do_atomic_write || do_writeback;
        host_mem_if.w = '0;
        host_mem_if.w.last = 1'b1;
        if (!wb_valid)
        begin
            // ****
            // Data for atomic request. If this were a normal AFU, we could simply
            // replicate the write data throughout the line, putting copies of the
            // data in each possible position for a naturally aligned value. That
            // would produce better hardware than this code. However, this is a
            // PIM test that seeks to validate the behavior of the atomic support.
            // The write data is generated here with only the expected location set.
            // Everything else is zero. This way, the PIM's address management must
            // be correct for the test to pass.
            // ****
            if (atomic_op_is_cas)
                host_mem_if.w.data = shiftAtomicCASWriteData(64'(atomic_req_id), 64'('h12345), atomic_cur_addr_offset, mode_64bit);
            else
                host_mem_if.w.data = shiftAtomicWriteData(64'(atomic_req_id), atomic_cur_addr_offset, mode_64bit);
            host_mem_if.w.strb = maskFromByteAddr(atomic_cur_addr_offset, mode_64bit, atomic_op_is_cas);
        end
        else
        begin
            // Write back atomic data
            host_mem_if.w.data = wb_data;
            host_mem_if.w.strb = wb_mask;
        end
    end

    //
    // Update the test engine after generating an atomic write request.
    // The test alternates between the available atomic functions and steps
    // through memory, targeting each word in a line.
    //
    always_ff @(posedge clk)
    begin
        if (do_atomic_write)
        begin
            // Advance one position. We assume there are few enough requests that
            // the address offset mask is not required.
            atomic_cur_addr_offset <= atomic_cur_addr_offset + (mode_64bit ? 8 : 4);
            atomic_num_reqs_left <= atomic_num_reqs_left - 1;
            atomic_req_id <= atomic_req_id + 1;
            atomic_done <= (atomic_num_reqs_left == t_num_reqs'(1));

            // Cycle through atomic operations
            if (atomic_op == ofs_plat_axi_mem_pkg::ATOMIC_ADD)
                atomic_op <= ofs_plat_axi_mem_pkg::ATOMIC_SWAP;
            else if (atomic_op == ofs_plat_axi_mem_pkg::ATOMIC_SWAP)
                atomic_op <= ofs_plat_axi_mem_pkg::ATOMIC_CAS;
            else
                atomic_op <= ofs_plat_axi_mem_pkg::ATOMIC_ADD;
        end

        if (state_reset)
        begin
            atomic_cur_addr_offset <= '0;
            atomic_num_reqs_left <= atomic_num_reqs;

            // Atomic requests set bit 8 of the ID field in order to distinguish
            // atomic read channel responses from normal reads. The RID/WID fields
            // must be at least 9 bits wide. The top-level module of this test
            // sets these requirements in the PIM interface.
            atomic_req_id <= t_rid'('h100);
            atomic_done <= 1'b0;
            atomic_op <= ofs_plat_axi_mem_pkg::ATOMIC_ADD;
        end
    end

    assign host_mem_if.bready = 1'b1;


    //
    // Consume atomic read responses and write back the responses to the wb
    // buffer, when enabled.
    //

    logic atomic_rsp_valid;
    t_rid atomic_rsp_id;
    logic [DATA_WIDTH-1 : 0] atomic_rsp_data;

    logic wb_notFull;

    // Skid buffer for incoming atomic read responses
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_rid) + DATA_WIDTH)
        )
      aread_rsp_in
       (
        .clk,
        .reset_n,

        .enq_data({ host_mem_if.r.id, host_mem_if.r.data }),
        .enq_en(wb_req_enable && host_mem_if.r.id[8] && host_mem_if.rvalid && host_mem_if.rready),
        .notFull(host_mem_if.rready),

        .first({ atomic_rsp_id, atomic_rsp_data }),
        .deq_en(atomic_rsp_valid && wb_notFull),
        .notEmpty(atomic_rsp_valid)
        );

    // Second skid buffer on the read response -> write path. Compute an address
    // offset and write data mask.
    t_addr_offset wb_addr_offset_in;
    logic [BYTE_MASK_WIDTH-1 : 0] wb_mask_in;
    logic [DATA_WIDTH-1 : 0] wb_data_in;

    assign wb_addr_offset_in = atomic_rsp_id[7:0] << (mode_64bit ? 3 : 2);
    assign wb_mask_in =
        mode_64bit ? (BYTE_MASK_WIDTH'('hff) << (8 * atomic_rsp_id[$clog2(DATA_WIDTH/64)-1:0])) :
                     (BYTE_MASK_WIDTH'('hf)  << (4 * atomic_rsp_id[$clog2(DATA_WIDTH/32)-1:0]));

    always_comb
    begin
        wb_data_in = atomic_rsp_data;

        // Clear everything but the value in the expected location to ensure that
        // the PIM is picking the proper location.
        if (mode_64bit)
        begin
            for (int i = 0; i < DATA_WIDTH/64; i = i + 1)
            begin
                if (i != atomic_rsp_id[$clog2(DATA_WIDTH/64)-1:0])
                    wb_data_in[i*64 +: 64] = '0;
            end
        end
        else
        begin
            for (int i = 0; i < DATA_WIDTH/32; i = i + 1)
            begin
                if (i != atomic_rsp_id[$clog2(DATA_WIDTH/32)-1:0])
                    wb_data_in[i*32 +: 32] = '0;
            end
        end
    end

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(ADDR_OFFSET_WIDTH + BYTE_MASK_WIDTH + DATA_WIDTH)
        )
      awriteback
       (
        .clk,
        .reset_n,

        .enq_data({ wb_addr_offset_in, wb_mask_in, wb_data_in }),
        .enq_en(atomic_rsp_valid && wb_notFull),
        .notFull(wb_notFull),

        .first({ wb_addr_offset, wb_mask, wb_data }),
        .deq_en(do_writeback),
        .notEmpty(wb_valid)
        );


    //
    // Generate read requests -- always for a single line. These requests
    // only inject extra traffic on the read request path in order
    // to exercise artbitration logic within the PIM. They serve no
    // functional purpose.
    //
    always_comb
    begin
        host_mem_if.arvalid = (state_run && !rd_done);

        host_mem_if.ar = '0;
        host_mem_if.ar.addr = { rd_base_addr + rd_cur_addr_offset,
                                t_byte_idx'(0) };
        host_mem_if.ar.size = host_mem_if.ADDR_BYTE_IDX_WIDTH;
        host_mem_if.ar.id = rd_req_id;
        host_mem_if.ar.burst = 2'b01;
    end

    always_ff @(posedge clk)
    begin
        // Was the read request accepted?
        if (state_run && !rd_done && host_mem_if.arready)
        begin
            rd_cur_addr_offset <= (rd_cur_addr_offset + 1) & base_addr_offset_mask;
            rd_num_reqs_left <= rd_num_reqs_left - 1;
            rd_req_id <= rd_req_id + 1;
            rd_done <= (rd_num_reqs_left == t_num_reqs'(1));
        end

        if (state_reset)
        begin
            rd_cur_addr_offset <= '0;
            rd_num_reqs_left <= rd_num_reqs;
            rd_req_id <= 0;
            rd_done <= ~rd_req_enable;
        end
    end

    // Quick check of non-atomic read responses. Software is expected to
    // initialize the memory with a specific pattern.
    always_ff @(posedge clk)
    begin
        // Low 16 bits of the payload must match the request ID. The next 16 bits
        // must match the inverse of the ID.
        if (host_mem_if.rvalid && host_mem_if.rready && ~host_mem_if.r.id[8] &&
            ((host_mem_if.r.data[0  +: 16] != 16'(host_mem_if.r.id)) ||
             (host_mem_if.r.data[16 +: 16] != ~16'(host_mem_if.r.id))))
        begin
            rd_error_flag <= 1'b1;
        end

        if (!reset_n || state_reset)
        begin
            rd_error_flag <= 1'b0;
        end
    end


    // ====================================================================
    //
    // Engine state
    //
    // ====================================================================

    always_ff @(posedge clk)
    begin
        csrs.status_active <= (state_run && ! (atomic_done && rd_done)) ||
                              (num_atomic_reqs != num_atomic_rd_resps) ||
                              (num_atomic_reqs != num_atomic_wr_resps) ||
                              (num_rd_reqs != num_rd_resps) ||
                              (num_wb_reqs != num_wb_resps);
    end


    // ====================================================================
    //
    // Counters. The multicycle counter breaks addition up into multiple
    // cycles for timing.
    //
    // ====================================================================

    logic incr_atomic_req, incr_atomic_rd_resp, incr_atomic_wr_resp;
    logic incr_rd_req, incr_rd_resp;
    logic incr_wb_req, incr_wb_resp;

    // Flags controlling counter increments
    always_ff @(posedge clk)
    begin
        // Atomic requests are tagged above with bit id[8]
        incr_atomic_req <= host_mem_if.awvalid && host_mem_if.awready && host_mem_if.aw.id[8];
        incr_atomic_rd_resp <= host_mem_if.rvalid && host_mem_if.r.last && host_mem_if.rready &&
                               host_mem_if.r.id[8];
        incr_atomic_wr_resp <= host_mem_if.bvalid && host_mem_if.bready && host_mem_if.b.id[8];

        incr_rd_req <= host_mem_if.arvalid && host_mem_if.arready;
        incr_rd_resp <= host_mem_if.rvalid && host_mem_if.r.last && host_mem_if.rready &&
                        !host_mem_if.r.id[8];

        incr_wb_req <= host_mem_if.awvalid && host_mem_if.awready && !host_mem_if.aw.id[8];
        incr_wb_resp <= host_mem_if.bvalid && host_mem_if.bready && !host_mem_if.b.id[8];
    end

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) atomic_req
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_atomic_req)),
        .value(num_atomic_reqs)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) atomic_rd_resp
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_atomic_rd_resp)),
        .value(num_atomic_rd_resps)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) atomic_wr_resp
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_atomic_wr_resp)),
        .value(num_atomic_wr_resps)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_req
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_rd_req)),
        .value(num_rd_reqs)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) rd_resp
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_rd_resp)),
        .value(num_rd_resps)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) wb_req
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_wb_req)),
        .value(num_wb_reqs)
        );

    counter_multicycle#(.NUM_BITS(COUNTER_WIDTH)) wb_resp
       (
        .clk,
        .reset_n(reset_n && !state_reset),
        .incr_by(COUNTER_WIDTH'(incr_wb_resp)),
        .value(num_wb_resps)
        );

endmodule // host_mem_atomic_engine_axi
