// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Clock crossing for all five AXI memory channels. This shim does no credit
// management.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_lite_if_async_shim
  #(
    // Extra pipeline stages without flow control added on input to each FIFO
    // to relax timing. FIFO buffer space is reserved to store requests that
    // arrive after almost full is asserted. This is all managed internally.
    parameter ADD_TIMING_REG_STAGES = 2,

    // If the source guarantees to reserve space for all responses then the
    // ready signals on sink responses pipelines can be ignored, perhaps
    // improving timing.
    parameter SINK_RESPONSES_ALWAYS_READY = 0
    )
   (
    ofs_plat_axi_mem_lite_if.to_sink mem_sink,
    ofs_plat_axi_mem_lite_if.to_source mem_source
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    logic source_reset_n;
    ofs_plat_prim_clock_crossing_reset_async m_reset_n
       (
        .clk(mem_source.clk),
        .reset_in(mem_source.reset_n),
        .reset_out(source_reset_n)
        );

    logic sink_reset_n;
    ofs_plat_prim_clock_crossing_reset_async s_reset_n
       (
        .clk(mem_sink.clk),
        .reset_in(mem_sink.reset_n),
        .reset_out(sink_reset_n)
        );

    ofs_plat_prim_ready_enable_async
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_sink.T_AW_WIDTH)
        )
      aw
       (
        .clk_in(mem_source.clk),
        .reset_n_in(source_reset_n),

        .ready_in(mem_source.awready),
        .valid_in(mem_source.awvalid),
        .data_in(mem_source.aw),

        .clk_out(mem_sink.clk),
        .reset_n_out(sink_reset_n),

        .ready_out(mem_sink.awready),
        .valid_out(mem_sink.awvalid),
        .data_out(mem_sink.aw)
        );

    ofs_plat_prim_ready_enable_async
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_sink.T_W_WIDTH)
        )
      w
       (
        .clk_in(mem_source.clk),
        .reset_n_in(source_reset_n),

        .ready_in(mem_source.wready),
        .valid_in(mem_source.wvalid),
        .data_in(mem_source.w),

        .clk_out(mem_sink.clk),
        .reset_n_out(sink_reset_n),

        .ready_out(mem_sink.wready),
        .valid_out(mem_sink.wvalid),
        .data_out(mem_sink.w)
        );


    logic sink_bready;
    assign mem_sink.bready = (SINK_RESPONSES_ALWAYS_READY ? 1'b1 : sink_bready);

    ofs_plat_prim_ready_enable_async
      #(
        .ADD_TIMING_REG_STAGES(SINK_RESPONSES_ALWAYS_READY ? ADD_TIMING_REG_STAGES : 0),
        .ADD_TIMING_READY_STAGES(0),
        .READY_FROM_ALMOST_FULL(0),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_sink.T_B_WIDTH)
        )
      b
       (
        .clk_in(mem_sink.clk),
        .reset_n_in(sink_reset_n),

        .ready_in(sink_bready),
        .valid_in(mem_sink.bvalid),
        .data_in(mem_sink.b),

        .clk_out(mem_source.clk),
        .reset_n_out(source_reset_n),

        .ready_out(mem_source.bready),
        .valid_out(mem_source.bvalid),
        .data_out(mem_source.b)
        );


    ofs_plat_prim_ready_enable_async
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_sink.T_AR_WIDTH)
        )
      ar
       (
        .clk_in(mem_source.clk),
        .reset_n_in(source_reset_n),

        .ready_in(mem_source.arready),
        .valid_in(mem_source.arvalid),
        .data_in(mem_source.ar),

        .clk_out(mem_sink.clk),
        .reset_n_out(sink_reset_n),

        .ready_out(mem_sink.arready),
        .valid_out(mem_sink.arvalid),
        .data_out(mem_sink.ar)
        );

    logic sink_rready;
    assign mem_sink.rready = (SINK_RESPONSES_ALWAYS_READY ? 1'b1 : sink_rready);

    ofs_plat_prim_ready_enable_async
      #(
        .ADD_TIMING_REG_STAGES(SINK_RESPONSES_ALWAYS_READY ? ADD_TIMING_REG_STAGES : 0),
        .ADD_TIMING_READY_STAGES(0),
        .READY_FROM_ALMOST_FULL(0),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_sink.T_R_WIDTH)
        )
      r
       (
        .clk_in(mem_sink.clk),
        .reset_n_in(sink_reset_n),

        .ready_in(sink_rready),
        .valid_in(mem_sink.rvalid),
        .data_in(mem_sink.r),

        .clk_out(mem_source.clk),
        .reset_n_out(source_reset_n),

        .ready_out(mem_source.rready),
        .valid_out(mem_source.rvalid),
        .data_out(mem_source.r)
        );

endmodule // ofs_plat_axi_mem_lite_if_async_shim


// Same as standard crossing, but set the sink's clock
module ofs_plat_axi_mem_lite_if_async_shim_set_sink
  #(
    parameter ADD_TIMING_REG_STAGES = 2,
    parameter SINK_RESPONSES_ALWAYS_READY = 0
    )
   (
    ofs_plat_axi_mem_lite_if.to_sink_clk mem_sink,
    ofs_plat_axi_mem_lite_if.to_source mem_source,

    input  logic sink_clk,
    input  logic sink_reset_n
    );

    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mem_sink)
        )
      mem_sink_with_clk();

    assign mem_sink_with_clk.clk = sink_clk;
    assign mem_sink_with_clk.reset_n = sink_reset_n;
    assign mem_sink_with_clk.instance_number = mem_source.instance_number;

    ofs_plat_axi_mem_lite_if_connect_source_clk con_sink
       (
        .mem_source(mem_sink_with_clk),
        .mem_sink
        );

    ofs_plat_axi_mem_lite_if_async_shim
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SINK_RESPONSES_ALWAYS_READY(SINK_RESPONSES_ALWAYS_READY)
        )
      cc
       (
        .mem_sink(mem_sink_with_clk),
        .mem_source
        );

endmodule // ofs_plat_axi_mem_lite_if_async_shim_set_sink
