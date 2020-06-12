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
// the master). The shim ofs_plat_axi_mem_if_rsp_credits() can be used for that
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

    // If the master guarantees to reserve space for all responses then the
    // ready signals on slave responses pipelines can be ignored, perhaps
    // improving timing.
    parameter SLAVE_RESPONSES_ALWAYS_READY = 0,

    parameter NUM_READ_CREDITS = 256,
    parameter NUM_WRITE_CREDITS = 128,

    // First bit in the slave's user fields where the ROB indices should be
    // stored.
    parameter USER_ROB_IDX_START = 0
    )
   (
    ofs_plat_axi_mem_if.to_slave mem_slave,
    ofs_plat_axi_mem_if.to_master mem_master
    );

    //
    // Copies of the slave and master interfaces that can be used for
    // internal, intermediate states using the sized data structures.
    //

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_slave),
        .DISABLE_CHECKER(1)
        )
      mem_slave_local();

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_master),
        .DISABLE_CHECKER(1)
        )
      mem_master_local();


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
    assign mem_master.awready = wr_rob_notFull & wr_fifo_notFull;
    // ROB reserves enough space for all outstanding responses
    assign mem_slave.bready = 1'b1;

    // Guarantee N_ENTRIES is a power of 2
    localparam WR_ROB_N_ENTRIES = 1 << $clog2(NUM_WRITE_CREDITS);
    typedef logic [$clog2(WR_ROB_N_ENTRIES)-1 : 0] t_wr_rob_idx;
    t_wr_rob_idx wr_next_allocIdx;

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(WR_ROB_N_ENTRIES),
        .N_DATA_BITS($bits(ofs_plat_axi_mem_pkg::t_axi_resp)),
        .N_META_BITS(mem_master.WID_WIDTH + mem_master.USER_WIDTH),
        .MAX_ALLOC_PER_CYCLE(1)
        )
      wr_rob
       (
        .clk(mem_master.clk),
        .reset_n(mem_master.reset_n),
        .alloc_en(mem_master.awvalid && mem_master.awready),
        .allocCnt(1'b1),
        .allocMeta({ mem_master.aw.id, mem_master.aw.user }),
        .notFull(wr_rob_notFull),
        .allocIdx(wr_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_slave.clk),
        .enq_reset_n(mem_slave.reset_n),
        .enqData_en(mem_slave.bvalid),
        .enqDataIdx(mem_slave.b.user[USER_ROB_IDX_START +: $clog2(WR_ROB_N_ENTRIES)]),
        .enqData(mem_slave.b.resp),

        .deq_en(wr_rsp_valid && !wr_rsp_almostFull),
        .notEmpty(wr_rsp_valid),
        .T2_first(mem_master_local.b.resp),
        .T2_firstMeta({ mem_master_local.b.id, mem_master_local.b.user })
        );

    // Construct the AW slave payload, saving the ROB index as the user field
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_slave_local.aw, =, mem_master.aw);

        mem_slave_local.aw.user[USER_ROB_IDX_START +: $clog2(WR_ROB_N_ENTRIES)] =
            wr_next_allocIdx;
    end

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_slave.T_AW_WIDTH)
        )
      aw
       (
        .clk_in(mem_master.clk),
        .reset_n_in(mem_master.reset_n),

        .ready_in(wr_fifo_notFull),
        .valid_in(mem_master.awvalid && mem_master.awready),
        .data_in(mem_slave_local.aw),

        .clk_out(mem_slave.clk),
        .reset_n_out(mem_slave.reset_n),

        .ready_out(mem_slave.awready),
        .valid_out(mem_slave.awvalid),
        .data_out(mem_slave.aw)
        );

    // Write data is just a clock crossing, independent of the AW control. Fields
    // still have to mapped, though, due to size changes.
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_slave_local.w, =, mem_master.w);
    end

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_slave.T_W_WIDTH)
        )
      w
       (
        .clk_in(mem_master.clk),
        .reset_n_in(mem_master.reset_n),

        .ready_in(mem_master.wready),
        .valid_in(mem_master.wvalid),
        .data_in(mem_slave_local.w),

        .clk_out(mem_slave.clk),
        .reset_n_out(mem_slave.reset_n),

        .ready_out(mem_slave.wready),
        .valid_out(mem_slave.wvalid),
        .data_out(mem_slave.w)
        );


    // Sorted responses. The ROB's ready latency is 2 cycles. Feed responses
    // into a FIFO that will handle flow control from the master.
    always_ff @(posedge mem_master.clk)
    begin
        wr_rsp_valid_q <= wr_rsp_valid && !wr_rsp_almostFull;
        mem_master_local.bvalid <= wr_rsp_valid_q;
    end

    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS(mem_master.T_B_WIDTH),
        .N_ENTRIES(4),
        .THRESHOLD(2),
        .REGISTER_OUTPUT(1)
        )
      b
       (
        .clk(mem_master.clk),
        .reset_n(mem_master.reset_n),

        .enq_data(mem_master_local.b),
        .enq_en(mem_master_local.bvalid),
        .notFull(),
        .almostFull(wr_rsp_almostFull),

        .first(mem_master.b),
        .deq_en(mem_master.bready && mem_master.bvalid),
        .notEmpty(mem_master.bvalid)
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
    assign mem_master.arready = rd_rob_notFull & rd_fifo_notFull;
    // ROB reserves enough space for all outstanding responses
    assign mem_slave.rready = 1'b1;

    localparam RD_ROB_N_ENTRIES = 1 << $clog2(NUM_READ_CREDITS);
    typedef logic [$clog2(RD_ROB_N_ENTRIES)-1 : 0] t_rd_rob_idx;
    t_rd_rob_idx rd_next_allocIdx;

    typedef logic [mem_slave.BURST_CNT_WIDTH : 0] t_rd_alloc_cnt;

    typedef logic [mem_master.RID_WIDTH-1 : 0] t_master_rid;
    typedef logic [mem_master.USER_WIDTH-1 : 0] t_master_user;
    t_master_rid rd_id, rd_reg_id;
    t_master_user rd_user, rd_reg_user;

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(RD_ROB_N_ENTRIES),
        .N_DATA_BITS(mem_slave.T_R_WIDTH),
        .N_META_BITS(mem_master.RID_WIDTH + mem_master.USER_WIDTH),
        .MAX_ALLOC_PER_CYCLE(1 << mem_slave.BURST_CNT_WIDTH)
        )
      rd_rob
       (
        .clk(mem_master.clk),
        .reset_n(mem_master.reset_n),
        .alloc_en(mem_master.arvalid && mem_master.arready),
        .allocCnt(t_rd_alloc_cnt'(mem_master.ar.len) + t_rd_alloc_cnt'(1)),
        .allocMeta({ mem_master.ar.id, mem_master.ar.user }),
        .notFull(rd_rob_notFull),
        .allocIdx(rd_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_slave.clk),
        .enq_reset_n(mem_slave.reset_n),
        .enqData_en(mem_slave.rvalid),
        .enqDataIdx(mem_slave.r.user[USER_ROB_IDX_START +: $clog2(RD_ROB_N_ENTRIES)]),
        .enqData(mem_slave.r),

        .deq_en(rd_rsp_valid && !rd_rsp_almostFull),
        .notEmpty(rd_rsp_valid),
        .T2_first(mem_slave_local.r),
        .T2_firstMeta({ rd_id, rd_user })
        );

    // Construct the AR slave payload, saving the ROB index as the user field
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_slave_local.ar, =, mem_master.ar);

        mem_slave_local.ar.user[USER_ROB_IDX_START +: $clog2(RD_ROB_N_ENTRIES)] =
            rd_next_allocIdx;
    end

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_slave.T_AR_WIDTH)
        )
      ar
       (
        .clk_in(mem_master.clk),
        .reset_n_in(mem_master.reset_n),

        .ready_in(rd_fifo_notFull),
        .valid_in(mem_master.arvalid && mem_master.arready),
        .data_in(mem_slave_local.ar),

        .clk_out(mem_slave.clk),
        .reset_n_out(mem_slave.reset_n),

        .ready_out(mem_slave.arready),
        .valid_out(mem_slave.arvalid),
        .data_out(mem_slave.ar)
        );


    // Sorted responses. The ROB's ready latency is 2 cycles. Feed responses
    // into a FIFO that will handle flow control from the master.
    always_ff @(posedge mem_master.clk)
    begin
        rd_rsp_valid_q <= rd_rsp_valid && !rd_rsp_almostFull;
        mem_master_local.rvalid <= rd_rsp_valid_q;
    end

    // Save the r.id and r.user on SOP and return them with every beat in the
    // response.
    logic rd_sop;
    always_ff @(posedge mem_master.clk)
    begin
        if (mem_master_local.rvalid)
        begin
            rd_sop <= mem_slave_local.r.last;
            if (rd_sop)
            begin
                rd_reg_id <= rd_id;
                rd_reg_user <= rd_user;
            end
        end

        if (!mem_master.reset_n)
        begin
            rd_sop <= 1'b1;
        end
    end

    // Construct a master version of read response using field widths from
    // the master instead of the slave.
    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_COPY_R(mem_master_local.r, =, mem_slave_local.r);
        if (rd_sop)
        begin
            mem_master_local.r.id = rd_id;
            mem_master_local.r.user = rd_user;
        end
        else
        begin
            mem_master_local.r.id = rd_reg_id;
            mem_master_local.r.user = rd_reg_user;
        end
    end

    // Manage flow control in a read response FIFO.
    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS(mem_master.T_R_WIDTH),
        .N_ENTRIES(4),
        .THRESHOLD(2),
        .REGISTER_OUTPUT(1)
        )
      r
       (
        .clk(mem_master.clk),
        .reset_n(mem_master.reset_n),

        .enq_data(mem_master_local.r),
        .enq_en(mem_master_local.rvalid),
        .notFull(),
        .almostFull(rd_rsp_almostFull),

        .first(mem_master.r),
        .deq_en(mem_master.rready && mem_master.rvalid),
        .notEmpty(mem_master.rvalid)
        );

endmodule // ofs_plat_axi_mem_if_async_rob
