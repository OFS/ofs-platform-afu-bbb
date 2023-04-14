// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: MIT

//
// A FIFO, but with separate almostFull tracking where FIFO slots can be
// claimed before they are used. Multiple slots may be claimed in the same
// cycle.
//
// The most common use of this structure is to guarantee that buffer slots
// are available for all outstanding read requests. Slots are claimed as
// requests are generated and released as data flows back to the requester.
//

module ofs_plat_prim_fifo_buffer
  #(
    parameter N_ENTRIES = 512,
    parameter N_DATA_BITS = 64,

    // Maximum number of entries that can be allocated in a single cycle.
    // This is used for multi-line requests.
    parameter MAX_ALLOC_PER_CYCLE = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Claim one or more FIFO entries. No payload, just control.
    input  logic alloc_en,
    input  logic [$clog2(MAX_ALLOC_PER_CYCLE) : 0] allocCnt, // Number to allocate
    output logic almostFull,                                 // Almost out of slots?

    // Payload write from the sink. notFull is driven by the FIFO
    // itself. As long as the source has honored almostFull above,
    // the FIFO will never be full.
    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,

    // Ordered output
    output logic [N_DATA_BITS-1 : 0] first,
    input  logic deq_en,
    output logic notEmpty
    );

    typedef logic [$clog2(N_ENTRIES) : 0] t_slot_cnt;

    t_slot_cnt space_used, space_used_next;

    always_comb
    begin
        // Selection after the adders, for timing
        unique casex ({ alloc_en, deq_en })
            2'b00: space_used_next = space_used;
            2'b10: space_used_next = space_used + allocCnt;
            2'b01: space_used_next = space_used - 1;
            2'b11: space_used_next = space_used + allocCnt - 1;
        endcase
    end

    always_ff @(posedge clk)
    begin
        space_used <= space_used_next;

        // We make a conservative assumption that MAX_ALLOC_PER_CYCLE entries
        // were allocated on cycles with new requests in order to avoid depending
        // on allocCnt.
        //
        // almostFull updates are delayed during allocation cycles, requiring
        // space for two requests before almostFull stops them.
        almostFull <=
            alloc_en ? (space_used > t_slot_cnt'(N_ENTRIES - 2 * MAX_ALLOC_PER_CYCLE)) :
                       (space_used > t_slot_cnt'(N_ENTRIES - MAX_ALLOC_PER_CYCLE));

        if (!reset_n)
        begin
            space_used <= '0;
            almostFull <= 1'b1;
        end
    end

    //
    // Data path is just a normal FIFO
    //
    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(N_DATA_BITS),
        .N_ENTRIES(N_ENTRIES)
        )
      fifo
       (
        .clk,
        .reset_n,
        .enq_data,
        .enq_en,
        .notFull,
        .almostFull(),
        .first,
        .deq_en,
        .notEmpty
        );


    //
    // Error checking for the control flow.
    //

    // synthesis translate_off

    // Count total requests and completions
    logic [63:0] total_alloc;
    logic [63:0] total_deq;

    always_ff @(posedge clk)
    begin
        if (alloc_en) total_alloc <= total_alloc + allocCnt;
        if (deq_en) total_deq <= total_deq + 1;

        if (reset_n)
        begin
            if (total_alloc - total_deq > N_ENTRIES)
                $fatal(2, "** ERROR ** %m: too many requests in flight (alloc 0x%0x, deq 0x%0x)", total_alloc, total_deq);
            if (alloc_en && (space_used_next < space_used))
                $fatal(2, "** ERROR ** %m: in flight counter overflow!");

            if (alloc_en && almostFull)
                $fatal(2, "** ERROR ** %m: allocated entries while no entries available!");
            if (deq_en && !notEmpty)
                $fatal(2, "** ERROR ** %m: deq from empty FIFO!");
        end

        if (!reset_n)
        begin
            total_alloc <= '0;
            total_deq <= '0;
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_prim_fifo_buffer
