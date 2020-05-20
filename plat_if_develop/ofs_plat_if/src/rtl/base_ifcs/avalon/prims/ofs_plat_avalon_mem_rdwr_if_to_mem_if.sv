//
// Copyright (c) 2019, Intel Corporation
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
// Map a normal Avalon memory master to a split-bus Avalon slave.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_rdwr_if_to_mem_if
   (
    ofs_plat_avalon_mem_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master mem_master
    );

    localparam ADDR_WIDTH = mem_slave.ADDR_WIDTH_;
    localparam DATA_WIDTH = mem_slave.DATA_WIDTH_;
    localparam BURST_CNT_WIDTH = mem_slave.BURST_CNT_WIDTH_;
    localparam MASKED_SYMBOL_WIDTH = mem_slave.MASKED_SYMBOL_WIDTH_;
    localparam USER_WIDTH = mem_slave.USER_WIDTH_;

    localparam DATA_N_BYTES = (DATA_WIDTH + 7) / MASKED_SYMBOL_WIDTH;

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] address;
        logic [BURST_CNT_WIDTH-1:0] burstcount;
        logic [DATA_N_BYTES-1:0] byteenable;
        logic [USER_WIDTH-1:0] user;
    } t_rd_req;

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] address;
        logic [BURST_CNT_WIDTH-1:0] burstcount;
        logic [DATA_WIDTH-1:0] data;
        logic [DATA_N_BYTES-1:0] byteenable;
        logic [USER_WIDTH-1:0] user;
        logic wr_function;
        logic eop;
    } t_wr_req;

    wire clk;
    assign clk = mem_slave.clk;
    logic reset_n;
    assign reset_n = mem_slave.reset_n;

    //
    // Inbound requests from master
    //

    t_rd_req master_in_rd_req;
    t_wr_req master_in_wr_req;

    always_comb
    begin
        master_in_rd_req.address = mem_master.rd_address;
        master_in_rd_req.burstcount = mem_master.rd_burstcount;
        master_in_rd_req.byteenable = mem_master.rd_byteenable;
        master_in_rd_req.user = mem_master.rd_user;

        master_in_wr_req.address = mem_master.wr_address;
        master_in_wr_req.burstcount = mem_master.wr_burstcount;
        master_in_wr_req.data = mem_master.wr_writedata;
        master_in_wr_req.byteenable = mem_master.wr_byteenable;
        master_in_wr_req.user = mem_master.wr_user;
        master_in_wr_req.wr_function = mem_master.wr_function;
    end

    // Track master write bursts so they stay contiguous
    ofs_plat_prim_burstcount1_sop_tracker
      #(
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH)
        )
      sop_tracker
       (
        .clk,
        .reset_n,
        .flit_valid(mem_master.wr_write && !mem_master.wr_waitrequest),
        .burstcount(mem_master.wr_burstcount),
        .sop(),
        .eop(master_in_wr_req.eop)
        );

    //
    // Push requests to FIFOs
    //

    logic rd_req_notFull, rd_req_notEmpty;
    assign mem_master.rd_waitrequest = !rd_req_notFull;

    t_rd_req rd_req;
    logic rd_req_deq_en;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_rd_req))
        )
      rd_req_fifo
       (
        .clk,
        .reset_n,
        .enq_data(master_in_rd_req),
        .enq_en(mem_master.rd_read && !mem_master.rd_waitrequest),
        .notFull(rd_req_notFull),
        .first(rd_req),
        .deq_en(rd_req_deq_en),
        .notEmpty(rd_req_notEmpty)
        );

    logic wr_req_notFull, wr_req_notEmpty;
    assign mem_master.wr_waitrequest = !wr_req_notFull;

    t_wr_req wr_req;
    logic wr_req_deq_en;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_wr_req))
        )
      wr_req_fifo
       (
        .clk,
        .reset_n,
        .enq_data(master_in_wr_req),
        .enq_en(mem_master.wr_write && !mem_master.wr_waitrequest),
        .notFull(wr_req_notFull),
        .first(wr_req),
        .deq_en(wr_req_deq_en),
        .notEmpty(wr_req_notEmpty)
        );

    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n && wr_req_notEmpty && wr_req.wr_function)
        begin
            $fatal(2, "** ERROR ** %m: Write fence unsupported -- they can't be encoded in ofs_plat_avalon_mem_if!");
        end
    end
    // synthesis translate_on

    //
    // Arbiter -- map separate request channels into a single channel.
    //

    logic arb_grant_write;
    logic wr_burst_active;

    ofs_plat_prim_arb_rr
      #(
        .NUM_CLIENTS(2)
        )
      arb
       (
        .clk,
        .reset_n,
        .ena(!mem_slave.waitrequest && !wr_burst_active),
        .request({ wr_req_notEmpty, rd_req_notEmpty }),
        .grant({ arb_grant_write, mem_slave.read }),
        .grantIdx()
        );

    // Keep write bursts together
    always_ff @(posedge clk)
    begin
        if (mem_slave.write)
        begin
            wr_burst_active <= !wr_req.eop;
        end

        if (!reset_n)
        begin
            wr_burst_active <= 1'b0;
        end
    end

    // Send a write to the slave if a new write wins arbitration or if an existing
    // burst has a new beat. Read requests will never win arbitration in the middle
    // of a write burst.
    assign mem_slave.write = arb_grant_write ||
                             (!mem_slave.waitrequest && wr_burst_active && wr_req_notEmpty);

    assign rd_req_deq_en = mem_slave.read;
    assign wr_req_deq_en = mem_slave.write;

    logic pick_read;
    assign pick_read = mem_slave.read;

    always_comb
    begin
        mem_slave.address = pick_read ? rd_req.address : wr_req.address;
        mem_slave.burstcount = pick_read ? rd_req.burstcount : wr_req.burstcount;
        mem_slave.writedata = wr_req.data;
        mem_slave.byteenable = pick_read ? rd_req.byteenable : wr_req.byteenable;
        mem_slave.user = pick_read ? rd_req.user : wr_req.user;
    end

    // Responses
    always_comb
    begin
        mem_master.rd_readdata = mem_slave.readdata;
        mem_master.rd_readdatavalid = mem_slave.readdatavalid;
        mem_master.rd_response = mem_slave.response;
        mem_master.rd_readresponseuser = mem_slave.readresponseuser;

        mem_master.wr_writeresponsevalid = mem_slave.writeresponsevalid;
        mem_master.wr_response = mem_slave.writeresponse;
        mem_master.wr_writeresponseuser = mem_slave.writeresponseuser;
    end

endmodule // ofs_plat_avalon_mem_rdwr_if_to_mem_if
