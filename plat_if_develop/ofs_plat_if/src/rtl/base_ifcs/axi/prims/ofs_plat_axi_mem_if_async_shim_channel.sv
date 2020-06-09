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
// Single AXI channel clock crossing FIFO.
//
module ofs_plat_axi_mem_if_async_shim_channel
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


    // Outbound FIFO to relax timing pressure
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(DATA_WIDTH)
        )
      fifo2
       (
        .clk(clk_out),
        .reset_n(reset_n_out),

        .enq_data(crossed_data),
        .enq_en(crossed_notEmpty && crossed_notFull),
        .notFull(crossed_notFull),

        .first(data_out),
        .deq_en(ready_out && valid_out),
        .notEmpty(valid_out)
        );

endmodule // ofs_plat_axi_mem_if_async_shim_channel
