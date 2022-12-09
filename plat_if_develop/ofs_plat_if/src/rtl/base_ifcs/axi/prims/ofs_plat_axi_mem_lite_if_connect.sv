// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Wire together two AXI memory instances.
//
module ofs_plat_axi_mem_lite_if_connect
   (
    ofs_plat_axi_mem_lite_if.to_sink mem_sink,
    ofs_plat_axi_mem_lite_if.to_source mem_source
    );

    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
        `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_sink);
    end

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

endmodule // ofs_plat_axi_mem_lite_if_connect


// Same as standard connection, but pass clk and reset from sink to source
module ofs_plat_axi_mem_lite_if_connect_sink_clk
   (
    ofs_plat_axi_mem_lite_if.to_sink mem_sink,
    ofs_plat_axi_mem_lite_if.to_source_clk mem_source
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
    `OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

endmodule // ofs_plat_axi_mem_lite_if_connect_sink_clk


// Same as standard connection, but pass clk and reset from source to sink
module ofs_plat_axi_mem_lite_if_connect_source_clk
   (
    ofs_plat_axi_mem_lite_if.to_sink_clk mem_sink,
    ofs_plat_axi_mem_lite_if.to_source mem_source
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
    `OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

endmodule // ofs_plat_axi_mem_lite_if_connect_sink_clk
