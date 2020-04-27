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
// Clock crossing bridge for the Avalon split bus read write memory interface.
//

module ofs_plat_avalon_mem_rdwr_if_async_rob
  #(
    // When non-zero, add a clock crossing along with the ROB.
    parameter ADD_CLOCK_CROSSING = 0,

    // Sizes of the response buffers in the ROB and clock crossing.
    parameter MAX_ACTIVE_RD_LINES = 256,
    parameter MAX_ACTIVE_WR_LINES = 256
    )
   (
    // BURST_CNT_WIDTH of both mem_slave and mem_master must be 3!
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master mem_master
    );

    localparam DATA_WIDTH = mem_slave.DATA_WIDTH_;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    // Preserve user data in master requests
    localparam MASTER_USER_WIDTH = mem_master.USER_WIDTH_;
    typedef logic [MASTER_USER_WIDTH-1 : 0] t_master_user;

    // Slave user data is the ROB index space
    localparam SLAVE_USER_WIDTH = mem_slave.USER_WIDTH_;
    typedef logic [SLAVE_USER_WIDTH-1 : 0] t_slave_user;
    

    // ====================================================================
    // 
    //  Reads
    // 
    // ====================================================================

    logic rd_req_en;
    t_slave_user rd_allocIdx;
    logic rd_rob_notFull;
    logic rd_fifo_notFull;

    logic rd_readdatavalid, rd_readdatavalid_q;

    assign mem_master.rd_waitrequest = !rd_rob_notFull || !rd_fifo_notFull;
    assign rd_req_en = mem_master.rd_read && rd_rob_notFull && rd_fifo_notFull;

    //
    // Read reorder buffer. Allocate a unique index for every request.
    //

    localparam RD_ROB_N_ENTRIES = 1 << $clog2(MAX_ACTIVE_RD_LINES);
    typedef logic [$clog2(RD_ROB_N_ENTRIES)-1 : 0] t_rd_rob_idx;
    t_rd_rob_idx rd_next_allocIdx;
    assign rd_allocIdx = t_slave_user'(rd_next_allocIdx);

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(RD_ROB_N_ENTRIES),
        .N_DATA_BITS(mem_slave.RESPONSE_WIDTH + DATA_WIDTH),
        .N_META_BITS(MASTER_USER_WIDTH),
        .MAX_ALLOC_PER_CYCLE(1 << (mem_slave.BURST_CNT_WIDTH - 1))
        )
      rd_rob
       (
        .clk(mem_master.clk),
        .reset_n(mem_master.reset_n),
        .alloc_en(rd_req_en),
        .allocCnt(mem_master.rd_burstcount),
        .allocMeta(mem_master.rd_user),
        .notFull(rd_rob_notFull),
        .allocIdx(rd_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_slave.clk),
        .enq_reset_n(mem_slave.reset_n),
        .enqData_en(mem_slave.rd_readdatavalid),
        .enqDataIdx(t_rd_rob_idx'(mem_slave.rd_readresponseuser)),
        .enqData({ mem_slave.rd_response, mem_slave.rd_readdata }),

        .deq_en(rd_readdatavalid),
        .notEmpty(rd_readdatavalid),
        .T2_first({ mem_master.rd_response, mem_master.rd_readdata }),
        .T2_firstMeta(mem_master.rd_readresponseuser)
        );

    // Responses: align mem_master.rd_readdatavalid with ROB's 2 cycle latency
    always_ff @(posedge mem_master.clk)
    begin
        rd_readdatavalid_q <= rd_readdatavalid;
        mem_master.rd_readdatavalid <= rd_readdatavalid_q;
    end

    //
    // Forward requests to slave, along with the rob index.
    //

    generate
        if (ADD_CLOCK_CROSSING)
        begin : rd_cc
            // Need a clock crossing FIFO for read requests
            ofs_plat_prim_fifo_dc
              #(
                .N_DATA_BITS(SLAVE_USER_WIDTH +
                             mem_master.BURST_CNT_WIDTH +
                             mem_master.DATA_N_BYTES +
                             1 + // rd_function
                             mem_master.ADDR_WIDTH),
                .N_ENTRIES(16)
                )
             rd_req_fifo
               (
                .enq_clk(mem_master.clk),
                .enq_reset_n(mem_master.reset_n),
                .enq_data({ t_slave_user'(rd_allocIdx),
                            mem_master.rd_burstcount,
                            mem_master.rd_byteenable,
                            mem_master.rd_function,
                            mem_master.rd_address }),
                .enq_en(rd_req_en),
                .notFull(rd_fifo_notFull),
                .almostFull(),

                .deq_clk(mem_slave.clk),
                .deq_reset_n(mem_slave.reset_n),
                .first({ mem_slave.rd_user,
                         mem_slave.rd_burstcount,
                         mem_slave.rd_byteenable,
                         mem_slave.rd_function,
                         mem_slave.rd_address }),
                .deq_en(mem_slave.rd_read && !mem_slave.rd_waitrequest),
                .notEmpty(mem_slave.rd_read)
                );
        end
        else
        begin : rd_nc
            // No clock crossing. Simple two-stage FIFO.
            ofs_plat_prim_fifo2
              #(
                .N_DATA_BITS(SLAVE_USER_WIDTH +
                             mem_master.BURST_CNT_WIDTH +
                             mem_master.DATA_N_BYTES +
                             1 + // rd_function
                             mem_master.ADDR_WIDTH)
                )
             rd_req_fifo
               (
                .clk(mem_master.clk),
                .reset_n(mem_master.reset_n),

                .enq_data({ t_slave_user'(rd_allocIdx),
                            mem_master.rd_burstcount,
                            mem_master.rd_byteenable,
                            mem_master.rd_function,
                            mem_master.rd_address }),
                .enq_en(rd_req_en),
                .notFull(rd_fifo_notFull),

                .first({ mem_slave.rd_user,
                         mem_slave.rd_burstcount,
                         mem_slave.rd_byteenable,
                         mem_slave.rd_function,
                         mem_slave.rd_address }),
                .deq_en(mem_slave.rd_read && !mem_slave.rd_waitrequest),
                .notEmpty(mem_slave.rd_read)
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

    logic wr_writeresponsevalid, wr_writeresponsevalid_q;

    assign mem_master.wr_waitrequest = !wr_rob_notFull || !wr_fifo_notFull;
    assign wr_req_en = mem_master.wr_write && wr_rob_notFull && wr_fifo_notFull;

    //
    // Track write SOP. ROB slots are needed only on start of packet.
    //
    logic wr_sop;

    ofs_plat_prim_burstcount1_sop_tracker
      #(
        .BURST_CNT_WIDTH(mem_master.BURST_CNT_WIDTH)
        )
      sop
       (
        .clk(mem_master.clk),
        .reset_n(mem_master.reset_n),
        .flit_valid(wr_req_en),
        .burstcount(mem_master.wr_burstcount),
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

    ofs_plat_prim_rob_maybe_dc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .N_ENTRIES(WR_ROB_N_ENTRIES),
        .N_DATA_BITS(mem_slave.RESPONSE_WIDTH),
        .N_META_BITS(MASTER_USER_WIDTH),
        .MAX_ALLOC_PER_CYCLE(1)
        )
      wr_rob
       (
        .clk(mem_master.clk),
        .reset_n(mem_master.reset_n),
        .alloc_en(wr_req_en && wr_sop),
        .allocCnt(1'b1),
        .allocMeta(mem_master.wr_user),
        .notFull(wr_rob_notFull),
        .allocIdx(wr_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_slave.clk),
        .enq_reset_n(mem_slave.reset_n),
        .enqData_en(mem_slave.wr_writeresponsevalid),
        .enqDataIdx(t_wr_rob_idx'(mem_slave.wr_writeresponseuser)),
        .enqData(mem_slave.wr_response),

        .deq_en(wr_writeresponsevalid),
        .notEmpty(wr_writeresponsevalid),
        .T2_first(mem_master.wr_response),
        .T2_firstMeta(mem_master.wr_writeresponseuser)
        );

    // Responses: align mem_master.wr_writeresponsevalid with ROB's 2 cycle latency
    always_ff @(posedge mem_master.clk)
    begin
        wr_writeresponsevalid_q <= wr_writeresponsevalid;
        mem_master.wr_writeresponsevalid <= wr_writeresponsevalid_q;
    end

    //
    // Forward requests to slave, along with the rob index.
    //

    // Hold ROB wr_allocIdx for the full packet
    t_slave_user wr_allocIdx, wr_packet_allocIdx;
    assign wr_allocIdx = (wr_sop ? t_slave_user'(wr_next_allocIdx) : wr_packet_allocIdx);

    always_ff @(posedge mem_master.clk)
    begin
        if (wr_sop)
        begin
            wr_packet_allocIdx <= t_slave_user'(wr_next_allocIdx);
        end
    end

    generate
        if (ADD_CLOCK_CROSSING)
        begin : wr_cc
            // Need a clock crossing FIFO for write requests
            ofs_plat_prim_fifo_dc
              #(
                .N_DATA_BITS(SLAVE_USER_WIDTH +
                             mem_master.BURST_CNT_WIDTH +
                             mem_master.DATA_WIDTH +
                             mem_master.DATA_N_BYTES +
                             1 + // wr_function
                             mem_master.ADDR_WIDTH),
                .N_ENTRIES(16)
                )
             wr_req_fifo
               (
                .enq_clk(mem_master.clk),
                .enq_reset_n(mem_master.reset_n),
                .enq_data({ t_slave_user'(wr_allocIdx),
                            mem_master.wr_burstcount,
                            mem_master.wr_writedata,
                            mem_master.wr_byteenable,
                            mem_master.wr_function,
                            mem_master.wr_address }),
                .enq_en(wr_req_en),
                .notFull(wr_fifo_notFull),
                .almostFull(),

                .deq_clk(mem_slave.clk),
                .deq_reset_n(mem_slave.reset_n),
                .first({ mem_slave.wr_user,
                         mem_slave.wr_burstcount,
                         mem_slave.wr_writedata,
                         mem_slave.wr_byteenable,
                         mem_slave.wr_function,
                         mem_slave.wr_address }),
                .deq_en(mem_slave.wr_write && !mem_slave.wr_waitrequest),
                .notEmpty(mem_slave.wr_write)
                );
        end
        else
        begin : wr_nc
            // No clock crossing. Simple two-stage FIFO.
            ofs_plat_prim_fifo2
              #(
                .N_DATA_BITS(SLAVE_USER_WIDTH +
                             mem_master.BURST_CNT_WIDTH +
                             mem_master.DATA_WIDTH +
                             mem_master.DATA_N_BYTES +
                             1 + // wr_function
                             mem_master.ADDR_WIDTH)
                )
             wr_req_fifo
               (
                .clk(mem_master.clk),
                .reset_n(mem_master.reset_n),

                .enq_data({ t_slave_user'(wr_allocIdx),
                            mem_master.wr_burstcount,
                            mem_master.wr_writedata,
                            mem_master.wr_byteenable,
                            mem_master.wr_function,
                            mem_master.wr_address }),
                .enq_en(wr_req_en),
                .notFull(wr_fifo_notFull),

                .first({ mem_slave.wr_user,
                         mem_slave.wr_burstcount,
                         mem_slave.wr_writedata,
                         mem_slave.wr_byteenable,
                         mem_slave.wr_function,
                         mem_slave.wr_address }),
                .deq_en(mem_slave.wr_write && !mem_slave.wr_waitrequest),
                .notEmpty(mem_slave.wr_write)
                );
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_async_rob
