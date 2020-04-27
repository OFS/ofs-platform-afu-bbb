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
// ROB that returns data FIFO by sorting out of order arrival of
// the payload. The ROB combines two pieces of data with each entry:
// meta-data that is supplied at the time an index is allocated and the
// late-arriving data. Both are returned together through first and first_meta.
// Within the driver this is typically used to combine a parent's mdata
// field for the response header in combination with read data.
//

module ofs_plat_prim_rob
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    parameter N_META_BITS = 1,
    // Maximum number of entries that can be allocated in a single cycle.
    // This is used for multi-line requests.
    parameter MAX_ALLOC_PER_CYCLE = 1,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = MAX_ALLOC_PER_CYCLE
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Add one or more new entries in the ROB.  No payload, just control.
    // The ROB returns a handle -- the index where the payload should
    // be written.  When allocating multiple entries the indices are
    // sequential.
    input  logic alloc_en,
    input  logic [$clog2(MAX_ALLOC_PER_CYCLE) : 0] allocCnt, // Number to allocate
    input  logic [N_META_BITS-1 : 0] allocMeta,        // Save meta-data for new entry
    output logic notFull,                              // Is ROB full?
    output logic [$clog2(N_ENTRIES)-1 : 0] allocIdx,   // Index of new entry
    output logic [$clog2(N_ENTRIES) : 0] inSpaceAvail, // Number of entries free

    // Payload write.  No ready signal.  The ROB must always be ready
    // to receive data.
    input  logic enqData_en,                        // Store data for existing entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqDataIdx,
    input  logic [N_DATA_BITS-1 : 0] enqData,

    // Ordered output
    input  logic deq_en,                            // Deq oldest entry
    output logic notEmpty,                          // Is oldest entry ready?
    // Data arrives TWO CYCLES AFTER notEmpty and deq_en are asserted
    output logic [N_DATA_BITS-1 : 0] T2_first,      // Data for oldest entry
    output logic [N_META_BITS-1 : 0] T2_firstMeta   // Meta-data for oldest entry
    );

    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;
    t_idx oldest;

    //
    // Instantiate ROB controller
    //
    ofs_plat_prim_rob_ctrl
      #(
        .N_ENTRIES(N_ENTRIES),
        .MIN_FREE_SLOTS(MIN_FREE_SLOTS),
        .MAX_ALLOC_PER_CYCLE(MAX_ALLOC_PER_CYCLE)
        )
      ctrl
       (
        .clk,
        .reset_n,
        .alloc_en,
        .allocCnt,
        .notFull,
        .allocIdx,
        .inSpaceAvail,
        .enqData_en,
        .enqDataIdx,
        .deq_en,
        .notEmpty,
        .deqIdx(oldest)
        );


    // ====================================================================
    //
    //  Storage.
    //
    // ====================================================================

    //
    // Data
    //
    ofs_plat_prim_ram_simple
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(1),
        .REGISTER_WRITES(1),
        .BYPASS_REGISTERED_WRITES(0)
        )
      memData
       (
        .clk,

        .waddr(enqDataIdx),
        .wen(enqData_en),
        .wdata(enqData),

        .raddr(oldest),
        .rdata(T2_first)
        );

    //
    // Meta-data memory.
    //
    generate
        if (N_META_BITS != 0)
        begin : genMeta
            ofs_plat_prim_ram_simple
              #(
                .N_ENTRIES(N_ENTRIES),
                .N_DATA_BITS(N_META_BITS),
                .N_OUTPUT_REG_STAGES(1)
                )
              memMeta
               (
                .clk(clk),

                .waddr(allocIdx),
                .wen(alloc_en),
                .wdata(allocMeta),

                .raddr(oldest),
                .rdata(T2_firstMeta)
                );
        end
        else
        begin : noMeta
            assign T2_firstMeta = 'x;
        end
    endgenerate

endmodule // ofs_plat_prim_rob


//
// Control logic for a ROB
//
module ofs_plat_prim_rob_ctrl
  #(
    parameter N_ENTRIES = 32,
    // Maximum number of entries that can be allocated in a single cycle.
    // This is used for multi-line requests.
    parameter MAX_ALLOC_PER_CYCLE = 1,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = MAX_ALLOC_PER_CYCLE
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Add one or more new entries in the ROB.  No payload, just control.
    // The ROB returns a handle -- the index where the payload should
    // be written.  When allocating multiple entries the indices are
    // sequential.
    input  logic alloc_en,
    input  logic [$clog2(MAX_ALLOC_PER_CYCLE) : 0] allocCnt, // Number to allocate
    output logic notFull,                              // Is ROB full?
    output logic [$clog2(N_ENTRIES)-1 : 0] allocIdx,   // Index of new entry
    output logic [$clog2(N_ENTRIES) : 0] inSpaceAvail, // Number of entries free

    // Payload write.  No ready signal.  The ROB must always be ready
    // to receive data.
    input  logic enqData_en,                        // Store data for existing entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqDataIdx,

    // Ordered output
    input  logic deq_en,                            // Deq oldest entry
    output logic notEmpty,                          // Is oldest entry ready?
    output logic [$clog2(N_ENTRIES)-1 : 0] deqIdx
    );

    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;

    // Epoch counter adds a high bit to manage counter wrapping
    typedef logic [$clog2(N_ENTRIES) : 0] t_epoch_idx;

    // Ready flags from valid bit memory
    logic validBits_rdy[0:1];

    t_epoch_idx newest;
    logic newest_epoch;
    t_idx newest_idx;
    assign { newest_epoch, newest_idx } = newest;

    t_epoch_idx oldest, oldest_q;
    logic oldest_epoch, oldest_epoch_q;
    t_idx oldest_idx, oldest_idx_q;
    assign { oldest_epoch, oldest_idx } = oldest;
    assign { oldest_epoch_q, oldest_idx_q } = oldest_q;

    t_epoch_idx in_space_avail, in_space_avail_next;
    assign inSpaceAvail = in_space_avail;

    // Compute available space, taking advantage of the extra epoch bit to
    // manage index wrapping. The count of entries allocated this cycle (alloc)
    // must be considered but we can wait until oldest is updated next cycle
    // to account for entries deallocated. This avoids timing dependence
    // on incrementing oldest and, at worst, undercounts available space.
    //
    // Coded so that the subtraction doesn't depend on alloc_en.
    assign in_space_avail_next =
        (alloc_en ? { ~oldest_epoch, oldest_idx } - newest - allocCnt :
                    { ~oldest_epoch, oldest_idx } - newest);

    always_ff @(posedge clk)
    begin
        in_space_avail <= in_space_avail_next;

        // We make a conservative assumption that MAX_ALLOC_PER_CYCLE entries
        // were allocated this cycle in order to avoid depending on alloc_en
        // and allocCnt. This improves timing at the expense of a few ROB slots.
        notFull <= validBits_rdy[0] &&
                   (in_space_avail > t_epoch_idx'(MAX_ALLOC_PER_CYCLE + MIN_FREE_SLOTS));
    end

    // enq allocates a slot and returns the index of the slot.
    assign allocIdx = newest_idx;
    assign deqIdx = oldest_idx;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            newest <= '0;
        end
        else
        begin
            if (alloc_en)
            begin
                newest <= newest + allocCnt;
            end

            // synthesis translate_off
            assert (!alloc_en || (allocCnt <= in_space_avail)) else
                $fatal(2, "** ERROR ** %m: Can't ENQ when FULL!");
            assert ((N_ENTRIES & (N_ENTRIES - 1)) == 0) else
                $fatal(2, "** ERROR ** %m: N_ENTRIES must be a power of 2!");
            // synthesis translate_on
        end
    end

    // Bump the oldest pointer on deq
    always_ff @(posedge clk)
    begin
        if (deq_en)
        begin
            oldest <= oldest + 1'b1;
        end
        oldest_q <= oldest;

        if (!reset_n)
        begin
            oldest <= '0;
        end
    end

    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n)
        begin
            assert(! deq_en || notEmpty) else
              $fatal(2, "** ERROR ** %m: Can't DEQ when EMPTY!");
        end
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Track data arrival
    //
    // ====================================================================

    //
    // Valid bits are stored in RAM.  To avoid the problem of needing
    // two write ports to the memory we toggle the meaning of the valid
    // bit on every trip around the ring buffer.  On the first trip around
    // the valid tag is 1 since the memory is initialized to 0.  On the
    // second trip around the valid bits start 1, having been set on the
    // previous loop.  The target is thus changed to 0.
    //
    logic valid_tag, valid_tag_q;
    t_idx enqDataIdx_q;

    always_ff @(posedge clk)
    begin
        enqDataIdx_q <= enqDataIdx;
        valid_tag_q <= valid_tag;

        // Toggle the valid_tag every trip around the ring buffer.
        if (deq_en && (&(oldest_idx) == 1'b1))
        begin
            valid_tag <= ~valid_tag;
        end

        if (!reset_n)
        begin
            valid_tag <= 1'b1;
        end
    end


    //
    // Track the number of valid entries ready to go.
    //
    // A small counter works fine.  The count just has to stay ahead of
    // the ROB's output.
    //
    typedef logic [2:0] t_valid_cnt;
    t_valid_cnt num_valid;

    // Valid bits array.  Memory reads are multi-cycle.  Valid bits
    // are stored in two banks and accessed in alternate cycles to hide
    // the latency.
    logic [$clog2(N_ENTRIES)-2 : 0] test_valid_idx[0:1], test_valid_idx_q[0:1];
    logic test_valid_value_q[0:1];
    logic test_valid_tgt;
    logic test_valid_bypass_q[0:1];

    // Which test_valid bank to read?
    logic test_valid_bank;

    // The next entry is ready when its valid tag matches
    // the target for the current trip around the ring buffer.
    logic test_valid_is_set;
    assign test_valid_is_set =
        (test_valid_tgt == test_valid_value_q[test_valid_bank]) ||
        test_valid_bypass_q[test_valid_bank];

    // Don't exceed num_valid's bounds
    logic test_is_valid;
    assign test_is_valid = test_valid_is_set && (&(num_valid) != 1'b1);

    //
    // Update the pointer to the oldest valid entry.
    //
    always_ff @(posedge clk)
    begin
        test_valid_idx_q <= test_valid_idx;

        if (test_is_valid)
        begin
            test_valid_idx[test_valid_bank] <= test_valid_idx[test_valid_bank] + 1;

            // Invert the comparison tag when wrapping, just like valid_tag.
            if (test_valid_bank && (&(test_valid_idx[1]) == 1'b1))
            begin
                test_valid_tgt <= ~test_valid_tgt;
            end

            test_valid_bank <= ~test_valid_bank;
        end

        if (!reset_n || !validBits_rdy[0])
        begin
            test_valid_idx[0] <= 0;
            test_valid_idx[1] <= 0;

            test_valid_bank <= 1'b0;
            test_valid_tgt <= 1'b1;
        end
    end

    //
    // Count the number of oldest data-ready entries in the ROB.
    //
    always_ff @(posedge clk)
    begin
        num_valid <= num_valid - t_valid_cnt'(deq_en) +
                                 t_valid_cnt'(test_is_valid);

        // Not empty if...
        notEmpty <= // A next entry became ready this cycle
                    test_is_valid ||
                    // or there is more than one entry ready
                    (num_valid > t_valid_cnt'(1)) ||
                    // or there was at least one entry and it wasn't removed
                    (num_valid[0] && ! deq_en);

        if (!reset_n)
        begin
            num_valid <= t_valid_cnt'(0);
            notEmpty <= 1'b0;
        end
    end

    genvar p;
    generate
        for (p = 0; p <= 1; p = p + 1)
        begin : r
            logic p_wen, p_wen_q;
            logic [$clog2(N_ENTRIES)-2 : 0] p_waddr_q;

            if (N_ENTRIES < 128)
            begin
                //
                // Small ROB. Just use a normal LUTRAM, but register the read response.
                //
                logic rdata;

                ofs_plat_prim_lutram_init
                  #(
                    // Two ROB valid bit banks, each with half the entries
                    .N_ENTRIES(N_ENTRIES >> 1),
                    .N_DATA_BITS(1),
                    .INIT_VALUE(1'b0),
                    // Writes are delayed a cycle for timing so bypass new writes
                    // to reads in the same cycle.
                    .READ_DURING_WRITE("NEW_DATA")
                    )
                validBits
                   (
                    .clk,
                    .reset_n,
                    .rdy(validBits_rdy[p]),

                    .raddr(test_valid_idx[p]),
                    .rdata(rdata),

                    .wen(p_wen_q),
                    .waddr(p_waddr_q),
                    // Indicate the entry is valid using the appropriate tag to
                    // mark validity.  Indices less than oldest are very young
                    // and have the tag for the next ring buffer loop.  Indicies
                    // greater than or equal to oldest use the tag for the current
                    // trip.
                    .wdata((enqDataIdx_q >= oldest_idx_q) ? valid_tag_q : ~valid_tag_q)
                    );

                always_ff @(posedge clk)
                begin
                    test_valid_value_q[p] <= rdata;
                end
            end
            else
            begin
                //
                // Don't confuse the two banks of valid bits in the ROB with this
                // banked implementation of a LUTRAM.  The banked LUTRAM exists
                // for timing, breaking the deep MUX required for a large array
                // into multiple cycles.  The ROB valid bits are in two banks,
                // which are implemented as multi-bank LUTRAMs.
                //
                ofs_plat_prim_lutram_init_banked
                  #(
                    // Two ROB valid bit banks, each with half the entries
                    .N_ENTRIES(N_ENTRIES >> 1),
                    .N_DATA_BITS(1),
                    .INIT_VALUE(1'b0),
                    // Writes are delayed a cycle for timing so bypass new writes
                    // to reads in the same cycle.
                    .READ_DURING_WRITE("NEW_DATA"),
                    // LUTRAM banks -- could be any number.  This is not ROB
                    // valid bit banks.
                    .N_BANKS(4)
                    )
                validBits
                   (
                    .clk,
                    .reset_n,
                    .rdy(validBits_rdy[p]),

                    .raddr(test_valid_idx[p]),
                    .T1_rdata(test_valid_value_q[p]),

                    .wen(p_wen_q),
                    .waddr(p_waddr_q),
                    // Indicate the entry is valid using the appropriate tag to
                    // mark validity.  Indices less than oldest are very young
                    // and have the tag for the next ring buffer loop.  Indicies
                    // greater than or equal to oldest use the tag for the current
                    // trip.
                    .wdata((enqDataIdx_q >= oldest_idx_q) ? valid_tag_q : ~valid_tag_q)
                    );
            end

            // Use the low bit of the data index as a bank select bit
            assign p_wen = enqData_en && (enqDataIdx[0] == p[0]);
            assign p_waddr_q = enqDataIdx_q[1 +: $bits(enqDataIdx)-1];

            // Bypass -- note writes to the bank being read
            assign test_valid_bypass_q[p] = (p_wen_q &&
                                             (p_waddr_q == test_valid_idx_q[p]));

            always_ff @(posedge clk)
            begin
                p_wen_q <= p_wen;
            end
        end
    endgenerate

endmodule // ofs_plat_prim_rob_ctrl
