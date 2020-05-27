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
// Clock crossing for all five AXI memory channels. This shim does no credit
// management. If response buffer space must be reserved for in-flight reads
// and writes, manage credits upstream of this shim (toward the master).
// The shim ofs_plat_axi_mem_if_rsp_credits() can be used for that purpose.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_if_async_shim
  #(
    // Extra pipeline stages without flow control added on input to each FIFO
    // to relax timing. FIFO buffer space is reserved to store requests that
    // arrive after almost full is asserted. This is all managed internally.
    parameter ADD_TIMING_REG_STAGES = 2,

    // If the master guarantees to reserve space for all responses then the
    // ready signals on slave responses pipelines can be ignored, perhaps
    // improving timing.
    parameter SLAVE_RESPONSES_ALWAYS_READY = 0,

    parameter NUM_READ_CREDITS = 256,
    parameter NUM_WRITE_CREDITS = 128
    )
   (
    ofs_plat_axi_mem_if.to_slave mem_slave,
    ofs_plat_axi_mem_if.to_master mem_master
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_slave, mem_master)
    // synthesis translate_on

    logic master_reset_n;
    ofs_plat_prim_clock_crossing_reset_async m_reset_n
       (
        .clk(mem_master.clk),
        .reset_in(mem_master.reset_n),
        .reset_out(master_reset_n)
        );

    logic slave_reset_n;
    ofs_plat_prim_clock_crossing_reset_async s_reset_n
       (
        .clk(mem_slave.clk),
        .reset_in(mem_slave.reset_n),
        .reset_out(slave_reset_n)
        );

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(8),
        .DATA_WIDTH(mem_slave.T_AW_WIDTH)
        )
      aw
       (
        .clk_in(mem_master.clk),
        .reset_n_in(master_reset_n),

        .ready_in(mem_master.awready),
        .valid_in(mem_master.awvalid),
        .data_in(mem_master.aw),

        .clk_out(mem_slave.clk),
        .reset_n_out(slave_reset_n),

        .ready_out(mem_slave.awready),
        .valid_out(mem_slave.awvalid),
        .data_out(mem_slave.aw)
        );

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(8),
        .DATA_WIDTH(mem_slave.T_W_WIDTH)
        )
      w
       (
        .clk_in(mem_master.clk),
        .reset_n_in(master_reset_n),

        .ready_in(mem_master.wready),
        .valid_in(mem_master.wvalid),
        .data_in(mem_master.w),

        .clk_out(mem_slave.clk),
        .reset_n_out(slave_reset_n),

        .ready_out(mem_slave.wready),
        .valid_out(mem_slave.wvalid),
        .data_out(mem_slave.w)
        );


    logic slave_bready;
    assign mem_slave.bready = (SLAVE_RESPONSES_ALWAYS_READY ? 1'b1 : slave_bready);

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(SLAVE_RESPONSES_ALWAYS_READY ? ADD_TIMING_REG_STAGES : 0),
        .ADD_TIMING_READY_STAGES(0),
        .READY_FROM_ALMOST_FULL(0),
        .N_ENTRIES(NUM_WRITE_CREDITS),
        .DATA_WIDTH(mem_slave.T_B_WIDTH)
        )
      b
       (
        .clk_in(mem_slave.clk),
        .reset_n_in(slave_reset_n),

        .ready_in(slave_bready),
        .valid_in(mem_slave.bvalid),
        .data_in(mem_slave.b),

        .clk_out(mem_master.clk),
        .reset_n_out(master_reset_n),

        .ready_out(mem_master.bready),
        .valid_out(mem_master.bvalid),
        .data_out(mem_master.b)
        );


    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(8),
        .DATA_WIDTH(mem_slave.T_AR_WIDTH)
        )
      ar
       (
        .clk_in(mem_master.clk),
        .reset_n_in(master_reset_n),

        .ready_in(mem_master.arready),
        .valid_in(mem_master.arvalid),
        .data_in(mem_master.ar),

        .clk_out(mem_slave.clk),
        .reset_n_out(slave_reset_n),

        .ready_out(mem_slave.arready),
        .valid_out(mem_slave.arvalid),
        .data_out(mem_slave.ar)
        );

    logic slave_rready;
    assign mem_slave.rready = (SLAVE_RESPONSES_ALWAYS_READY ? 1'b1 : slave_rready);

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(SLAVE_RESPONSES_ALWAYS_READY ? ADD_TIMING_REG_STAGES : 0),
        .ADD_TIMING_READY_STAGES(0),
        .READY_FROM_ALMOST_FULL(0),
        .N_ENTRIES(NUM_READ_CREDITS),
        .DATA_WIDTH(mem_slave.T_R_WIDTH)
        )
      r
       (
        .clk_in(mem_slave.clk),
        .reset_n_in(slave_reset_n),

        .ready_in(slave_rready),
        .valid_in(mem_slave.rvalid),
        .data_in(mem_slave.r),

        .clk_out(mem_master.clk),
        .reset_n_out(master_reset_n),

        .ready_out(mem_master.rready),
        .valid_out(mem_master.rvalid),
        .data_out(mem_master.r)
        );

endmodule // ofs_plat_axi_mem_if_async_shim


//
// Internal shim for a single channel.
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

endmodule // ofs_plat_axi_mem_if_async_shim
