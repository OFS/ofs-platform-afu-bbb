// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Wire together two AXI memory instances.
//
module ofs_plat_axi_mem_if_connect
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
        `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_sink);
    end

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

endmodule // ofs_plat_axi_mem_if_connect


// Same as standard connection, but pass clk and reset from sink to source
module ofs_plat_axi_mem_if_connect_sink_clk
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source_clk mem_source
    );

    assign mem_source.clk = mem_sink.clk;
    assign mem_source.reset_n = mem_sink.reset_n;

    // Debugging signal
    assign mem_source.instance_number = mem_sink.instance_number;

    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
        `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_sink);
    end

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

endmodule // ofs_plat_axi_mem_if_connect_sink_clk


// Same as standard connection, but pass clk and reset from source to sink
module ofs_plat_axi_mem_if_connect_source_clk
   (
    ofs_plat_axi_mem_if.to_sink_clk mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    assign mem_sink.clk = mem_source.clk;
    assign mem_sink.reset_n = mem_source.reset_n;

    // Debugging signal
    assign mem_sink.instance_number = mem_source.instance_number;

    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
        `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_sink);
    end

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

endmodule // ofs_plat_axi_mem_if_connect_sink_clk


//
// Wire together two AXI memory instances, copying field-by-field. This is
// needed when field width parameters vary between the interfaces.
//
module ofs_plat_axi_mem_if_connect_by_field
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    always_comb
    begin
        mem_sink.awvalid = mem_source.awvalid;
        mem_sink.wvalid = mem_source.wvalid;
        mem_sink.bready = mem_source.bready;
        mem_sink.arvalid = mem_source.arvalid;
        mem_sink.rready = mem_source.rready;
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_sink.aw, =, mem_source.aw);
        `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_sink.w, =, mem_source.w);
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_sink.ar, =, mem_source.ar);

        mem_source.awready = mem_sink.awready;
        mem_source.wready = mem_sink.wready;
        mem_source.bvalid = mem_sink.bvalid;
        mem_source.arready = mem_sink.arready;
        mem_source.rvalid = mem_sink.rvalid;
        `OFS_PLAT_AXI_MEM_IF_COPY_B(mem_source.b, =, mem_sink.b);
        `OFS_PLAT_AXI_MEM_IF_COPY_R(mem_source.r, =, mem_sink.r);
    end

endmodule // ofs_plat_axi_mem_if_connect
