// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
    parameter NUM_WRITE_CREDITS = 128,

    // For some configurations, read responses may sometimes be shorter than
    // the bus width. The parameter defines the number of independent read
    // response segments. Extra state is added to mem_sink.r.user when
    // NUM_PAYLOAD_RCB_SEGS is greater than 1. See the logic around rd_rob
    // below for details.
    parameter NUM_PAYLOAD_RCB_SEGS = 1
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

    ofs_plat_prim_ready_enable_async
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

    ofs_plat_prim_ready_enable_async
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


    // When read responses may arrive in chunks smaller than the full data width,
    // the ROB is broken down into multiple smaller buffers. Full bus-width
    // completions are returned to the source only when all chunks have
    // arrived.

    // Completion chunks -- guaranteed to be returned as a single unit
    localparam RCB_SEG_WIDTH = mem_sink.DATA_WIDTH / NUM_PAYLOAD_RCB_SEGS;
    typedef logic [RCB_SEG_WIDTH-1 : 0] t_rcb_seg_data;
    // Full data bus, composed of one or more completion chunks
    typedef t_rcb_seg_data [NUM_PAYLOAD_RCB_SEGS-1 : 0] t_rcb_full_data;

    t_rcb_full_data rd_rsp_data;
    t_rcb_full_data rd_rsp_data_in;
    assign rd_rsp_data_in = mem_sink.r.data;
    assign mem_sink_local.r.data = rd_rsp_data;

    // The sink must encode RCB chunk details for each incoming valid cycle.
    // Details arrive in mem_sink.r.user since it is otherwise unused. Only
    // the original user field from mem_source.ar is passed to mem_source.r.

    // Segment-level valid bits
    logic [NUM_PAYLOAD_RCB_SEGS-1 : 0] rcb_seg_valid;
    // Segment-level offset bits. A read response might not start at bit 0
    // of the bus. When set, these bits indicate a segment belongs to the
    // next line.
    logic [NUM_PAYLOAD_RCB_SEGS-1 : 0] rcb_seg_offset;
    // Segment-level state from mem_sink.r.user. Force the high bit of
    // rcb_seg_offset to 0 since at least one segment must be associated
    // with the index in mem_sink.r.id.
    assign { rcb_seg_offset, rcb_seg_valid } =
        (NUM_PAYLOAD_RCB_SEGS == 1) ?
            { 1'b0, 1'b1 } :
            { 1'b0, mem_sink.r.user[0 +: 2*NUM_PAYLOAD_RCB_SEGS-1] };

    // Segment-level ROB response valid / last
    logic [NUM_PAYLOAD_RCB_SEGS-1 : 0] rd_rsp_seg_valid;
    logic [NUM_PAYLOAD_RCB_SEGS-1 : 0] rd_rsp_seg_last;
    // Response is valid when all segments are valid
    assign rd_rsp_valid = &rd_rsp_seg_valid;
    assign mem_sink_local.r.last = |rd_rsp_seg_last;

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(RD_ROB_N_ENTRIES),
        .N_DATA_BITS(RCB_SEG_WIDTH + 1),
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
        .enqData_en(mem_sink.rvalid && rcb_seg_valid[0]),
        .enqDataIdx(mem_sink.r.id[0 +: $clog2(RD_ROB_N_ENTRIES)] + rcb_seg_offset[0]),
        .enqData({ rd_rsp_data_in[0], mem_sink.r.last }),

        .deq_en(rd_rsp_valid && !rd_rsp_almostFull),
        .notEmpty(rd_rsp_seg_valid[0]),
        .T2_first({ rd_rsp_data[0], rd_rsp_seg_last[0] }),
        .T2_firstMeta({ rd_id, rd_user })
        );

    for (genvar s = 1; s < NUM_PAYLOAD_RCB_SEGS; s += 1) begin : rs
        // Other RCB segments. Timing and valid/ready will be identical to the
        // main segment, so almost now control flow is used. All metadata also
        // comes from segment 0 above.
        ofs_plat_prim_rob_maybe_dc
          #(
            .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
            .N_ENTRIES(RD_ROB_N_ENTRIES),
            .N_DATA_BITS(RCB_SEG_WIDTH + 1),
            .N_META_BITS(1),
            .MAX_ALLOC_PER_CYCLE(1 << mem_sink.BURST_CNT_WIDTH)
            )
          rd_seg_rob
           (
            .clk(mem_source.clk),
            .reset_n(mem_source.reset_n),
            .alloc_en(mem_source.arvalid && mem_source.arready),
            .allocCnt(t_rd_alloc_cnt'(mem_source.ar.len) + t_rd_alloc_cnt'(1)),
            .allocMeta(1'b0),
            .notFull(),
            .allocIdx(),
            .inSpaceAvail(),

            // Responses
            .enq_clk(mem_sink.clk),
            .enq_reset_n(mem_sink.reset_n),
            .enqData_en(mem_sink.rvalid && rcb_seg_valid[s]),
            .enqDataIdx(mem_sink.r.id[0 +: $clog2(RD_ROB_N_ENTRIES)] + rcb_seg_offset[s]),
            .enqData({ rd_rsp_data_in[s], mem_sink.r.last }),

            .deq_en(rd_rsp_valid && !rd_rsp_almostFull),
            .notEmpty(rd_rsp_seg_valid[s]),
            .T2_first({ rd_rsp_data[s], rd_rsp_seg_last[s] }),
            .T2_firstMeta()
            );
    end

    assign mem_sink_local.r.resp = '0;

    // Construct the AR sink payload, saving the ROB index as the ID field
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_sink_local.ar, =, mem_source.ar);

        mem_sink_local.ar.id = rd_next_allocIdx;
    end

    ofs_plat_prim_ready_enable_async
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
