// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
// Since the module assumes in-order responses, it can also preserve extra
// ID bits if the AFU's ARID or AWID field is wider than the FIM's.
//

module ofs_plat_axi_mem_if_user_ext
  #(
    // Width of the native device's FIM user flags
    parameter FIM_USER_WIDTH = 1,

    // Force FIM-side user to zero? In some implementations, the user bits
    // may indicate some property of the request. The FIM might also not
    // return the original user bits with a response -- a semantic expected
    // by PIM clients.
    parameter FORCE_USER_TO_ZERO = 0,

    // Preserve the ID bits in requests passed to the FIM or set them to zero?
    // When set to zero, AXI memory subsystems are forced to keep transactions
    // ordered. Even when enabled, IDs are recorded here and returned with
    // responses to PIM clients.
    parameter FORCE_RD_ID_TO_ZERO = 0,
    parameter FORCE_WR_ID_TO_ZERO = 0,

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

    localparam RID_WIDTH = mem_source.RID_WIDTH;
    typedef logic [RID_WIDTH-1 : 0] t_rid;
    // Common portion of RID (the smaller of sink and source)
    localparam RID_COMMON_WIDTH = (RID_WIDTH < mem_sink.RID_WIDTH) ? RID_WIDTH : mem_sink.RID_WIDTH;

    localparam WID_WIDTH = mem_source.WID_WIDTH;
    typedef logic [WID_WIDTH-1 : 0] t_wid;
    localparam WID_COMMON_WIDTH = (WID_WIDTH < mem_sink.WID_WIDTH) ? WID_WIDTH : mem_sink.WID_WIDTH;

    localparam FIM_USER_START = ofs_plat_local_mem_axi_mem_pkg::LM_AXI_UFLAG_WIDTH;


    //
    // Track read request/response user and ID fields. The whole field is tracked,
    // though not all is required since the FIM will return some. Quartus will
    // drop the unconsumed portion.
    //
    logic rd_fifo_notFull;
    t_user rd_fifo_user;
    t_rid rd_fifo_rid;
    logic rd_fifo_deq;

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(RID_WIDTH + USER_WIDTH),
        .N_ENTRIES(RD_FIFO_ENTRIES)
        )
      rd_fifo
       (
        .clk,
        .reset_n,

        .enq_en(mem_source.arvalid && mem_source.arready),
        .enq_data({ mem_source.ar.id, mem_source.ar.user }),
        .notFull(rd_fifo_notFull),
        .almostFull(),

        .first({ rd_fifo_rid, rd_fifo_user }),
        .deq_en(mem_source.rvalid && mem_source.rready && mem_source.r.last),
        // FIFO must have data. The FIFO primitive will generate an error
        // (in simulation) if this isn't true.
        .notEmpty()
        );


    //
    // Track write request/response user and ID fields.
    //
    logic wr_fifo_notFull;
    t_user wr_fifo_user;
    t_wid wr_fifo_wid;

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(WID_WIDTH + USER_WIDTH),
        .N_ENTRIES(WR_FIFO_ENTRIES)
        )
      wr_fifo
       (
        .clk,
        .reset_n,

        .enq_en(mem_source.awvalid && mem_source.awready),
        .enq_data({ mem_source.aw.id, mem_source.aw.user }),
        .notFull(wr_fifo_notFull),
        .almostFull(),

        .first({ wr_fifo_wid, wr_fifo_user }),
        .deq_en(mem_source.bvalid && mem_source.bready),
        // FIFO must have data. The FIFO primitive will generate an error
        // (in simulation) if this isn't true.
        .notEmpty()
        );


    //
    // Connect source and sink and add response metadata.
    //
    t_wid merged_wid;
    t_rid merged_rid;

    always_comb
    begin
        // Most fields can just be wired together
        mem_sink.awvalid = mem_source.awvalid && wr_fifo_notFull;
        mem_source.awready = mem_sink.awready && wr_fifo_notFull;
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_sink.aw, =, mem_source.aw);
        if (FORCE_USER_TO_ZERO) mem_sink.aw.user = '0;
        if (FORCE_WR_ID_TO_ZERO) mem_sink.aw.id = '0;

        mem_sink.wvalid = mem_source.wvalid;
        mem_source.wready = mem_sink.wready;
        `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_sink.w, =, mem_source.w);
        if (FORCE_USER_TO_ZERO) mem_sink.w.user = '0;

        mem_source.bvalid = mem_sink.bvalid;
        mem_sink.bready = mem_source.bready;
        `OFS_PLAT_AXI_MEM_IF_COPY_B(mem_source.b, =, mem_sink.b);
        mem_source.b.user = wr_fifo_user;
        merged_wid = wr_fifo_wid;
        if (!FORCE_WR_ID_TO_ZERO) merged_wid[WID_COMMON_WIDTH-1 : 0] = WID_COMMON_WIDTH'(mem_sink.b.id);
        mem_source.b.id = merged_wid;


        mem_sink.arvalid = mem_source.arvalid && rd_fifo_notFull;
        mem_source.arready = mem_sink.arready && rd_fifo_notFull;
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_sink.ar, =, mem_source.ar);
        if (FORCE_USER_TO_ZERO) mem_sink.ar.user = '0;
        if (FORCE_RD_ID_TO_ZERO) mem_sink.ar.id = '0;

        mem_source.rvalid = mem_sink.rvalid;
        mem_sink.rready = mem_source.rready;
        `OFS_PLAT_AXI_MEM_IF_COPY_R(mem_source.r, =, mem_sink.r);
        mem_source.r.user = rd_fifo_user;
        merged_rid = rd_fifo_rid;
        if (!FORCE_RD_ID_TO_ZERO) merged_rid[RID_COMMON_WIDTH-1 : 0] = RID_COMMON_WIDTH'(mem_sink.r.id);
        mem_source.r.id = merged_rid;
    end

endmodule // ofs_plat_axi_mem_if_user_ext
