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
// Protect AXI memory read and write response buffers from overflow by tracking
// requests. Typically, the protected buffers are the entry points for responses
// from devices that don't have flow control.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_if_rsp_credits
  #(
    parameter NUM_READ_CREDITS = 256,
    parameter NUM_WRITE_CREDITS = 128
    )
   (
    ofs_plat_axi_mem_if.to_slave mem_slave,
    ofs_plat_axi_mem_if.to_master mem_master
    );

    logic clk;
    assign clk = mem_slave.clk;
    logic reset_n;
    assign reset_n = mem_slave.reset_n;

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_slave, mem_master)
    // synthesis translate_on

    // Write data needs no flow control here
    assign mem_master.wready = mem_slave.wready;
    assign mem_slave.wvalid = mem_master.wvalid;
    assign mem_slave.w = mem_master.w;

    // Responses need no flow control here, though they will be monitored
    // in order to restore credits.
    assign mem_slave.bready = mem_master.bready;
    assign mem_master.bvalid = mem_slave.bvalid;
    assign mem_master.b = mem_slave.b;

    assign mem_slave.rready = mem_master.rready;
    assign mem_master.rvalid = mem_slave.rvalid;
    assign mem_master.r = mem_slave.r;

    //
    // Incoming write address stream.
    //
    // There is one write address request for every response.
    //
    typedef logic [$clog2(NUM_WRITE_CREDITS+1)-1 : 0] t_wr_credits;
    t_wr_credits n_wr_credits;

    logic wr_req_valid;
    logic fwd_wr_req;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(mem_master.T_AW_WIDTH)
        )
      aw_fifo
       (
        .clk,
        .reset_n,
        .enq_data(mem_master.aw),
        .enq_en(mem_master.awready && mem_master.awvalid),
        .notFull(mem_master.awready),
        .first(mem_slave.aw),
        .deq_en(fwd_wr_req),
        .notEmpty(wr_req_valid)
        );

    assign mem_slave.awvalid = wr_req_valid && (n_wr_credits != t_wr_credits'(0));
    assign fwd_wr_req = mem_slave.awvalid && mem_slave.awready;

    // Track write responses. Add a pipeline stage for timing since single
    // response credits aren't important.
    logic wr_resp_valid, wr_resp_valid_q;

    always_ff @(posedge clk)
    begin
        wr_resp_valid <= mem_slave.bvalid && mem_slave.bready;
        wr_resp_valid_q <= wr_resp_valid;
    end

    // Track write credits
    always_ff @(posedge clk)
    begin
        if (fwd_wr_req && !wr_resp_valid_q)
            n_wr_credits <= n_wr_credits - 1;
        else if (!fwd_wr_req && wr_resp_valid_q)
            n_wr_credits <= n_wr_credits + 1;

        if (!reset_n)
        begin
            n_wr_credits <= t_wr_credits'(NUM_WRITE_CREDITS);
	end
    end


    //
    // Incoming read address stream
    //
    localparam MAX_RD_PER_REQ = 1 << mem_slave.BURST_CNT_WIDTH;
    typedef logic [$clog2(NUM_READ_CREDITS+1)-1 : 0] t_rd_credits;
    t_rd_credits n_rd_credits;

    logic rd_req_valid;
    logic fwd_rd_req;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(mem_master.T_AR_WIDTH)
        )
      ar_fifo
       (
        .clk,
        .reset_n,
        .enq_data(mem_master.ar),
        .enq_en(mem_master.arready && mem_master.arvalid),
        .notFull(mem_master.arready),
        .first(mem_slave.ar),
        .deq_en(fwd_rd_req),
        .notEmpty(rd_req_valid)
        );

    assign mem_slave.arvalid = rd_req_valid && (n_rd_credits >= t_wr_credits'(MAX_RD_PER_REQ));
    assign fwd_rd_req = mem_slave.arvalid && mem_slave.arready;

    // Track read responses. Add a pipeline stage for timing since single
    // response credits aren't important.
    logic rd_resp_valid, rd_resp_valid_q;

    always_ff @(posedge clk)
    begin
        rd_resp_valid <= mem_slave.rvalid && mem_slave.rready;
        rd_resp_valid_q <= rd_resp_valid;
    end

    // Track read credits
    always_ff @(posedge clk)
    begin
        if (!fwd_rd_req)
            // Just, perhaps, a response -- no request
            n_rd_credits <= n_rd_credits + rd_resp_valid_q;
        else if (rd_resp_valid_q)
            // Both response and request
            n_rd_credits <= n_rd_credits - mem_slave.ar.len;
        else
            // Just a request
            n_rd_credits <= n_rd_credits - mem_slave.ar.len - 1;

        if (!reset_n)
        begin
            n_rd_credits <= t_rd_credits'(NUM_READ_CREDITS);
	end
    end

endmodule // ofs_plat_axi_mem_if_rsp_credits
