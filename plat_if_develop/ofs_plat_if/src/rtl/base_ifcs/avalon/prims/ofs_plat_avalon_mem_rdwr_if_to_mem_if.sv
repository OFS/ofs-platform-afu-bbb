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
// Map a normal Avalon memory source to a split-bus Avalon sink.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_rdwr_if_to_mem_if
  #(
    // Generate a write response inside this module as write requests
    // commit? Some Avalon sinks may not generate write responses.
    // With LOCAL_WR_RESPONSE set, write responses are generated as
    // soon as write requests win arbitration.
    parameter LOCAL_WR_RESPONSE = 0,

    // When LOCAL_WR_RESPONSE is set, preserve USER field? This
    // field is ignored when LOCAL_WR_RESPONSE is 0.
    parameter PRESERVE_WR_RESPONSE_USER = 1
    )
   (
    ofs_plat_avalon_mem_if.to_sink mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source
    );

    localparam ADDR_WIDTH = mem_sink.ADDR_WIDTH_;
    localparam DATA_WIDTH = mem_sink.DATA_WIDTH_;
    localparam BURST_CNT_WIDTH = mem_sink.BURST_CNT_WIDTH_;
    localparam MASKED_SYMBOL_WIDTH = mem_sink.MASKED_SYMBOL_WIDTH_;
    localparam USER_WIDTH = mem_source.USER_WIDTH_;

    localparam DATA_N_BYTES = mem_sink.DATA_N_BYTES;

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] address;
        logic [BURST_CNT_WIDTH-1:0] burstcount;
        logic [DATA_N_BYTES-1:0] byteenable;
        logic [USER_WIDTH-1:0] user;
    } t_rd_req;
    // Some simulators weren't happy with $bits(t_rd_req)
    localparam T_RD_REQ_WIDTH = ADDR_WIDTH + BURST_CNT_WIDTH + DATA_N_BYTES + USER_WIDTH;

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] address;
        logic [BURST_CNT_WIDTH-1:0] burstcount;
        logic [DATA_WIDTH-1:0] data;
        logic [DATA_N_BYTES-1:0] byteenable;
        logic [USER_WIDTH-1:0] user;
        logic eop;
    } t_wr_req;
    // Some simulators weren't happy with $bits(t_rd_req)
    localparam T_WR_REQ_WIDTH = ADDR_WIDTH + BURST_CNT_WIDTH +
                                DATA_WIDTH + DATA_N_BYTES + USER_WIDTH + 1;

    wire clk;
    assign clk = mem_sink.clk;
    logic reset_n;
    assign reset_n = mem_sink.reset_n;

    //
    // Inbound requests from source
    //

    t_rd_req source_in_rd_req;
    t_wr_req source_in_wr_req;

    always_comb
    begin
        source_in_rd_req.address = mem_source.rd_address;
        source_in_rd_req.burstcount = mem_source.rd_burstcount;
        source_in_rd_req.byteenable = mem_source.rd_byteenable;
        source_in_rd_req.user = mem_source.rd_user;

        source_in_wr_req.address = mem_source.wr_address;
        source_in_wr_req.burstcount = mem_source.wr_burstcount;
        source_in_wr_req.data = mem_source.wr_writedata;
        source_in_wr_req.byteenable = mem_source.wr_byteenable;
        source_in_wr_req.user = mem_source.wr_user;
    end

    // Track source write bursts so they stay contiguous
    ofs_plat_prim_burstcount1_sop_tracker
      #(
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH)
        )
      sop_tracker
       (
        .clk,
        .reset_n,
        .flit_valid(mem_source.wr_write && !mem_source.wr_waitrequest),
        .burstcount(mem_source.wr_burstcount),
        .sop(),
        .eop(source_in_wr_req.eop)
        );

    //
    // Push requests to FIFOs
    //

    logic rd_req_notFull, rd_req_notEmpty;
    assign mem_source.rd_waitrequest = !rd_req_notFull;

    t_rd_req rd_req;
    logic rd_req_deq_en;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(T_RD_REQ_WIDTH)
        )
      rd_req_fifo
       (
        .clk,
        .reset_n,
        .enq_data(source_in_rd_req),
        .enq_en(mem_source.rd_read && !mem_source.rd_waitrequest),
        .notFull(rd_req_notFull),
        .first(rd_req),
        .deq_en(rd_req_deq_en),
        .notEmpty(rd_req_notEmpty)
        );

    logic wr_req_notFull, wr_req_notEmpty;
    assign mem_source.wr_waitrequest = !wr_req_notFull;

    t_wr_req wr_req;
    logic wr_req_deq_en;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(T_WR_REQ_WIDTH)
        )
      wr_req_fifo
       (
        .clk,
        .reset_n,
        .enq_data(source_in_wr_req),
        .enq_en(mem_source.wr_write && !mem_source.wr_waitrequest),
        .notFull(wr_req_notFull),
        .first(wr_req),
        .deq_en(wr_req_deq_en),
        .notEmpty(wr_req_notEmpty)
        );

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
        .ena(!mem_sink.waitrequest && !wr_burst_active),
        .request({ wr_req_notEmpty, rd_req_notEmpty }),
        .grant({ arb_grant_write, mem_sink.read }),
        .grantIdx()
        );

    // Keep write bursts together
    always_ff @(posedge clk)
    begin
        if (mem_sink.write)
        begin
            wr_burst_active <= !wr_req.eop;
        end

        if (!reset_n)
        begin
            wr_burst_active <= 1'b0;
        end
    end

    // Send a write to the sink if a new write wins arbitration or if an existing
    // burst has a new beat. Read requests will never win arbitration in the middle
    // of a write burst.
    assign mem_sink.write = arb_grant_write ||
                             (!mem_sink.waitrequest && wr_burst_active && wr_req_notEmpty);

    assign rd_req_deq_en = mem_sink.read;
    assign wr_req_deq_en = mem_sink.write;

    logic pick_read;
    assign pick_read = mem_sink.read;

    always_comb
    begin
        mem_sink.address = pick_read ? rd_req.address : wr_req.address;
        mem_sink.burstcount = pick_read ? rd_req.burstcount : wr_req.burstcount;
        mem_sink.writedata = wr_req.data;
        mem_sink.byteenable = pick_read ? rd_req.byteenable : wr_req.byteenable;
        mem_sink.user = pick_read ? rd_req.user : wr_req.user;
    end

    // Responses
    always_comb
    begin
        mem_source.rd_readdata = mem_sink.readdata;
        mem_source.rd_readdatavalid = mem_sink.readdatavalid;
        mem_source.rd_response = mem_sink.response;
        mem_source.rd_readresponseuser = mem_sink.readresponseuser;
    end

    always_ff @(posedge clk)
    begin
        if (LOCAL_WR_RESPONSE == 0)
        begin
            // Sink will generate a response
            mem_source.wr_writeresponsevalid <= mem_sink.writeresponsevalid;
            mem_source.wr_response <= mem_sink.writeresponse;
            mem_source.wr_writeresponseuser <= mem_sink.writeresponseuser;
        end
        else
        begin
            // Response generated here as writes win arbitrarion
            mem_source.wr_writeresponsevalid <= arb_grant_write && !mem_sink.waitrequest &&
                                                !wr_burst_active;
            mem_source.wr_response <= '0;

            if (PRESERVE_WR_RESPONSE_USER != 0)
                mem_source.wr_writeresponseuser <= wr_req.user;
            else
                mem_source.wr_writeresponseuser <= '0;
        end

        if (!reset_n)
        begin
            mem_source.wr_writeresponsevalid <= 1'b0;
        end
    end

endmodule // ofs_plat_avalon_mem_rdwr_if_to_mem_if
