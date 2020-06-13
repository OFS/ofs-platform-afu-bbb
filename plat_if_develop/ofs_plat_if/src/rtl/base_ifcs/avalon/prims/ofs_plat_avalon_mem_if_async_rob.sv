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
// Combined crossing bridge and reorder buffer (ROB) for the Avalon
//  memory interface. The ROB stores tags for sorting in the slave's
// user fields and assumes that the slave preserves them. This module is
// needed only for unusual slaves that return responses out of order.
//

module ofs_plat_avalon_mem_if_async_rob
  #(
    // When non-zero, add a clock crossing along with the ROB.
    parameter ADD_CLOCK_CROSSING = 0,

    // Sizes of the response buffers in the ROB and clock crossing.
    parameter MAX_ACTIVE_RD_LINES = 256,
    parameter MAX_ACTIVE_WR_LINES = 256,

    // First bit in the slave's user fields where the ROB indices should be
    // stored.
    parameter USER_ROB_IDX_START = 0
    )
   (
    // BURST_CNT_WIDTH of both mem_slave and mem_master must be 3!
    ofs_plat_avalon_mem_if.to_slave mem_slave,
    ofs_plat_avalon_mem_if.to_master mem_master
    );

    localparam DATA_WIDTH = mem_slave.DATA_WIDTH_;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    // Preserve user data in master requests
    localparam MASTER_USER_WIDTH = mem_master.USER_WIDTH_;
    typedef logic [MASTER_USER_WIDTH-1 : 0] t_master_user;

    // Slave user data is the ROB index space
    localparam SLAVE_USER_WIDTH = mem_slave.USER_WIDTH_;
    typedef logic [SLAVE_USER_WIDTH-1 : 0] t_slave_user;

    //
    // Pick a number of active lines that can actually be encoded
    // in the user field.
    //
    function automatic int validNumActive(int active_lines);
        // Largest counter that can be encoded in the user field
        int max_lines = 1 << SLAVE_USER_WIDTH;

        if (active_lines <= max_lines)
            return active_lines;

        return max_lines;
    endfunction // validNumActive


    // ====================================================================
    // 
    //  Reads and writes have separate ROBs but a single command queue.
    // 
    // ====================================================================

    // ====================================================================
    // 
    //  Reads
    // 
    // ====================================================================

    logic rd_req_en;
    t_slave_user rd_allocIdx;
    logic rd_rob_notFull;

    logic readdatavalid, readdatavalid_q;

    assign rd_req_en = mem_master.read && !mem_master.waitrequest;

    //
    // Read reorder buffer. Allocate a unique index for every request.
    //

    localparam RD_ROB_N_ENTRIES = 1 << $clog2(validNumActive(MAX_ACTIVE_RD_LINES));
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
        .allocCnt(mem_master.burstcount),
        .allocMeta(mem_master.user),
        .notFull(rd_rob_notFull),
        .allocIdx(rd_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_slave.clk),
        .enq_reset_n(mem_slave.reset_n),
        .enqData_en(mem_slave.readdatavalid),
        .enqDataIdx(mem_slave.readresponseuser[USER_ROB_IDX_START +: $clog2(RD_ROB_N_ENTRIES)]),
        .enqData({ mem_slave.response, mem_slave.readdata }),

        .deq_en(readdatavalid),
        .notEmpty(readdatavalid),
        .T2_first({ mem_master.response, mem_master.readdata }),
        .T2_firstMeta(mem_master.readresponseuser)
        );

    // Responses: align mem_master.readdatavalid with ROB's 2 cycle latency
    always_ff @(posedge mem_master.clk)
    begin
        readdatavalid_q <= readdatavalid;
        mem_master.readdatavalid <= readdatavalid_q;
    end
    

    // ====================================================================
    // 
    //  Writes
    // 
    // ====================================================================

    logic wr_req_en;
    logic wr_rob_notFull;
    logic wr_fifo_notFull;

    logic writeresponsevalid, writeresponsevalid_q;

    assign wr_req_en = mem_master.write && !mem_master.waitrequest;

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
        .burstcount(mem_master.burstcount),
        .sop(wr_sop),
        .eop()
        );

    //
    // Write reorder buffer. Allocate a unique index for every request.
    //

    // Guarantee N_ENTRIES is a power of 2
    localparam WR_ROB_N_ENTRIES = 1 << $clog2(validNumActive(MAX_ACTIVE_WR_LINES));
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
        .allocMeta(mem_master.user),
        .notFull(wr_rob_notFull),
        .allocIdx(wr_next_allocIdx),
        .inSpaceAvail(),

        // Responses
        .enq_clk(mem_slave.clk),
        .enq_reset_n(mem_slave.reset_n),
        .enqData_en(mem_slave.writeresponsevalid),
        .enqDataIdx(mem_slave.writeresponseuser[USER_ROB_IDX_START +: $clog2(WR_ROB_N_ENTRIES)]),
        .enqData(mem_slave.writeresponse),

        .deq_en(writeresponsevalid),
        .notEmpty(writeresponsevalid),
        .T2_first(mem_master.writeresponse),
        .T2_firstMeta(mem_master.writeresponseuser)
        );

    // Responses: align mem_master.writeresponsevalid with ROB's 2 cycle latency
    always_ff @(posedge mem_master.clk)
    begin
        writeresponsevalid_q <= writeresponsevalid;
        mem_master.writeresponsevalid <= writeresponsevalid_q;
    end

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


    // ====================================================================
    // 
    //  Commands
    // 
    // ====================================================================

    logic cmd_is_write;
    logic cmd_fifo_notFull, cmd_fifo_notEmpty;
    assign mem_master.waitrequest = !rd_rob_notFull || !wr_rob_notFull || !cmd_fifo_notFull;

    logic cmd_enq_en;
    assign cmd_enq_en = (mem_master.read || mem_master.write) && !mem_master.waitrequest;

    assign mem_slave.read = !cmd_is_write && cmd_fifo_notEmpty;
    assign mem_slave.write = cmd_is_write && cmd_fifo_notEmpty;

    t_slave_user slave_user;
    always_comb
    begin
        slave_user = t_slave_user'(mem_master.user);
        if (mem_master.read)
            slave_user[USER_ROB_IDX_START +: $clog2(RD_ROB_N_ENTRIES)] = rd_allocIdx;
        else
            slave_user[USER_ROB_IDX_START +: $clog2(WR_ROB_N_ENTRIES)] = wr_allocIdx;
    end

    //
    // Forward commands to slave, along with the rob index.
    //
    generate
        if (ADD_CLOCK_CROSSING)
        begin : cc
            // Need a clock crossing FIFO for write requests
            ofs_plat_prim_fifo_dc
              #(
                .N_DATA_BITS(SLAVE_USER_WIDTH +
                             mem_master.BURST_CNT_WIDTH +
                             mem_master.DATA_WIDTH +
                             mem_master.DATA_N_BYTES +
                             1 + // is write
                             mem_master.ADDR_WIDTH),
                .N_ENTRIES(16)
                )
              cmd_fifo
               (
                .enq_clk(mem_master.clk),
                .enq_reset_n(mem_master.reset_n),
                .enq_data({ slave_user,
                            mem_master.burstcount,
                            mem_master.writedata,
                            mem_master.byteenable,
                            mem_master.write,
                            mem_master.address }),
                .enq_en(cmd_enq_en),
                .notFull(cmd_fifo_notFull),
                .almostFull(),

                .deq_clk(mem_slave.clk),
                .deq_reset_n(mem_slave.reset_n),
                .first({ mem_slave.user,
                         mem_slave.burstcount,
                         mem_slave.writedata,
                         mem_slave.byteenable,
                         cmd_is_write,
                         mem_slave.address }),
                .deq_en(cmd_fifo_notEmpty && !mem_slave.waitrequest),
                .notEmpty(cmd_fifo_notEmpty)
                );
        end
        else
        begin : nc
            // No clock crossing. Simple two-stage FIFO.
            ofs_plat_prim_fifo2
              #(
                .N_DATA_BITS(SLAVE_USER_WIDTH +
                             mem_master.BURST_CNT_WIDTH +
                             mem_master.DATA_WIDTH +
                             mem_master.DATA_N_BYTES +
                             1 + // is write
                             mem_master.ADDR_WIDTH)
                )
              cmd_fifo
               (
                .clk(mem_master.clk),
                .reset_n(mem_master.reset_n),

                .enq_data({ slave_user,
                            mem_master.burstcount,
                            mem_master.writedata,
                            mem_master.byteenable,
                            mem_master.write,
                            mem_master.address }),
                .enq_en(cmd_enq_en),
                .notFull(cmd_fifo_notFull),

                .first({ mem_slave.user,
                         mem_slave.burstcount,
                         mem_slave.writedata,
                         mem_slave.byteenable,
                         cmd_is_write,
                         mem_slave.address }),
                .deq_en(cmd_fifo_notEmpty && !mem_slave.waitrequest),
                .notEmpty(cmd_fifo_notEmpty)
                );
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_if_async_rob
