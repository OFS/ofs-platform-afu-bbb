// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Map the local memory AXI-MM interface exposed by the FIM to the PIM's
// representation. The payload is the same in both.
//

`include "ofs_plat_if.vh"

module map_fim_emif_axi_mm_to_local_mem
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

    bit mb_rst_n = 1'b0;
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

endmodule // map_fim_emif_axi_mm_to_local_mem


//
// Reverse of the mapping above, used mainly in simulation. It maps a PIM
// sink to a FIM emif interface. ASE's local memory emulator offers a PIM
// AXI-MM interface and this module transforms it to the FIM's equivalent,
// which may be required when emulating in afu_main mode.
//
module map_local_mem_to_fim_emif_axi_mm
  #(
    // Instance number is just used for debugging as a tag
    parameter INSTANCE_NUMBER = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

    // PIM interface
    ofs_plat_axi_mem_if.to_sink_clk pim_mem_bank,

    // FIM interface
    ofs_fim_emif_axi_mm_if.emif fim_mem_bank
    );

    assign pim_mem_bank.clk = clk;
    assign pim_mem_bank.reset_n = reset_n;
    assign pim_mem_bank.instance_number = INSTANCE_NUMBER;

    assign fim_mem_bank.clk = pim_mem_bank.clk;
    assign fim_mem_bank.rst_n = pim_mem_bank.reset_n;

    assign fim_mem_bank.awready = pim_mem_bank.awready;
    assign pim_mem_bank.awvalid = fim_mem_bank.awvalid;
    always_comb
    begin
        pim_mem_bank.aw = '0;
        pim_mem_bank.aw.id = fim_mem_bank.awid;
        pim_mem_bank.aw.addr = fim_mem_bank.awaddr;
        pim_mem_bank.aw.len = fim_mem_bank.awlen;
        pim_mem_bank.aw.size = fim_mem_bank.awsize;
        pim_mem_bank.aw.burst = fim_mem_bank.awburst;
        pim_mem_bank.aw.lock = fim_mem_bank.awlock;
        pim_mem_bank.aw.cache = fim_mem_bank.awcache;
        pim_mem_bank.aw.prot = fim_mem_bank.awprot;
        pim_mem_bank.aw.qos = '0;
        pim_mem_bank.aw.user = fim_mem_bank.awuser;
    end

    assign fim_mem_bank.wready = pim_mem_bank.wready;
    assign pim_mem_bank.wvalid = fim_mem_bank.wvalid;
    always_comb
    begin
        pim_mem_bank.w = '0;
        pim_mem_bank.w.data = fim_mem_bank.wdata;
        pim_mem_bank.w.strb = fim_mem_bank.wstrb;
        pim_mem_bank.w.last = fim_mem_bank.wlast;
        pim_mem_bank.w.user = '0;
    end

    assign pim_mem_bank.bready = fim_mem_bank.bready;
    assign fim_mem_bank.bvalid = pim_mem_bank.bvalid;
    assign fim_mem_bank.bid = pim_mem_bank.b.id;
    assign fim_mem_bank.bresp = pim_mem_bank.b.resp;
    assign fim_mem_bank.buser = pim_mem_bank.b.user;

    assign fim_mem_bank.arready = pim_mem_bank.arready;
    assign pim_mem_bank.arvalid = fim_mem_bank.arvalid;
    always_comb
    begin
        pim_mem_bank.ar = '0;
        pim_mem_bank.ar.id = fim_mem_bank.arid;
        pim_mem_bank.ar.addr = fim_mem_bank.araddr;
        pim_mem_bank.ar.len = fim_mem_bank.arlen;
        pim_mem_bank.ar.size = fim_mem_bank.arsize;
        pim_mem_bank.ar.burst = fim_mem_bank.arburst;
        pim_mem_bank.ar.lock = fim_mem_bank.arlock;
        pim_mem_bank.ar.cache = fim_mem_bank.arcache;
        pim_mem_bank.ar.prot = fim_mem_bank.arprot;
        pim_mem_bank.ar.qos = '0;
        pim_mem_bank.ar.user = fim_mem_bank.aruser;
    end

    assign pim_mem_bank.rready = fim_mem_bank.rready;
    assign fim_mem_bank.rvalid = pim_mem_bank.rvalid;
    assign fim_mem_bank.rid = pim_mem_bank.r.id;
    assign fim_mem_bank.rdata = pim_mem_bank.r.data;
    assign fim_mem_bank.rresp = pim_mem_bank.r.resp;
    assign fim_mem_bank.rlast = pim_mem_bank.r.last;
    assign fim_mem_bank.ruser = pim_mem_bank.r.user;

endmodule // map_local_mem_to_fim_emif_axi_mm
