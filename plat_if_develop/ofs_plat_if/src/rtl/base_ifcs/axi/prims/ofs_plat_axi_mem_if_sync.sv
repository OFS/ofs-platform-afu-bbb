// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Synchronize channels to simplify the AXI interface, making the AXI request
// channels behave more like Avalon. The AW and SOP on W are guaranteed to
// arrive simultaneously.
//
// *** SOP tracking only works if the sink consumes both AW and W when AW
// *** is valid.
//

module ofs_plat_axi_mem_if_sync
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    logic clk;
    assign clk = mem_source.clk;
    logic reset_n;
    assign reset_n = mem_source.reset_n;

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    // Track write stream SOP. AW is allowed only on SOP.
    logic wr_is_sop;
    always_ff @(posedge clk)
    begin
        if (mem_source.wready && mem_source.wvalid)
        begin
            wr_is_sop <= mem_source.w.last;
        end

        if (!reset_n)
        begin
            wr_is_sop <= 1'b1;
        end
    end

    always_comb
    begin
        mem_sink.awvalid = mem_source.awvalid && mem_source.wvalid && wr_is_sop;
        mem_source.awready = mem_sink.awready && mem_source.wvalid && wr_is_sop;
        mem_sink.aw = mem_source.aw;

        mem_sink.wvalid = mem_source.wvalid && (mem_source.awvalid || !wr_is_sop);
        mem_source.wready = mem_sink.wready && (mem_source.awvalid || !wr_is_sop);
        mem_sink.w = mem_source.w;

        mem_sink.arvalid = mem_source.arvalid;
        mem_source.arready = mem_sink.arready;
        mem_sink.ar = mem_source.ar;

        mem_source.bvalid = mem_sink.bvalid;
        mem_sink.bready = mem_source.bready;
        mem_source.b = mem_sink.b;

        mem_source.rvalid = mem_sink.rvalid;
        mem_sink.rready = mem_source.rready;
        mem_source.r = mem_sink.r;
    end

endmodule // ofs_plat_axi_mem_if_sync
