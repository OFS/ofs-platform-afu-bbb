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

module ofs_plat_axi_mem_lite_if_skid
  #(
    // Enable skid (1) or just connect as wires (0)?
    parameter SKID_AW = 1,
    parameter SKID_W = 1,
    parameter SKID_B = 1,
    parameter SKID_AR = 1,
    parameter SKID_R = 1
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

    generate
        if (SKID_AW)
        begin : sk_aw
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
        end
        else
        begin : c_aw
            assign mem_source.awready = mem_sink.awready;
            assign mem_sink.awvalid = mem_source.awvalid;
            assign mem_sink.aw = mem_source.aw;
        end

        if (SKID_W)
        begin : sk_w
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
        end
        else
        begin : c_w
            assign mem_source.wready = mem_sink.wready;
            assign mem_sink.wvalid = mem_source.wvalid;
            assign mem_sink.w = mem_source.w;
        end

        if (SKID_B)
        begin : sk_b
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
        end
        else
        begin : c_b
            assign mem_sink.bready = mem_source.bready;
            assign mem_source.bvalid = mem_sink.bvalid;
            assign mem_source.b = mem_sink.b;
        end

        if (SKID_AR)
        begin : sk_ar
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
        end
        else
        begin : c_ar
            assign mem_source.arready = mem_sink.arready;
            assign mem_sink.arvalid = mem_source.arvalid;
            assign mem_sink.ar = mem_source.ar;
        end

        if (SKID_R)
        begin : sk_r
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
        end
        else
        begin : c_r
            assign mem_sink.rready = mem_source.rready;
            assign mem_source.rvalid = mem_sink.rvalid;
            assign mem_source.r = mem_sink.r;
        end
    endgenerate

endmodule // ofs_plat_axi_mem_lite_if_skid
