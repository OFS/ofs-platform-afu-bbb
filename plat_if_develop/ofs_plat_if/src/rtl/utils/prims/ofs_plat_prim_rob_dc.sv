// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Dual clock ROB that returns data FIFO by sorting out of order arrival of
// the payload. The ROB combines two pieces of data with each entry:
// meta-data that is supplied at the time an index is allocated and the
// late-arriving data. Both are returned together through first and first_meta.
// Within the driver this is typically used to combine a parent's mdata
// field for the response header in combination with read data.
//
// All ports are in the "clk" domain except for inbound unordered
// data, which is clocked by enq_clk.
//

module ofs_plat_prim_rob_dc
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
    input  logic enq_clk,
    input  logic enq_reset_n,
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
    ofs_plat_prim_rob_ctrl_dc
      #(
        .N_ENTRIES(N_ENTRIES),
        .MIN_FREE_SLOTS(MIN_FREE_SLOTS),
        .MAX_ALLOC_PER_CYCLE(MAX_ALLOC_PER_CYCLE)
        )
      dc_ctrl
       (
        .clk,
        .reset_n,
        .alloc_en,
        .allocCnt,
        .notFull,
        .allocIdx,
        .inSpaceAvail,
        .enq_clk,
        .enq_reset_n,
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
    ofs_plat_prim_ram_simple_dc
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(1),
        .REGISTER_WRITES(1)
        )
      memData
       (
        .wclk(enq_clk),
        .waddr(enqDataIdx),
        .wen(enqData_en),
        .wdata(enqData),

        .rclk(clk),
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

endmodule // ofs_plat_prim_rob_dc


//
// Control logic for a ROB
//
module ofs_plat_prim_rob_ctrl_dc
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
    input  logic enq_clk,
    input  logic enq_reset_n,
    input  logic enqData_en,                        // Store data for existing entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqDataIdx,

    // Ordered output
    input  logic deq_en,                            // Deq oldest entry
    output logic notEmpty,                          // Is oldest entry ready?
    output logic [$clog2(N_ENTRIES)-1 : 0] deqIdx
    );

    //
    // Forward response control through a clock crossing FIFO and then use
    // the normal single clock ROB control, all in receiver's clk domain.
    //
    logic enq_notFull;
    logic cc_enqData_en, cc_enqData_en_q;
    logic [$clog2(N_ENTRIES)-1 : 0] cc_enqDataIdx, cc_enqDataIdx_q;

    ofs_plat_prim_fifo_dc
      #(
        .N_DATA_BITS($clog2(N_ENTRIES)),
        .N_ENTRIES(N_ENTRIES)
        )
      rsp_fifo
       (
        .enq_clk(enq_clk),
        .enq_reset_n(enq_reset_n),
        .enq_data(enqDataIdx),
        .enq_en(enqData_en),
        .notFull(enq_notFull),
        .almostFull(),
        .deq_clk(clk),
        .deq_reset_n(reset_n),
        .first(cc_enqDataIdx),
        .deq_en(cc_enqData_en),
        .notEmpty(cc_enqData_en)
        );

    // synthesis translate_off
    always_ff @(negedge enq_clk)
    begin
        if (enq_reset_n)
        begin
            assert(!enqData_en || enq_notFull) else
              $fatal(2, "** ERROR ** %m: clock crossing FIFO is full!");
        end
    end
    // synthesis translate_on


    //
    // Now everthing is in clk. Use the normal ROB controller.
    //

    always_ff @(posedge clk)
    begin
        cc_enqData_en_q <= cc_enqData_en;
        cc_enqDataIdx_q <= cc_enqDataIdx;
    end

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
        .enqData_en(cc_enqData_en_q),
        .enqDataIdx(cc_enqDataIdx_q),
        .deq_en,
        .notEmpty,
        .deqIdx
        );

endmodule // ofs_plat_prim_rob_ctrl_dc


//
// Wrapper around either the dual clock or single clock ROB, depending
// on ADD_CLOCK_CROSSING.
//
module ofs_plat_prim_rob_maybe_dc
  #(
    parameter ADD_CLOCK_CROSSING = 1,

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
    input  logic enq_clk,
    input  logic enq_reset_n,
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

    generate
        if (ADD_CLOCK_CROSSING)
        begin : cc
            ofs_plat_prim_rob_dc
              #(
                .N_ENTRIES(N_ENTRIES),
                .N_DATA_BITS(N_DATA_BITS),
                .N_META_BITS(N_META_BITS),
                .MIN_FREE_SLOTS(MIN_FREE_SLOTS),
                .MAX_ALLOC_PER_CYCLE(MAX_ALLOC_PER_CYCLE)
                )
              rob
               (
                .clk,
                .reset_n,
                .alloc_en,
                .allocCnt,
                .allocMeta,
                .notFull,
                .allocIdx,
                .inSpaceAvail,

                .enq_clk,
                .enq_reset_n,
                .enqData_en,
                .enqDataIdx,
                .enqData,

                .deq_en,
                .notEmpty,
                .T2_first,
                .T2_firstMeta
                );
        end
        else
        begin : nc
            ofs_plat_prim_rob
              #(
                .N_ENTRIES(N_ENTRIES),
                .N_DATA_BITS(N_DATA_BITS),
                .N_META_BITS(N_META_BITS),
                .MIN_FREE_SLOTS(MIN_FREE_SLOTS),
                .MAX_ALLOC_PER_CYCLE(MAX_ALLOC_PER_CYCLE)
                )
              rob
               (
                .clk,
                .reset_n,
                .alloc_en,
                .allocCnt,
                .allocMeta,
                .notFull,
                .allocIdx,
                .inSpaceAvail,

                .enqData_en,
                .enqDataIdx,
                .enqData,

                .deq_en,
                .notEmpty,
                .T2_first,
                .T2_firstMeta
                );
        end
    endgenerate

endmodule // ofs_plat_prim_rob_maybe_dc
