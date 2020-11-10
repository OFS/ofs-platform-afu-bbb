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
// Insert skid buffers on all channels between the two interfaces.
//

module ofs_plat_axi_mem_if_skid
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

    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(mem_source.T_AW_WIDTH)
        )
      mem_aw_skid
       (
        .clk,
        .reset_n,

        .enable_from_src(mem_source.awvalid),
        .data_from_src(mem_source.aw),
        .ready_to_src(mem_source.awready),

        .enable_to_dst(mem_sink.awvalid),
        .data_to_dst(mem_sink.aw),
        .ready_from_dst(mem_sink.awready)
        );

    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(mem_source.T_W_WIDTH)
        )
      mem_w_skid
       (
        .clk,
        .reset_n,

        .enable_from_src(mem_source.wvalid),
        .data_from_src(mem_source.w),
        .ready_to_src(mem_source.wready),

        .enable_to_dst(mem_sink.wvalid),
        .data_to_dst(mem_sink.w),
        .ready_from_dst(mem_sink.wready)
        );

    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(mem_source.T_B_WIDTH)
        )
      mem_b_skid
       (
        .clk,
        .reset_n,

        .enable_from_src(mem_sink.bvalid),
        .data_from_src(mem_sink.b),
        .ready_to_src(mem_sink.bready),

        .enable_to_dst(mem_source.bvalid),
        .data_to_dst(mem_source.b),
        .ready_from_dst(mem_source.bready)
        );

    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(mem_source.T_AR_WIDTH)
        )
      mem_ar_skid
       (
        .clk,
        .reset_n,

        .enable_from_src(mem_source.arvalid),
        .data_from_src(mem_source.ar),
        .ready_to_src(mem_source.arready),

        .enable_to_dst(mem_sink.arvalid),
        .data_to_dst(mem_sink.ar),
        .ready_from_dst(mem_sink.arready)
        );

    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(mem_source.T_R_WIDTH)
        )
      mem_r_skid
       (
        .clk,
        .reset_n,

        .enable_from_src(mem_sink.rvalid),
        .data_from_src(mem_sink.r),
        .ready_to_src(mem_sink.rready),

        .enable_to_dst(mem_source.rvalid),
        .data_to_dst(mem_source.r),
        .ready_from_dst(mem_source.rready)
        );

endmodule // ofs_plat_axi_mem_if_skid
