//
// Copyright (c) 2022, Intel Corporation
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
// Preserve ID and USER fields from requests and restore them as responses
// arrive. Use this module when a sink does not return the full ID or USER
// state along with a response. The behavior is similar to the handling of
// metadata in ofs_plat_axi_mem_if_async_rob, except that no reordering is
// performed.
//
// The module manages a private tag space for read and write request streams
// that is written to outgoing requests and used to index the internal RAM
// to restore the original metadata.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_if_preserve_meta
  #(
    parameter NUM_READ_CREDITS = 256,
    parameter NUM_WRITE_CREDITS = 128,
    // Add a register stage to the tagged RAM output for timing?
    parameter REGISTER_RAM_OUTPUT = 0
    )
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    localparam N_OUTPUT_REG_STAGES = (REGISTER_RAM_OUTPUT != 0) ? 1 : 0;

    wire clk = mem_sink.clk;
    wire reset_n = mem_sink.reset_n;

    //
    // Copies of the sink and source interfaces that can be used for
    // internal, intermediate states using the sized data structures.
    //

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_sink),
        .DISABLE_CHECKER(1)
        )
      mem_sink_local[2]();

    // synthesis translate_off
    initial
    begin
        assert (mem_sink.RID_WIDTH >= $clog2(NUM_READ_CREDITS)) else
            $fatal(2, "** ERROR ** %m: mem_sink.RID_WIDTH (%d) is too small for RAM index (%d)!",
                   mem_sink.RID_WIDTH, NUM_READ_CREDITS);

        assert (mem_sink.WID_WIDTH >= $clog2(NUM_WRITE_CREDITS)) else
            $fatal(2, "** ERROR ** %m: mem_sink.WID_WIDTH (%d) is too small for RAM index (%d)!",
                   mem_sink.WID_WIDTH, NUM_WRITE_CREDITS);
    end
    // synthesis translate_on


    // ====================================================================
    // 
    //  Writes
    // 
    // ====================================================================

    // Guarantee N_ENTRIES is a power of 2
    localparam WR_META_N_ENTRIES = 1 << $clog2(NUM_WRITE_CREDITS);
    typedef logic [$clog2(WR_META_N_ENTRIES)-1 : 0] t_wr_meta_idx;

    t_wr_meta_idx wr_meta_allocIdx;
    logic wr_meta_notFull;
    logic wr_meta_valid;
    logic [mem_source.WID_WIDTH + mem_source.USER_WIDTH - 1 : 0] wr_meta_first;
    logic [mem_source.WID_WIDTH + mem_source.USER_WIDTH - 1 : 0] wr_meta_rsp;

    // Construct the AW sink payload, saving the index as the ID field
    assign mem_sink.awvalid = mem_source.awvalid && wr_meta_notFull;
    assign mem_source.awready = mem_sink.awready && wr_meta_notFull;
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_sink.aw, =, mem_source.aw);

        mem_sink.aw.id = wr_meta_allocIdx;
    end

    // Write data is connected directly
    assign mem_sink.wvalid = mem_source.wvalid;
    assign mem_source.wready = mem_sink.wready;
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_sink.w, =, mem_source.w);
    end

    ofs_plat_prim_tagged_ram
      #(
        .N_ENTRIES(NUM_WRITE_CREDITS),
        .N_DATA_BITS(mem_source.WID_WIDTH + mem_source.USER_WIDTH),
        .N_OUTPUT_REG_STAGES(N_OUTPUT_REG_STAGES)
        )
      wr_meta
       (
        .clk,
        .reset_n,

        .alloc_en(mem_source.awvalid && mem_source.awready),
        .allocData({ mem_source.aw.id, mem_source.aw.user }),
        .notFull(wr_meta_notFull),
        .allocIdx(wr_meta_allocIdx),

        .rd_en(mem_sink.bvalid && mem_sink.bready),
        .rdIdx(t_wr_meta_idx'(mem_sink.b.id)),
        // Data arrives TWO CYCLES AFTER rd_en is asserted
        .first(wr_meta_first),
        .valid(wr_meta_valid),

        .deq_en(mem_sink.bvalid && mem_sink.bready),
        .deqIdx(t_wr_meta_idx'(mem_sink.b.id))
        );


    //
    // Two register stages of write response to match the latency of
    // wr_meta_first. It's ok if the pipeline stalls. wr_meta_first
    // feeds a FIFO that will hold wr_meta_first until the stalled
    // pipeline is ready.
    //
    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(mem_sink.T_B_WIDTH)
        )
      b1
       (
        .clk,
        .reset_n,

        .enable_from_src(mem_sink.bvalid),
        .data_from_src(mem_sink.b),
        .ready_to_src(mem_sink.bready),

        .enable_to_dst(mem_sink_local[0].bvalid),
        .data_to_dst(mem_sink_local[0].b),
        .ready_from_dst(mem_sink_local[0].bready)
        );

    generate
        if (N_OUTPUT_REG_STAGES > 0)
        begin : b2
            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_sink.T_B_WIDTH)
                )
              skid
               (
                .clk,
                .reset_n,

                .enable_from_src(mem_sink_local[0].bvalid),
                .data_from_src(mem_sink_local[0].b),
                .ready_to_src(mem_sink_local[0].bready),

                .enable_to_dst(mem_sink_local[1].bvalid),
                .data_to_dst(mem_sink_local[1].b),
                .ready_from_dst(mem_sink_local[1].bready)
                );
        end
    endgenerate


    // Feed wr_meta_first into a FIFO in case the mem_sink_local pipeline
    // stalls. The pipeline is bypassed so that notEmpty is asserted the
    // same cycle that enq_en is set.
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(mem_source.WID_WIDTH + mem_source.USER_WIDTH),
        .BYPASS_FIFO(1)
        )
      b_fifo
       (
        .clk,
        .reset_n,

        .enq_data(wr_meta_first),
        .enq_en(wr_meta_valid),
        .notFull(),	// Pipeline can't fill due to pipeline

        .first(wr_meta_rsp),
        .deq_en(mem_source.bvalid && mem_source.bready),
        .notEmpty()     // Data ready by design
        );


    // Restore metadata in write response
    assign mem_source.bvalid = mem_sink_local[N_OUTPUT_REG_STAGES].bvalid;
    assign mem_sink_local[N_OUTPUT_REG_STAGES].bready = mem_source.bready;
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_B(mem_source.b, =, mem_sink_local[N_OUTPUT_REG_STAGES].b);

        { mem_source.b.id, mem_source.b.user } = wr_meta_rsp;
    end


    // ====================================================================
    // 
    //  Reads
    // 
    // ====================================================================

    // Guarantee N_ENTRIES is a power of 2
    localparam RD_META_N_ENTRIES = 1 << $clog2(NUM_READ_CREDITS);
    typedef logic [$clog2(RD_META_N_ENTRIES)-1 : 0] t_rd_meta_idx;

    t_rd_meta_idx rd_meta_allocIdx;
    logic rd_meta_notFull;
    logic rd_meta_valid;
    logic [mem_source.RID_WIDTH + mem_source.USER_WIDTH - 1 : 0] rd_meta_first;
    logic [mem_source.RID_WIDTH + mem_source.USER_WIDTH - 1 : 0] rd_meta_rsp;

    // Construct the AR sink payload, saving the index as the ID field
    assign mem_sink.arvalid = mem_source.arvalid && rd_meta_notFull;
    assign mem_source.arready = mem_sink.arready && rd_meta_notFull;
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_sink.ar, =, mem_source.ar);

        mem_sink.ar.id = rd_meta_allocIdx;
    end

    // Use the IDX from the SOP beat to index the metadata RAM
    logic rd_meta_rsp_is_sop;
    t_rd_meta_idx rd_rsp_hdr_idx;
    logic rd_meta_rsp_deq;

    ofs_plat_prim_tagged_ram
      #(
        .N_ENTRIES(NUM_READ_CREDITS),
        .N_DATA_BITS(mem_source.RID_WIDTH + mem_source.USER_WIDTH),
        .N_OUTPUT_REG_STAGES(N_OUTPUT_REG_STAGES)
        )
      rd_meta
       (
        .clk,
        .reset_n,

        .alloc_en(mem_source.arvalid && mem_source.arready),
        .allocData({ mem_source.ar.id, mem_source.ar.user }),
        .notFull(rd_meta_notFull),
        .allocIdx(rd_meta_allocIdx),

        .rd_en(mem_sink.rvalid && mem_sink.rready),
        .rdIdx(rd_meta_rsp_is_sop ? t_rd_meta_idx'(mem_sink.r.id) : rd_rsp_hdr_idx),
        // Data arrives TWO CYCLES AFTER rd_en is asserted
        .first(rd_meta_first),
        .valid(rd_meta_valid),

        .deq_en(rd_meta_rsp_deq),
        .deqIdx(rd_rsp_hdr_idx)
        );

    always_ff @(posedge clk)
    begin
        // Hold the metadata index for subsequent beats after the SOP
        if (mem_sink.rvalid && mem_sink.rready && rd_meta_rsp_is_sop)
            rd_rsp_hdr_idx <= t_rd_meta_idx'(mem_sink.r.id);

        // Free the metadata entry the cycle after the packet is complete
        rd_meta_rsp_deq <= mem_sink.rvalid && mem_sink.rready && mem_sink.r.last;

        // Track read response SOP
        if (mem_sink.rvalid && mem_sink.rready)
            rd_meta_rsp_is_sop <= mem_sink.r.last;

        if (!reset_n)
            rd_meta_rsp_is_sop <= 1'b1;
    end


    //
    // Two register stages of read response to match the latency of
    // rd_meta_first. It's ok if the pipeline stalls. rd_meta_first
    // feeds a FIFO that will hold rd_meta_first until the stalled
    // pipeline is ready.
    //
    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(mem_sink.T_R_WIDTH)
        )
      r1
       (
        .clk,
        .reset_n,

        .enable_from_src(mem_sink.rvalid),
        .data_from_src(mem_sink.r),
        .ready_to_src(mem_sink.rready),

        .enable_to_dst(mem_sink_local[0].rvalid),
        .data_to_dst(mem_sink_local[0].r),
        .ready_from_dst(mem_sink_local[0].rready)
        );

    generate
        if (N_OUTPUT_REG_STAGES > 0)
        begin : r2
            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_sink.T_R_WIDTH)
                )
              skid
               (
                .clk,
                .reset_n,

                .enable_from_src(mem_sink_local[0].rvalid),
                .data_from_src(mem_sink_local[0].r),
                .ready_to_src(mem_sink_local[0].rready),

                .enable_to_dst(mem_sink_local[1].rvalid),
                .data_to_dst(mem_sink_local[1].r),
                .ready_from_dst(mem_sink_local[1].rready)
                );
        end
    endgenerate


    // Feed rd_meta_first into a FIFO in case the mem_sink_local pipeline
    // stalls. The pipeline is bypassed so that notEmpty is asserted the
    // same cycle that enq_en is set.
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(mem_source.RID_WIDTH + mem_source.USER_WIDTH),
        .BYPASS_FIFO(1)
        )
      r_fifo
       (
        .clk,
        .reset_n,

        .enq_data(rd_meta_first),
        .enq_en(rd_meta_valid),
        .notFull(),	// Pipeline can't fill due to pipeline

        .first(rd_meta_rsp),
        .deq_en(mem_source.rvalid && mem_source.rready),
        .notEmpty()     // Data ready by design
        );


    // Restore metadata in read response
    assign mem_source.rvalid = mem_sink_local[N_OUTPUT_REG_STAGES].rvalid;
    assign mem_sink_local[N_OUTPUT_REG_STAGES].rready = mem_source.rready;
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_R(mem_source.r, =, mem_sink_local[N_OUTPUT_REG_STAGES].r);

        { mem_source.r.id, mem_source.r.user } = rd_meta_rsp;
    end

endmodule // ofs_plat_axi_mem_if_preserve_meta
