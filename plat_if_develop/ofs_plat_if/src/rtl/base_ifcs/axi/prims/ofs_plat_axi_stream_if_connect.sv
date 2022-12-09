// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Wire together two AXI stream instances.
//
module ofs_plat_axi_stream_if_connect
   (
    ofs_plat_axi_stream_if.to_sink stream_sink,
    ofs_plat_axi_stream_if.to_source stream_source
    );

    always_comb
    begin
        `OFS_PLAT_AXI_STREAM_IF_FROM_SOURCE_TO_SINK_COMB(stream_sink, stream_source);
        `OFS_PLAT_AXI_STREAM_IF_FROM_SINK_TO_SOURCE_COMB(stream_source, stream_sink);
    end

    // synthesis translate_off
    `OFS_PLAT_AXI_STREAM_IF_CHECK_PARAMS_MATCH(stream_sink, stream_source)
    // synthesis translate_on

endmodule // ofs_plat_axi_stream_if_connect
