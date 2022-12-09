// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Connect a pair of AXI stream interfaces with a skid buffer.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_stream_if_skid
   (
    ofs_plat_axi_stream_if.to_sink stream_sink,
    ofs_plat_axi_stream_if.to_source stream_source
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_STREAM_IF_CHECK_PARAMS_MATCH(stream_sink, stream_source)
    // synthesis translate_on

    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(stream_source.T_PAYLOAD_WIDTH)
        )
      skid
       (
        .clk(stream_source.clk),
        .reset_n(stream_source.reset_n),

        .enable_from_src(stream_source.tvalid),
        .data_from_src(stream_source.t),
        .ready_to_src(stream_source.tready),

        .enable_to_dst(stream_sink.tvalid),
        .data_to_dst(stream_sink.t),
        .ready_from_dst(stream_sink.tready)
        );

endmodule // ofs_plat_axi_stream_if_skid


// Pass clock from sink to source
module ofs_plat_axi_stream_if_skid_sink_clk
   (
    ofs_plat_axi_stream_if.to_sink stream_sink,
    ofs_plat_axi_stream_if.to_source_clk stream_source
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_STREAM_IF_CHECK_PARAMS_MATCH(stream_sink, stream_source)
    // synthesis translate_on

    assign stream_source.clk = stream_sink.clk;
    assign stream_source.reset_n = stream_sink.reset_n;
    // Debugging signal
    assign stream_source.instance_number = stream_sink.instance_number;

    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(stream_source.T_PAYLOAD_WIDTH)
        )
      skid
       (
        .clk(stream_source.clk),
        .reset_n(stream_source.reset_n),

        .enable_from_src(stream_source.tvalid),
        .data_from_src(stream_source.t),
        .ready_to_src(stream_source.tready),

        .enable_to_dst(stream_sink.tvalid),
        .data_to_dst(stream_sink.t),
        .ready_from_dst(stream_sink.tready)
        );

endmodule // ofs_plat_axi_stream_if_skid_sink_clk


// Pass clock from source to sink
module ofs_plat_axi_stream_if_skid_source_clk
   (
    ofs_plat_axi_stream_if.to_sink_clk stream_sink,
    ofs_plat_axi_stream_if.to_source stream_source
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_STREAM_IF_CHECK_PARAMS_MATCH(stream_sink, stream_source)
    // synthesis translate_on

    assign stream_sink.clk = stream_source.clk;
    assign stream_sink.reset_n = stream_source.reset_n;
    // Debugging signal
    assign stream_sink.instance_number = stream_source.instance_number;

    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(stream_source.T_PAYLOAD_WIDTH)
        )
      skid
       (
        .clk(stream_source.clk),
        .reset_n(stream_source.reset_n),

        .enable_from_src(stream_source.tvalid),
        .data_from_src(stream_source.t),
        .ready_to_src(stream_source.tready),

        .enable_to_dst(stream_sink.tvalid),
        .data_to_dst(stream_sink.t),
        .ready_from_dst(stream_sink.tready)
        );

endmodule // ofs_plat_axi_stream_if_skid_source_clk
