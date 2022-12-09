// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Break counter into a two-cycle operation. The output is delayed one cycle.
// At most half the counter's size can be added to it in one cycle.
//
module counter_multicycle
  #(
    parameter NUM_BITS = 64
    )
   (
    input  logic clk,
    input  logic reset_n,
    input  logic [NUM_BITS-1 : 0] incr_by,
    output logic [NUM_BITS-1 : 0] value
    );

    localparam HALF_BITS = NUM_BITS / 2;

    logic [HALF_BITS - 1 : 0] low_half;
    logic carry;

    always_ff @(posedge clk)
    begin
        // First stage: add incr_by to low half and note a carry
        { carry, low_half } <= low_half + HALF_BITS'(incr_by);

        // Second stage: pass on the low half and add the carry to the upper half
        value[HALF_BITS-1 : 0] <= low_half;
        value[NUM_BITS-1 : HALF_BITS] <= value[NUM_BITS-1 : HALF_BITS] + carry;

        if (!reset_n)
        begin
            value <= 0;
            low_half <= 0;
        end
    end

    // synthesis translate_off
    always_ff @(posedge clk)
    begin
        if (reset_n && |(incr_by[NUM_BITS-1 : HALF_BITS]))
        begin
            $fatal(2, "** ERROR ** %m: The upper half of incr_by is ignored (0x%h)!", incr_by);
        end
    end
    // synthesis translate_on

endmodule // counter_multicycle
