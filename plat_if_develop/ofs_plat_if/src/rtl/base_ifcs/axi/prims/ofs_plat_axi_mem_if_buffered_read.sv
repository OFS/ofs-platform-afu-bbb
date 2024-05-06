// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Add a FIFO to the read response path and guarantee that an entry is
// available for every outstanding read request.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_if_buffered_read
  #(
    parameter NUM_READ_ENTRIES = 512
    )
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    localparam MAX_ALLOC_PER_CYCLE = 1 << mem_source.BURST_CNT_WIDTH;
    // Extra bit in order to represent the value MAX_ALLOC_PER_CYCLE
    typedef logic [$clog2(MAX_ALLOC_PER_CYCLE):0] t_alloc_cnt;

    localparam R_WIDTH = mem_sink.T_R_WIDTH;

    logic almostFull;
    assign mem_source.arready = mem_sink.arready && !almostFull;
    assign mem_sink.arvalid = mem_source.arvalid && !almostFull;
    assign mem_sink.ar = mem_source.ar;

    ofs_plat_prim_fifo_buffer
      #(
        .N_ENTRIES(NUM_READ_ENTRIES),
        .MAX_ALLOC_PER_CYCLE(MAX_ALLOC_PER_CYCLE),
        .N_DATA_BITS(R_WIDTH)
        )
      rd_buf
       (
        .clk(mem_sink.clk),
        .reset_n(mem_sink.reset_n),

        // Slot allocation at request time
        .alloc_en(mem_source.arvalid && mem_source.arready),
        // Convert to 1 based lengths (AXI is zero based)
        .allocCnt(t_alloc_cnt'(mem_source.ar.len) + t_alloc_cnt'(1)),
        .almostFull,

        // Incoming read responses from the sink to the buffer
        .enq_data(mem_sink.r),
        .enq_en(mem_sink.rvalid && mem_sink.rready),
        .notFull(mem_sink.rready),

        // Outgoing read responses from the buffer to the source
        .first(mem_source.r),
        .deq_en(mem_source.rvalid && mem_source.rready),
        .notEmpty(mem_source.rvalid)
        );


    // Simple connections for AXI write channels
    always_comb
    begin
        mem_sink.awvalid = mem_source.awvalid;
        mem_sink.wvalid = mem_source.wvalid;
        mem_sink.bready = mem_source.bready;
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_sink.aw, =, mem_source.aw);
        `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_sink.w, =, mem_source.w);

        mem_source.awready = mem_sink.awready;
        mem_source.wready = mem_sink.wready;
        mem_source.bvalid = mem_sink.bvalid;
        `OFS_PLAT_AXI_MEM_IF_COPY_B(mem_source.b, =, mem_sink.b);
    end

endmodule // ofs_plat_axi_mem_if_buffered_read
