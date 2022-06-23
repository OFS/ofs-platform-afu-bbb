//
// Copyright (c) 2022, Intel Corporation
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
// Map the local memory AXI-MM interface exposed by the FIM to the PIM's
// representation. The payload is the same in both.
//

`include "ofs_plat_if.vh"

module map_fim_emif_axi_mm_to_@group@_local_mem
  #(
    // Instance number is just used for debugging as a tag
    parameter INSTANCE_NUMBER = 0
    )
   (
    // FIM interface
    ofs_fim_emif_axi_mm_if.user fim_mem_bank,

    // PIM interface
    ofs_plat_axi_mem_if.to_source_clk afu_mem_bank
    );

    logic mb_rst_n = 1'b0;
    always @(posedge fim_mem_bank.clk)
    begin
      mb_rst_n <= fim_mem_bank.rst_n;
    end

    assign afu_mem_bank.clk = fim_mem_bank.clk;
    assign afu_mem_bank.reset_n = mb_rst_n;
    assign afu_mem_bank.instance_number = INSTANCE_NUMBER;

    assign afu_mem_bank.awready = fim_mem_bank.awready;
    assign fim_mem_bank.awvalid = afu_mem_bank.awvalid;
    assign fim_mem_bank.awid = afu_mem_bank.aw.id;
    assign fim_mem_bank.awaddr = afu_mem_bank.aw.addr;
    assign fim_mem_bank.awlen = afu_mem_bank.aw.len;
    assign fim_mem_bank.awsize = afu_mem_bank.aw.size;
    assign fim_mem_bank.awburst = afu_mem_bank.aw.burst;
    assign fim_mem_bank.awlock = afu_mem_bank.aw.lock;
    assign fim_mem_bank.awcache = afu_mem_bank.aw.cache;
    assign fim_mem_bank.awprot = afu_mem_bank.aw.prot;
    // assign fim_mem_bank.awqos = afu_mem_bank.aw.qos;
    assign fim_mem_bank.awuser = afu_mem_bank.aw.user;

    assign afu_mem_bank.wready = fim_mem_bank.wready;
    assign fim_mem_bank.wvalid = afu_mem_bank.wvalid;
    assign fim_mem_bank.wdata = afu_mem_bank.w.data;
    assign fim_mem_bank.wstrb = afu_mem_bank.w.strb;
    assign fim_mem_bank.wlast = afu_mem_bank.w.last;
    // assign fim_mem_bank.wuser = afu_mem_bank.w.user;

    assign fim_mem_bank.bready = afu_mem_bank.bready;
    assign afu_mem_bank.bvalid = fim_mem_bank.bvalid;
    always_comb
    begin
        afu_mem_bank.b = '0;
        afu_mem_bank.b.id = fim_mem_bank.bid;
        afu_mem_bank.b.resp = fim_mem_bank.bresp;
        afu_mem_bank.b.user = fim_mem_bank.buser;
    end

    assign afu_mem_bank.arready = fim_mem_bank.arready;
    assign fim_mem_bank.arvalid = afu_mem_bank.arvalid;
    assign fim_mem_bank.arid = afu_mem_bank.ar.id;
    assign fim_mem_bank.araddr = afu_mem_bank.ar.addr;
    assign fim_mem_bank.arlen = afu_mem_bank.ar.len;
    assign fim_mem_bank.arsize = afu_mem_bank.ar.size;
    assign fim_mem_bank.arburst = afu_mem_bank.ar.burst;
    assign fim_mem_bank.arlock = afu_mem_bank.ar.lock;
    assign fim_mem_bank.arcache = afu_mem_bank.ar.cache;
    assign fim_mem_bank.arprot = afu_mem_bank.ar.prot;
    // assign fim_mem_bank.arqos = afu_mem_bank.ar.qos;
    assign fim_mem_bank.aruser = afu_mem_bank.ar.user;

    assign fim_mem_bank.rready = afu_mem_bank.rready;
    assign afu_mem_bank.rvalid = fim_mem_bank.rvalid;
    always_comb
    begin
        afu_mem_bank.r = '0;
        afu_mem_bank.r.id = fim_mem_bank.rid;
        afu_mem_bank.r.data = fim_mem_bank.rdata;
        afu_mem_bank.r.resp = fim_mem_bank.rresp;
        afu_mem_bank.r.last = fim_mem_bank.rlast;
        afu_mem_bank.r.user = fim_mem_bank.ruser;
    end

endmodule // map_fim_emif_axi_mm_to_@group@_local_mem
