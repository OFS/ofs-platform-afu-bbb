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

`include "ofs_plat_if.vh"

//
// Add user extention fields to Avalon memory responses. This is used when
// the native interface doesn't implement user field extensions or write
// responses.
//

module ofs_plat_avalon_mem_if_user_ext
  #(
    // Number of entries in the read response tracker.
    parameter RD_RESP_USER_ENTRIES = 512
    )
   (
    ofs_plat_avalon_mem_if.to_sink mem_sink,
    ofs_plat_avalon_mem_if.to_source mem_source
    );

    logic clk;
    assign clk = mem_sink.clk;
    logic reset_n;
    assign reset_n = mem_sink.reset_n;

    // The read response FIFO is a block RAM. Allocating less than 512 entries
    // won't save space.
    localparam RD_FIFO_ENTRIES = (RD_RESP_USER_ENTRIES > 512) ? RD_RESP_USER_ENTRIES : 512;

    localparam BURST_CNT_WIDTH = mem_source.BURST_CNT_WIDTH;
    typedef logic [BURST_CNT_WIDTH-1 : 0] t_burst_cnt;

    localparam USER_WIDTH = mem_source.USER_WIDTH;
    typedef logic [USER_WIDTH-1 : 0] t_user;


    //
    // Track read request/response user fields.
    //
    logic rd_fifo_notFull;
    t_burst_cnt rd_fifo_burstcount;
    t_user rd_fifo_user;
    logic rd_fifo_deq;

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(BURST_CNT_WIDTH + USER_WIDTH),
        .N_ENTRIES(RD_FIFO_ENTRIES)
        )
      rd_fifo
       (
        .clk,
        .reset_n,

        .enq_en(mem_source.read && !mem_source.waitrequest),
        .enq_data({ mem_source.burstcount, mem_source.user }),
        .notFull(rd_fifo_notFull),
        .almostFull(),

        .first({ rd_fifo_burstcount, rd_fifo_user }),
        .deq_en(rd_fifo_deq),
        // FIFO must have data. The FIFO primitive will generate an error
        // (in simulation) if this isn't true.
        .notEmpty()
        );

    //
    // Count responses and pop entries off the read response FIFO at the end
    // of each burst.
    //
    t_burst_cnt rd_cnt_burst;

    assign rd_fifo_deq = mem_sink.readdatavalid && (rd_cnt_burst == rd_fifo_burstcount);

    always_ff @(posedge clk)
    begin
        if (mem_sink.readdatavalid)
        begin
            // Burst complete?
            if (rd_cnt_burst == rd_fifo_burstcount)
                rd_cnt_burst <= 1;
            else
                rd_cnt_burst <= rd_cnt_burst + 1;
        end

        if (!reset_n)
        begin
            rd_cnt_burst <= 1;
        end
    end


    //
    // Track write requests in order to generate write responses here.
    //
    logic wr_sop, wr_eop;
    t_user wr_user;
    logic wr_resp_valid;
    t_user wr_resp_user;

    ofs_plat_prim_burstcount1_sop_tracker
      #(
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH)
        )
      wr_sop_tracker
       (
        .clk,
        .reset_n,

        .flit_valid(mem_source.write && !mem_source.waitrequest),
        .burstcount(mem_source.burstcount),

        .sop(wr_sop),
        .eop(wr_eop)
        );

    always_ff @(posedge clk)
    begin
        // Record user on first beat
        if (wr_sop && mem_source.write && !mem_source.waitrequest)
        begin
            wr_user <= mem_source.user;
        end

        // Generate response
        wr_resp_valid <= (wr_eop && mem_source.write && !mem_source.waitrequest);
        wr_resp_user <= (wr_sop ? mem_source.user : wr_user);
    end


    //
    // Connect source and sink and add response metadata.
    //
    always_comb
    begin
        // Most fields can just be wired together
        `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
        `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_sink);

        // Block if the read FIFO fills
        mem_source.waitrequest = mem_sink.waitrequest || !rd_fifo_notFull;

        // Add the read user meta-data
        mem_source.readresponseuser = rd_fifo_user;

        // Generate write responses
        mem_source.writeresponsevalid = wr_resp_valid;
        mem_source.writeresponseuser = wr_resp_user;
        mem_source.writeresponse = '0;
    end

endmodule // ofs_plat_avalon_mem_if_user_ext
