// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Single ready/enable channel clock crossing FIFO.
//
module ofs_plat_prim_ready_enable_async
  #(
    parameter ADD_TIMING_REG_STAGES = 2,
    parameter ADD_TIMING_READY_STAGES = 2,
    parameter READY_FROM_ALMOST_FULL = 1,
    parameter N_ENTRIES = 16,
    parameter DATA_WIDTH = 1
    )
   (
    input  logic clk_in,
    input  logic reset_n_in,

    output logic ready_in,
    input  logic valid_in,
    input  logic [DATA_WIDTH-1 : 0] data_in,

    input  logic clk_out,
    input  logic reset_n_out,

    input  logic ready_out,
    output logic valid_out,
    output logic [DATA_WIDTH-1 : 0] data_out
    );

    // Need extra buffering to handle the incoming data pipeline registers and
    // latency of registered ready signals? When READY_FROM_ALMOST_FULL is 1
    // we assume that the buffering is required. When 0, we assume that the
    // traffic has been managed to avoid overflow.
    localparam EXTRA_STAGES = ADD_TIMING_READY_STAGES +
                              (READY_FROM_ALMOST_FULL ? ADD_TIMING_REG_STAGES : 0);

    // Input pipeline. Space is reserved in the FIFO for the full contents
    // of the pipeline.
    logic pipe_valid_in[ADD_TIMING_REG_STAGES + 1];
    logic [DATA_WIDTH-1 : 0] pipe_data_in[ADD_TIMING_REG_STAGES + 1];

    genvar p;
    generate
        assign pipe_valid_in[ADD_TIMING_REG_STAGES] = valid_in && ready_in;
        assign pipe_data_in[ADD_TIMING_REG_STAGES] = data_in;

        for (p = 0; p < ADD_TIMING_REG_STAGES; p = p + 1)
        begin : s
            always_ff @(posedge clk_in)
            begin
                pipe_valid_in[p] <= pipe_valid_in[p + 1];
                pipe_data_in[p] <= pipe_data_in[p + 1];
            end
        end
    endgenerate

    // Ready pipeline. Space is reserved for the latency of this also.
    logic notFull;
    logic almostFull;
    logic pipe_ready_in[ADD_TIMING_READY_STAGES + 1];

    assign pipe_ready_in[ADD_TIMING_READY_STAGES] =
        (READY_FROM_ALMOST_FULL ? !almostFull : notFull);
    assign ready_in = pipe_ready_in[0];

    generate
        for (p = 0; p < ADD_TIMING_READY_STAGES; p = p + 1)
        begin : pr
            always_ff @(posedge clk_in)
            begin
                pipe_ready_in[p] <= pipe_ready_in[p + 1];
            end
        end
    endgenerate

    logic [DATA_WIDTH-1 : 0] crossed_data;
    logic crossed_notEmpty, crossed_notFull;

    ofs_plat_prim_fifo_dc
      #(
        .N_DATA_BITS(DATA_WIDTH),
        .N_ENTRIES(N_ENTRIES + EXTRA_STAGES),
        .THRESHOLD(1 + EXTRA_STAGES)
        )
      fifo
       (
        .enq_clk(clk_in),
        .enq_reset_n(reset_n_in),
        .enq_data(pipe_data_in[0]),
        .enq_en(pipe_valid_in[0]),
        .notFull,
        .almostFull,

        .deq_clk(clk_out),
        .deq_reset_n(reset_n_out),
        .first(crossed_data),
        .deq_en(crossed_notEmpty && crossed_notFull),
        .notEmpty(crossed_notEmpty)
        );


    // Register outbound data to relax timing pressure
    ofs_plat_prim_ready_enable_reg
      #(
        .N_DATA_BITS(DATA_WIDTH)
        )
      reg_out
       (
        .clk(clk_out),
        .reset_n(reset_n_out),

        .data_from_src(crossed_data),
        .enable_from_src(crossed_notEmpty),
        .ready_to_src(crossed_notFull),

        .data_to_dst(data_out),
        .enable_to_dst(valid_out),
        .ready_from_dst(ready_out)
        );

endmodule // ofs_plat_prim_ready_enable_async
