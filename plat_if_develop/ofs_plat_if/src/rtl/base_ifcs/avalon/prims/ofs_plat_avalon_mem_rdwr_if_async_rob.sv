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
// Combined crossing bridge and reorder buffer (ROB) for the Avalon split bus read
// write memory interface. The ROB stores tags for sorting in the sink's
// user fields and assumes that the sink preserves them. This module is needed
// only for unusual sinks that return responses out of order.
//

module ofs_plat_avalon_mem_rdwr_if_async_rob
  #(
    // When non-zero, add a clock crossing along with the ROB.
    parameter ADD_CLOCK_CROSSING = 0,

    // Sizes of the response buffers in the ROB and clock crossing.
    parameter MAX_ACTIVE_RD_LINES = 256,
    parameter MAX_ACTIVE_WR_LINES = 256,

    // First bit in the sink's user fields where the ROB indices should be
    // stored.
    parameter USER_ROB_IDX_START = 0,

    // When non-zero, the write channel is blocked when the read channel runs
    // out of credits. On some channels, such as PCIe TLP, blocking writes along
    // with reads solves a fairness problem caused by writes not having either
    // tags or completions.
    parameter BLOCK_WRITE_WITH_READ = 0
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source
    );

    localparam DATA_WIDTH = mem_sink.DATA_WIDTH_;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    // Preserve user data in source requests
    localparam SOURCE_USER_WIDTH = mem_source.USER_WIDTH_;
    typedef logic [SOURCE_USER_WIDTH-1 : 0] t_source_user;

    // Sink user data is the ROB index space
    localparam SINK_USER_WIDTH = mem_sink.USER_WIDTH_;
    typedef logic [SINK_USER_WIDTH-1 : 0] t_sink_user;
    

    // ====================================================================
    // 
    //  Reads
    // 
    // ====================================================================

    logic rd_req_en;
    t_sink_user rd_allocIdx;
    logic rd_rob_notFull_cur, rd_rob_notFull;
    logic rd_fifo_notFull;

    // Debounce rd_rob_notFull by disallowing back-to-back notFull after
    // a transition from full to notFull. Because the ROB maintains multiple
    // slots per request for multi-line reads, there is some pipelining in the
    // notFull calculation. Making it more regular helps with the read/write
    // synchronization when BLOCK_WRITE_WITH_READ is set.
    logic rd_rob_wasFull, rd_rob_notFull_q;
    assign rd_rob_notFull = rd_rob_notFull_cur && !rd_rob_wasFull;

    always_ff @(posedge mem_source.clk)
    begin
        rd_rob_notFull_q <= rd_rob_notFull_cur;
        rd_rob_wasFull <= !rd_rob_notFull_q && rd_rob_notFull_cur;
    end

    logic rd_readdatavalid, rd_readdatavalid_q;

    assign mem_source.rd_waitrequest = !rd_rob_notFull || !rd_fifo_notFull;
    assign rd_req_en = mem_source.rd_read && rd_rob_notFull && rd_fifo_notFull;

    //
    // Read reorder buffer. Allocate a unique index for every request.
    //

    localparam RD_ROB_N_ENTRIES = 1 << $clog2(MAX_ACTIVE_RD_LINES);
    typedef logic [$clog2(RD_ROB_N_ENTRIES)-1 : 0] t_rd_rob_idx;
    t_rd_rob_idx rd_next_allocIdx;
    assign rd_allocIdx = t_sink_user'(rd_next_allocIdx);
    logic rd_rsp_is_sop;
    t_source_user rd_readresponseuser, rd_readresponseuser_sop;

    // Limit allocation in the ROB to MAX_ACTIVE_RD_LINES. Using less space
    // may seem counterintuitive, but MAX_ACTIVE_RD_LINES is already enough
    // for full throughput. Allowing more just increases latency.
    localparam RD_ROB_MAX_ALLOC_PER_CYCLE = 1 << (mem_sink.BURST_CNT_WIDTH - 1);
    localparam RD_ROB_EXCESS_SLOTS = RD_ROB_N_ENTRIES - MAX_ACTIVE_RD_LINES;
    localparam RD_ROB_MIN_FREE_SLOTS = (RD_ROB_EXCESS_SLOTS > RD_ROB_MAX_ALLOC_PER_CYCLE) ?
                                       RD_ROB_EXCESS_SLOTS : RD_ROB_MAX_ALLOC_PER_CYCLE;

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(RD_ROB_N_ENTRIES),
        .N_DATA_BITS(1 + mem_sink.RESPONSE_WIDTH + DATA_WIDTH),
        .N_META_BITS(SOURCE_USER_WIDTH),
        .MAX_ALLOC_PER_CYCLE(RD_ROB_MAX_ALLOC_PER_CYCLE),
        .MIN_FREE_SLOTS(RD_ROB_MIN_FREE_SLOTS)
        )
      rd_rob
       (
        .clk(mem_source.clk),
        .reset_n(mem_source.reset_n),
        .alloc_en(rd_req_en),
        .allocCnt(mem_source.rd_burstcount),
        .allocMeta(mem_source.rd_user),
        .notFull(rd_rob_notFull_cur),
        .allocIdx(rd_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_sink.clk),
        .enq_reset_n(mem_sink.reset_n),
        .enqData_en(mem_sink.rd_readdatavalid),
        .enqDataIdx(mem_sink.rd_readresponseuser[USER_ROB_IDX_START +: $clog2(RD_ROB_N_ENTRIES)]),
        // High bit of data is set only on SOP of the response group.
        // The sink is expected to set the NO_REPLY flag on non-SOP.
        .enqData({ ~mem_sink.rd_readresponseuser[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_NO_REPLY],
                   mem_sink.rd_response,
                   mem_sink.rd_readdata }),

        .deq_en(rd_readdatavalid),
        .notEmpty(rd_readdatavalid),
        .T2_first({ rd_rsp_is_sop, mem_source.rd_response, mem_source.rd_readdata }),
        .T2_firstMeta(rd_readresponseuser)
        );

    // Responses: align mem_source.rd_readdatavalid with ROB's 2 cycle latency
    always_ff @(posedge mem_source.clk)
    begin
        rd_readdatavalid_q <= rd_readdatavalid;
        mem_source.rd_readdatavalid <= rd_readdatavalid_q;
    end

    // Hold rd_readresponseuser from the SOP beat
    assign mem_source.rd_readresponseuser = rd_rsp_is_sop ? rd_readresponseuser :
                                                            rd_readresponseuser_sop;
    always_ff @(posedge mem_source.clk)
    begin
        if (mem_source.rd_readdatavalid && rd_rsp_is_sop)
        begin
            rd_readresponseuser_sop <= rd_readresponseuser;
        end
    end

    //
    // Forward requests to sink, along with the rob index.
    //

    t_sink_user sink_rd_user;
    always_comb
    begin
        sink_rd_user = t_sink_user'(mem_source.rd_user);
        sink_rd_user[USER_ROB_IDX_START +: $clog2(RD_ROB_N_ENTRIES)] = rd_allocIdx;
    end

    generate
        if (ADD_CLOCK_CROSSING)
        begin : rd_cc
            // Need a clock crossing FIFO for read requests
            ofs_plat_prim_fifo_dc
              #(
                .N_DATA_BITS(SINK_USER_WIDTH +
                             mem_source.BURST_CNT_WIDTH +
                             mem_source.DATA_N_BYTES +
                             mem_source.ADDR_WIDTH),
                .N_ENTRIES(16)
                )
             rd_req_fifo
               (
                .enq_clk(mem_source.clk),
                .enq_reset_n(mem_source.reset_n),
                .enq_data({ sink_rd_user,
                            mem_source.rd_burstcount,
                            mem_source.rd_byteenable,
                            mem_source.rd_address }),
                .enq_en(rd_req_en),
                .notFull(rd_fifo_notFull),
                .almostFull(),

                .deq_clk(mem_sink.clk),
                .deq_reset_n(mem_sink.reset_n),
                .first({ mem_sink.rd_user,
                         mem_sink.rd_burstcount,
                         mem_sink.rd_byteenable,
                         mem_sink.rd_address }),
                .deq_en(mem_sink.rd_read && !mem_sink.rd_waitrequest),
                .notEmpty(mem_sink.rd_read)
                );
        end
        else
        begin : rd_nc
            // No clock crossing. Simple two-stage FIFO.
            ofs_plat_prim_fifo2
              #(
                .N_DATA_BITS(SINK_USER_WIDTH +
                             mem_source.BURST_CNT_WIDTH +
                             mem_source.DATA_N_BYTES +
                             mem_source.ADDR_WIDTH)
                )
             rd_req_fifo
               (
                .clk(mem_source.clk),
                .reset_n(mem_source.reset_n),

                .enq_data({ sink_rd_user,
                            mem_source.rd_burstcount,
                            mem_source.rd_byteenable,
                            mem_source.rd_address }),
                .enq_en(rd_req_en),
                .notFull(rd_fifo_notFull),

                .first({ mem_sink.rd_user,
                         mem_sink.rd_burstcount,
                         mem_sink.rd_byteenable,
                         mem_sink.rd_address }),
                .deq_en(mem_sink.rd_read && !mem_sink.rd_waitrequest),
                .notEmpty(mem_sink.rd_read)
                );
        end
    endgenerate
    

    // ====================================================================
    // 
    //  Writes
    // 
    // ====================================================================

    logic wr_req_en;
    logic wr_rob_notFull;
    logic wr_fifo_notFull;
    logic wr_sop;

    logic wr_writeresponsevalid, wr_writeresponsevalid_q;

    assign mem_source.wr_waitrequest =
        !wr_rob_notFull || !wr_fifo_notFull ||
        ((BLOCK_WRITE_WITH_READ != 0) ? (!rd_rob_notFull && wr_sop) : 1'b0);
    assign wr_req_en = mem_source.wr_write && !mem_source.wr_waitrequest;

    //
    // Track write SOP. ROB slots are needed only on start of packet.
    //
    ofs_plat_prim_burstcount1_sop_tracker
      #(
        .BURST_CNT_WIDTH(mem_source.BURST_CNT_WIDTH)
        )
      sop
       (
        .clk(mem_source.clk),
        .reset_n(mem_source.reset_n),
        .flit_valid(wr_req_en),
        .burstcount(mem_source.wr_burstcount),
        .sop(wr_sop),
        .eop()
        );

    //
    // Write reorder buffer. Allocate a unique index for every request.
    //

    // Guarantee N_ENTRIES is a power of 2
    localparam WR_ROB_N_ENTRIES = 1 << $clog2(MAX_ACTIVE_WR_LINES);
    typedef logic [$clog2(WR_ROB_N_ENTRIES)-1 : 0] t_wr_rob_idx;
    t_wr_rob_idx wr_next_allocIdx;

    // Limit allocation in the ROB to MAX_ACTIVE_WR_LINES.
    localparam WR_ROB_MAX_ALLOC_PER_CYCLE = 1;
    localparam WR_ROB_EXCESS_SLOTS = WR_ROB_N_ENTRIES - MAX_ACTIVE_WR_LINES;
    localparam WR_ROB_MIN_FREE_SLOTS = (WR_ROB_EXCESS_SLOTS > WR_ROB_MAX_ALLOC_PER_CYCLE) ?
                                       WR_ROB_EXCESS_SLOTS : WR_ROB_MAX_ALLOC_PER_CYCLE;

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(WR_ROB_N_ENTRIES),
        .N_DATA_BITS(mem_sink.RESPONSE_WIDTH),
        .N_META_BITS(SOURCE_USER_WIDTH),
        .MAX_ALLOC_PER_CYCLE(WR_ROB_MAX_ALLOC_PER_CYCLE),
        .MIN_FREE_SLOTS(WR_ROB_MIN_FREE_SLOTS)
        )
      wr_rob
       (
        .clk(mem_source.clk),
        .reset_n(mem_source.reset_n),
        .alloc_en(wr_req_en && wr_sop),
        .allocCnt(1'b1),
        .allocMeta(mem_source.wr_user),
        .notFull(wr_rob_notFull),
        .allocIdx(wr_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_sink.clk),
        .enq_reset_n(mem_sink.reset_n),
        .enqData_en(mem_sink.wr_writeresponsevalid),
        .enqDataIdx(mem_sink.wr_writeresponseuser[USER_ROB_IDX_START +: $clog2(WR_ROB_N_ENTRIES)]),
        .enqData(mem_sink.wr_response),

        .deq_en(wr_writeresponsevalid),
        .notEmpty(wr_writeresponsevalid),
        .T2_first(mem_source.wr_response),
        .T2_firstMeta(mem_source.wr_writeresponseuser)
        );

    // Responses: align mem_source.wr_writeresponsevalid with ROB's 2 cycle latency
    always_ff @(posedge mem_source.clk)
    begin
        wr_writeresponsevalid_q <= wr_writeresponsevalid;
        mem_source.wr_writeresponsevalid <= wr_writeresponsevalid_q;
    end

    //
    // Forward requests to sink, along with the rob index.
    //

    // Hold ROB wr_allocIdx for the full packet
    t_sink_user wr_allocIdx, wr_packet_allocIdx;
    assign wr_allocIdx = (wr_sop ? t_sink_user'(wr_next_allocIdx) : wr_packet_allocIdx);

    always_ff @(posedge mem_source.clk)
    begin
        if (wr_sop)
        begin
            wr_packet_allocIdx <= t_sink_user'(wr_next_allocIdx);
        end
    end

    t_sink_user sink_wr_user;
    always_comb
    begin
        sink_wr_user = t_sink_user'(mem_source.wr_user);
        sink_wr_user[USER_ROB_IDX_START +: $clog2(WR_ROB_N_ENTRIES)] = wr_allocIdx;
    end

    generate
        if (ADD_CLOCK_CROSSING)
        begin : wr_cc
            // Need a clock crossing FIFO for write requests
            ofs_plat_prim_fifo_dc
              #(
                .N_DATA_BITS(SINK_USER_WIDTH +
                             mem_source.BURST_CNT_WIDTH +
                             mem_source.DATA_WIDTH +
                             mem_source.DATA_N_BYTES +
                             mem_source.ADDR_WIDTH),
                .N_ENTRIES(16)
                )
             wr_req_fifo
               (
                .enq_clk(mem_source.clk),
                .enq_reset_n(mem_source.reset_n),
                .enq_data({ sink_wr_user,
                            mem_source.wr_burstcount,
                            mem_source.wr_writedata,
                            mem_source.wr_byteenable,
                            mem_source.wr_address }),
                .enq_en(wr_req_en),
                .notFull(wr_fifo_notFull),
                .almostFull(),

                .deq_clk(mem_sink.clk),
                .deq_reset_n(mem_sink.reset_n),
                .first({ mem_sink.wr_user,
                         mem_sink.wr_burstcount,
                         mem_sink.wr_writedata,
                         mem_sink.wr_byteenable,
                         mem_sink.wr_address }),
                .deq_en(mem_sink.wr_write && !mem_sink.wr_waitrequest),
                .notEmpty(mem_sink.wr_write)
                );
        end
        else
        begin : wr_nc
            // No clock crossing. Simple two-stage FIFO.
            ofs_plat_prim_fifo2
              #(
                .N_DATA_BITS(SINK_USER_WIDTH +
                             mem_source.BURST_CNT_WIDTH +
                             mem_source.DATA_WIDTH +
                             mem_source.DATA_N_BYTES +
                             mem_source.ADDR_WIDTH)
                )
             wr_req_fifo
               (
                .clk(mem_source.clk),
                .reset_n(mem_source.reset_n),

                .enq_data({ sink_wr_user,
                            mem_source.wr_burstcount,
                            mem_source.wr_writedata,
                            mem_source.wr_byteenable,
                            mem_source.wr_address }),
                .enq_en(wr_req_en),
                .notFull(wr_fifo_notFull),

                .first({ mem_sink.wr_user,
                         mem_sink.wr_burstcount,
                         mem_sink.wr_writedata,
                         mem_sink.wr_byteenable,
                         mem_sink.wr_address }),
                .deq_en(mem_sink.wr_write && !mem_sink.wr_waitrequest),
                .notEmpty(mem_sink.wr_write)
                );
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_async_rob
