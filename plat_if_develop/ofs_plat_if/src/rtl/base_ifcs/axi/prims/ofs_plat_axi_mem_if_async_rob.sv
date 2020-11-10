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
// Reorder buffer combined with clock crossing for all five AXI memory channels.
// This shim does no credit management. If response buffer space must be reserved
// for in-flight reads and writes, manage credits upstream of this shim (toward
// the source). The shim ofs_plat_axi_mem_if_rsp_credits() can be used for that
// purpose.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_if_async_rob
  #(
    // When non-zero, add a clock crossing along with the ROB.
    parameter ADD_CLOCK_CROSSING = 0,

    // Extra pipeline stages without flow control added on input to each FIFO
    // to relax timing. FIFO buffer space is reserved to store requests that
    // arrive after almost full is asserted. This is all managed internally.
    parameter ADD_TIMING_REG_STAGES = 2,

    // If the source guarantees to reserve space for all responses then the
    // ready signals on sink responses pipelines can be ignored, perhaps
    // improving timing.
    parameter SINK_RESPONSES_ALWAYS_READY = 0,

    parameter NUM_READ_CREDITS = 256,
    parameter NUM_WRITE_CREDITS = 128
    )
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    //
    // Copies of the sink and source interfaces that can be used for
    // internal, intermediate states using the sized data structures.
    //

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_sink),
        .DISABLE_CHECKER(1)
        )
      mem_sink_local();

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_source),
        .DISABLE_CHECKER(1)
        )
      mem_source_local();

    // synthesis translate_off
    initial
    begin
        assert (mem_sink.RID_WIDTH >= $clog2(NUM_READ_CREDITS)) else
            $fatal(2, "** ERROR ** %m: mem_sink.RID_WIDTH (%d) is too small for ROB index (%d)!",
                   mem_sink.RID_WIDTH, NUM_READ_CREDITS);

        assert (mem_sink.WID_WIDTH >= $clog2(NUM_WRITE_CREDITS)) else
            $fatal(2, "** ERROR ** %m: mem_sink.WID_WIDTH (%d) is too small for ROB index (%d)!",
                   mem_sink.WID_WIDTH, NUM_WRITE_CREDITS);
    end
    // synthesis translate_on


    // ====================================================================
    // 
    //  Writes
    // 
    // ====================================================================

    //
    // AW request channel determines the order of B channel responses.
    //

    logic wr_rob_notFull;
    logic wr_fifo_notFull;
    logic wr_rsp_almostFull;
    logic wr_rsp_valid, wr_rsp_valid_q;

    // Both the ROB and the clock crossing FIFO must have space
    assign mem_source.awready = wr_rob_notFull & wr_fifo_notFull;
    // ROB reserves enough space for all outstanding responses
    assign mem_sink.bready = 1'b1;

    // Guarantee N_ENTRIES is a power of 2
    localparam WR_ROB_N_ENTRIES = 1 << $clog2(NUM_WRITE_CREDITS);
    typedef logic [$clog2(WR_ROB_N_ENTRIES)-1 : 0] t_wr_rob_idx;
    t_wr_rob_idx wr_next_allocIdx;

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(WR_ROB_N_ENTRIES),
        .N_DATA_BITS($bits(ofs_plat_axi_mem_pkg::t_axi_resp)),
        .N_META_BITS(mem_source.WID_WIDTH + mem_source.USER_WIDTH),
        .MAX_ALLOC_PER_CYCLE(1)
        )
      wr_rob
       (
        .clk(mem_source.clk),
        .reset_n(mem_source.reset_n),
        .alloc_en(mem_source.awvalid && mem_source.awready),
        .allocCnt(1'b1),
        .allocMeta({ mem_source.aw.id, mem_source.aw.user }),
        .notFull(wr_rob_notFull),
        .allocIdx(wr_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_sink.clk),
        .enq_reset_n(mem_sink.reset_n),
        .enqData_en(mem_sink.bvalid),
        .enqDataIdx(mem_sink.b.id[0 +: $clog2(WR_ROB_N_ENTRIES)]),
        .enqData(mem_sink.b.resp),

        .deq_en(wr_rsp_valid && !wr_rsp_almostFull),
        .notEmpty(wr_rsp_valid),
        .T2_first(mem_source_local.b.resp),
        .T2_firstMeta({ mem_source_local.b.id, mem_source_local.b.user })
        );

    // Construct the AW sink payload, saving the ROB index as the ID field
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_sink_local.aw, =, mem_source.aw);

        mem_sink_local.aw.id = wr_next_allocIdx;
    end

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_sink.T_AW_WIDTH)
        )
      aw
       (
        .clk_in(mem_source.clk),
        .reset_n_in(mem_source.reset_n),

        .ready_in(wr_fifo_notFull),
        .valid_in(mem_source.awvalid && mem_source.awready),
        .data_in(mem_sink_local.aw),

        .clk_out(mem_sink.clk),
        .reset_n_out(mem_sink.reset_n),

        .ready_out(mem_sink.awready),
        .valid_out(mem_sink.awvalid),
        .data_out(mem_sink.aw)
        );

    // Write data is just a clock crossing, independent of the AW control. Fields
    // still have to mapped, though, due to size changes.
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_sink_local.w, =, mem_source.w);
    end

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_sink.T_W_WIDTH)
        )
      w
       (
        .clk_in(mem_source.clk),
        .reset_n_in(mem_source.reset_n),

        .ready_in(mem_source.wready),
        .valid_in(mem_source.wvalid),
        .data_in(mem_sink_local.w),

        .clk_out(mem_sink.clk),
        .reset_n_out(mem_sink.reset_n),

        .ready_out(mem_sink.wready),
        .valid_out(mem_sink.wvalid),
        .data_out(mem_sink.w)
        );


    // Sorted responses. The ROB's ready latency is 2 cycles. Feed responses
    // into a FIFO that will handle flow control from the source.
    always_ff @(posedge mem_source.clk)
    begin
        wr_rsp_valid_q <= wr_rsp_valid && !wr_rsp_almostFull;
        mem_source_local.bvalid <= wr_rsp_valid_q;
    end

    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS(mem_source.T_B_WIDTH),
        .N_ENTRIES(4),
        .THRESHOLD(2),
        .REGISTER_OUTPUT(1)
        )
      b
       (
        .clk(mem_source.clk),
        .reset_n(mem_source.reset_n),

        .enq_data(mem_source_local.b),
        .enq_en(mem_source_local.bvalid),
        .notFull(),
        .almostFull(wr_rsp_almostFull),

        .first(mem_source.b),
        .deq_en(mem_source.bready && mem_source.bvalid),
        .notEmpty(mem_source.bvalid)
        );


    // ====================================================================
    // 
    //  Reads
    // 
    // ====================================================================

    logic rd_rob_notFull;
    logic rd_fifo_notFull;
    logic rd_rsp_almostFull;
    logic rd_rsp_valid, rd_rsp_valid_q;

    // Both the ROB and the clock crossing FIFO must have space
    assign mem_source.arready = rd_rob_notFull & rd_fifo_notFull;
    // ROB reserves enough space for all outstanding responses
    assign mem_sink.rready = 1'b1;

    localparam RD_ROB_N_ENTRIES = 1 << $clog2(NUM_READ_CREDITS);
    typedef logic [$clog2(RD_ROB_N_ENTRIES)-1 : 0] t_rd_rob_idx;
    t_rd_rob_idx rd_next_allocIdx;

    typedef logic [mem_sink.BURST_CNT_WIDTH : 0] t_rd_alloc_cnt;

    typedef logic [mem_source.RID_WIDTH-1 : 0] t_source_rid;
    typedef logic [mem_source.USER_WIDTH-1 : 0] t_source_user;
    t_source_rid rd_id, rd_reg_id;
    t_source_user rd_user, rd_reg_user;

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(RD_ROB_N_ENTRIES),
        .N_DATA_BITS(mem_sink.T_R_WIDTH),
        .N_META_BITS(mem_source.RID_WIDTH + mem_source.USER_WIDTH),
        .MAX_ALLOC_PER_CYCLE(1 << mem_sink.BURST_CNT_WIDTH)
        )
      rd_rob
       (
        .clk(mem_source.clk),
        .reset_n(mem_source.reset_n),
        .alloc_en(mem_source.arvalid && mem_source.arready),
        .allocCnt(t_rd_alloc_cnt'(mem_source.ar.len) + t_rd_alloc_cnt'(1)),
        .allocMeta({ mem_source.ar.id, mem_source.ar.user }),
        .notFull(rd_rob_notFull),
        .allocIdx(rd_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_sink.clk),
        .enq_reset_n(mem_sink.reset_n),
        .enqData_en(mem_sink.rvalid),
        .enqDataIdx(mem_sink.r.id[0 +: $clog2(RD_ROB_N_ENTRIES)]),
        .enqData(mem_sink.r),

        .deq_en(rd_rsp_valid && !rd_rsp_almostFull),
        .notEmpty(rd_rsp_valid),
        .T2_first(mem_sink_local.r),
        .T2_firstMeta({ rd_id, rd_user })
        );

    // Construct the AR sink payload, saving the ROB index as the ID field
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_sink_local.ar, =, mem_source.ar);

        mem_sink_local.ar.id = rd_next_allocIdx;
    end

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_sink.T_AR_WIDTH)
        )
      ar
       (
        .clk_in(mem_source.clk),
        .reset_n_in(mem_source.reset_n),

        .ready_in(rd_fifo_notFull),
        .valid_in(mem_source.arvalid && mem_source.arready),
        .data_in(mem_sink_local.ar),

        .clk_out(mem_sink.clk),
        .reset_n_out(mem_sink.reset_n),

        .ready_out(mem_sink.arready),
        .valid_out(mem_sink.arvalid),
        .data_out(mem_sink.ar)
        );


    // Sorted responses. The ROB's ready latency is 2 cycles. Feed responses
    // into a FIFO that will handle flow control from the source.
    always_ff @(posedge mem_source.clk)
    begin
        rd_rsp_valid_q <= rd_rsp_valid && !rd_rsp_almostFull;
        mem_source_local.rvalid <= rd_rsp_valid_q;
    end

    // Save the r.id and r.user on SOP and return them with every beat in the
    // response.
    logic rd_sop;
    always_ff @(posedge mem_source.clk)
    begin
        if (mem_source_local.rvalid)
        begin
            rd_sop <= mem_sink_local.r.last;
            if (rd_sop)
            begin
                rd_reg_id <= rd_id;
                rd_reg_user <= rd_user;
            end
        end

        if (!mem_source.reset_n)
        begin
            rd_sop <= 1'b1;
        end
    end

    // Construct a source version of read response using field widths from
    // the source instead of the sink.
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_R(mem_source_local.r, =, mem_sink_local.r);
        if (rd_sop)
        begin
            mem_source_local.r.id = rd_id;
            mem_source_local.r.user = rd_user;
        end
        else
        begin
            mem_source_local.r.id = rd_reg_id;
            mem_source_local.r.user = rd_reg_user;
        end
    end

    // Manage flow control in a read response FIFO.
    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS(mem_source.T_R_WIDTH),
        .N_ENTRIES(4),
        .THRESHOLD(2),
        .REGISTER_OUTPUT(1)
        )
      r
       (
        .clk(mem_source.clk),
        .reset_n(mem_source.reset_n),

        .enq_data(mem_source_local.r),
        .enq_en(mem_source_local.rvalid),
        .notFull(),
        .almostFull(rd_rsp_almostFull),

        .first(mem_source.r),
        .deq_en(mem_source.rready && mem_source.rvalid),
        .notEmpty(mem_source.rvalid)
        );

endmodule // ofs_plat_axi_mem_if_async_rob
