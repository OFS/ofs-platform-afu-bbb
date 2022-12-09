// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// fifo2 --
//   A FIFO with two storage elements supporting full pipelining.
//

module fifo2
  #(
    parameter N_DATA_BITS = 32
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,

    output logic [N_DATA_BITS-1 : 0] first,
    input  logic deq_en,
    output logic notEmpty
    );

    fifo2_peek
      #(
        .N_DATA_BITS(N_DATA_BITS)
        )
      f
       (
        .clk,
        .reset_n,

        .enq_data,
        .enq_en,
        .notFull,

        .first,
        .deq_en,
        .notEmpty,

        .peek_valid(),
        .peek_value()
        );

endmodule // fifo2


//
// FIFO2 with the internal data state exposed
//
module fifo2_peek
  #(
    parameter N_DATA_BITS = 32
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,

    output logic [N_DATA_BITS-1 : 0] first,
    input  logic deq_en,
    output logic notEmpty,

    output logic [1:0] peek_valid,
    output logic [1:0][N_DATA_BITS-1 : 0] peek_value
    );

    logic [1:0] valid;
    logic [N_DATA_BITS-1 : 0] data[0 : 1];

    assign notFull = ~valid[0];
    assign first = data[1];
    assign notEmpty = valid[1];

    always_ff @(posedge clk)
    begin
        // Target output slot if it is empty or dequeued this cycle
        if (! valid[1] || deq_en)
        begin
            // Output slot will be valid next cycle if slot 0 has data
            // or a new value is enqueued this cycle.  Both can't be
            // true, so valid[0] will definitely be 0 next cycle.
            valid[0] <= 1'b0;
            valid[1] <= valid[0] || enq_en;
            data[1] <= valid[0] ? data[0] : enq_data;
        end
        else
        begin
            // Target of enq is slot 0.  It will be valid if there was
            // data and it didn't shift or if new data is enqueued.
            valid[0] <= (valid[0] && ! deq_en) || enq_en;
        end

        // Speculatively store data if the slot is empty. If the slot
        // was valid then no enqueue will be allowed.
        if (! valid[0])
        begin
            data[0] <= enq_data;
        end

        if (!reset_n)
        begin
            valid <= 2'b0;
        end
    end

    // synthesis translate_off
    always_ff @(posedge clk)
    begin
        if (reset_n)
        begin
            assert (! (enq_en && valid[0])) else
                $fatal(2, "** ERROR ** %m: ENQ to full FIFO!");
            assert (! (deq_en && ! valid[1])) else
                $fatal(2, "** ERROR ** %m: DEQ from empty FIFO!");
        end
    end
    // synthesis translate_on

    assign peek_valid = valid;
    assign peek_value[0] = data[0];
    assign peek_value[1] = data[1];

endmodule // fifo2_peek
