// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Synchronize channels to simplify the AXI interface, making the AXI request
// channels behave more like Avalon:
//
//   - AW and W are guaranteed to arrive simultaneously.
//   - Optionally, only one of AR or AW/W may be valid at once.
//

module ofs_plat_axi_mem_lite_if_sync
  #(
    // Allow AW and AR to both be valid in the same cycle?
    parameter NO_SIMULTANEOUS_RW = 0
    )
   (
    ofs_plat_axi_mem_lite_if.to_sink mem_sink,
    ofs_plat_axi_mem_lite_if.to_source mem_source
    );

    logic clk;
    assign clk = mem_source.clk;
    logic reset_n;
    assign reset_n = mem_source.reset_n;

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    logic allow_rd, allow_wr;

    generate
        if (NO_SIMULTANEOUS_RW)
        begin : no_rw
            always_ff @(posedge clk)
            begin
                if (allow_rd)
                begin
                    // In read mode, there is a pending write, and no read
                    // requested or a read was just completed.
                    if ((!mem_source.arvalid || mem_sink.arready) &&
                        mem_source.awvalid)
                    begin
                        // Switch to write mode
                        allow_rd <= 1'b0;
                        allow_wr <= 1'b1;
                    end
                end
                else
                begin
                    // In write mode, there is a pending read, and no write
                    // requested or a write was just completed.
                    if ((!mem_source.awvalid || !mem_source.wvalid || mem_sink.awready) &&
                        mem_source.arvalid)
                    begin
                        // Switch to read mode
                        allow_rd <= 1'b1;
                        allow_wr <= 1'b0;
                    end
                end

                if (!reset_n)
                begin
                    allow_rd <= 1'b1;
                    allow_wr <= 1'b0;
                end
            end
        end
        else
        begin : rw
            // Allow simultaneous read and write requests
            assign allow_rd = 1'b1;
            assign allow_wr = 1'b1;
        end
    endgenerate

    always_comb
    begin
        mem_sink.awvalid = mem_source.awvalid && mem_source.wvalid && allow_wr;
        mem_source.awready = mem_sink.awready && mem_source.wvalid && allow_wr;
        mem_sink.aw = mem_source.aw;

        mem_sink.wvalid = mem_source.wvalid && mem_source.awvalid && allow_wr;
        mem_source.wready = mem_sink.wready && mem_source.awvalid && allow_wr;
        mem_sink.w = mem_source.w;

        mem_sink.arvalid = mem_source.arvalid && allow_rd;
        mem_source.arready = mem_sink.arready && allow_rd;
        mem_sink.ar = mem_source.ar;

        mem_source.bvalid = mem_sink.bvalid;
        mem_sink.bready = mem_source.bready;
        mem_source.b = mem_sink.b;

        mem_source.rvalid = mem_sink.rvalid;
        mem_sink.rready = mem_source.rready;
        mem_source.r = mem_sink.r;
    end

endmodule // ofs_plat_axi_mem_lite_if_sync
