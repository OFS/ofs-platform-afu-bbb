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
// The PIM manages AXI user fields as three components:
//     { AFU user, FIM user flags, PIM user flags }
//
// AFU user values from requests are returned with responses. PIM user
// flags (from ofs_plat_local_mem_axi_mem_pkg) control PIM behavior.
// FIM user flags are passed to the native device.
//
// This module preserves AFU and PIM user request state, holding them in FIFOs
// and returning them with responses. The code assumes responses are returned
// in request order.
//

module ofs_plat_axi_mem_if_user_ext
  #(
    // Width of the native device's FIM user flags
    parameter FIM_USER_WIDTH = 1,

    // Number of entries in the response trackers.
    parameter RD_RESP_USER_ENTRIES = 512,
    parameter WR_RESP_USER_ENTRIES = 512
    )
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    logic clk;
    assign clk = mem_sink.clk;
    logic reset_n;
    assign reset_n = mem_sink.reset_n;

    // The response FIFO is a block RAM. Allocating less than 512 entries
    // won't save space.
    localparam RD_FIFO_ENTRIES = (RD_RESP_USER_ENTRIES > 512) ? RD_RESP_USER_ENTRIES : 512;
    localparam WR_FIFO_ENTRIES = (WR_RESP_USER_ENTRIES > 512) ? WR_RESP_USER_ENTRIES : 512;

    localparam USER_WIDTH = mem_source.USER_WIDTH;
    typedef logic [USER_WIDTH-1 : 0] t_user;

    localparam FIM_USER_START = ofs_plat_local_mem_axi_mem_pkg::LM_AXI_UFLAG_WIDTH;


    //
    // Track read request/response user fields.
    //
    logic rd_fifo_notFull;
    t_user rd_fifo_user;
    logic rd_fifo_deq;

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(USER_WIDTH),
        .N_ENTRIES(RD_FIFO_ENTRIES)
        )
      rd_fifo
       (
        .clk,
        .reset_n,

        .enq_en(mem_source.arvalid && mem_source.arready),
        .enq_data(mem_source.ar.user),
        .notFull(rd_fifo_notFull),
        .almostFull(),

        .first(rd_fifo_user),
        .deq_en(mem_source.rvalid && mem_source.rready && mem_source.r.last),
        // FIFO must have data. The FIFO primitive will generate an error
        // (in simulation) if this isn't true.
        .notEmpty()
        );


    //
    // Track write request/response user fields.
    //
    logic wr_fifo_notFull;
    t_user wr_fifo_user;

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(USER_WIDTH),
        .N_ENTRIES(WR_FIFO_ENTRIES)
        )
      wr_fifo
       (
        .clk,
        .reset_n,

        .enq_en(mem_source.awvalid && mem_source.awready),
        .enq_data(mem_source.aw.user),
        .notFull(wr_fifo_notFull),
        .almostFull(),

        .first(wr_fifo_user),
        .deq_en(mem_source.bvalid && mem_source.bready),
        // FIFO must have data. The FIFO primitive will generate an error
        // (in simulation) if this isn't true.
        .notEmpty()
        );


    //
    // Connect source and sink and add response metadata.
    //
    always_comb
    begin
        // Most fields can just be wired together
        mem_sink.awvalid = mem_source.awvalid;
        mem_source.awready = mem_sink.awready && wr_fifo_notFull;
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_sink.aw, =, mem_source.aw);

        mem_sink.wvalid = mem_source.wvalid;
        mem_source.wready = mem_sink.wready;
        `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_sink.w, =, mem_source.w);

        mem_source.bvalid = mem_sink.bvalid;
        mem_sink.bready = mem_source.bready;
        `OFS_PLAT_AXI_MEM_IF_COPY_B(mem_source.b, =, mem_sink.b);
        mem_source.b.user = wr_fifo_user;
        mem_source.b.user[FIM_USER_START +: FIM_USER_WIDTH] = mem_sink.b.user[FIM_USER_START +: FIM_USER_WIDTH];


        mem_sink.arvalid = mem_source.arvalid;
        mem_source.arready = mem_sink.arready && rd_fifo_notFull;
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_sink.ar, =, mem_source.ar);

        mem_source.rvalid = mem_sink.rvalid;
        mem_sink.rready = mem_source.rready;
        `OFS_PLAT_AXI_MEM_IF_COPY_R(mem_source.r, =, mem_sink.r);
        mem_source.r.user = rd_fifo_user;
        mem_source.r.user[FIM_USER_START +: FIM_USER_WIDTH] = mem_sink.r.user[FIM_USER_START +: FIM_USER_WIDTH];
    end

endmodule // ofs_plat_axi_mem_if_user_ext
