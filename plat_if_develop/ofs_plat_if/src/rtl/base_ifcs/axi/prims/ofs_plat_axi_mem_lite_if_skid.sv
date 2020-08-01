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
    ofs_plat_axi_mem_lite_if.to_slave mem_slave,
    ofs_plat_axi_mem_lite_if.to_master mem_master
    );

    logic clk;
    assign clk = mem_master.clk;
    logic reset_n;
    assign reset_n = mem_master.reset_n;

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(mem_slave, mem_master)
    // synthesis translate_on

    generate
        if (SKID_AW)
        begin : sk_aw
            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_master.T_AW_WIDTH)
                )
            mem_aw_skid
              (
               .clk,
               .reset_n,

               .enable_from_src(mem_master.awvalid),
               .data_from_src(mem_master.aw),
               .ready_to_src(mem_master.awready),

               .enable_to_dst(mem_slave.awvalid),
               .data_to_dst(mem_slave.aw),
               .ready_from_dst(mem_slave.awready)
               );
        end
        else
        begin : c_aw
            assign mem_master.awready = mem_slave.awready;
            assign mem_slave.awvalid = mem_master.awvalid;
            assign mem_slave.aw = mem_master.aw;
        end

        if (SKID_W)
        begin : sk_w
            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_master.T_W_WIDTH)
                )
            mem_w_skid
              (
               .clk,
               .reset_n,

               .enable_from_src(mem_master.wvalid),
               .data_from_src(mem_master.w),
               .ready_to_src(mem_master.wready),

               .enable_to_dst(mem_slave.wvalid),
               .data_to_dst(mem_slave.w),
               .ready_from_dst(mem_slave.wready)
               );
        end
        else
        begin : c_w
            assign mem_master.wready = mem_slave.wready;
            assign mem_slave.wvalid = mem_master.wvalid;
            assign mem_slave.w = mem_master.w;
        end

        if (SKID_B)
        begin : sk_b
            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_master.T_B_WIDTH)
                )
            mem_b_skid
              (
               .clk,
               .reset_n,

               .enable_from_src(mem_slave.bvalid),
               .data_from_src(mem_slave.b),
               .ready_to_src(mem_slave.bready),

               .enable_to_dst(mem_master.bvalid),
               .data_to_dst(mem_master.b),
               .ready_from_dst(mem_master.bready)
               );
        end
        else
        begin : c_b
            assign mem_slave.bready = mem_master.bready;
            assign mem_master.bvalid = mem_slave.bvalid;
            assign mem_master.b = mem_slave.b;
        end

        if (SKID_AR)
        begin : sk_ar
            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_master.T_AR_WIDTH)
                )
            mem_ar_skid
              (
               .clk,
               .reset_n,

               .enable_from_src(mem_master.arvalid),
               .data_from_src(mem_master.ar),
               .ready_to_src(mem_master.arready),

               .enable_to_dst(mem_slave.arvalid),
               .data_to_dst(mem_slave.ar),
               .ready_from_dst(mem_slave.arready)
               );
        end
        else
        begin : c_ar
            assign mem_master.arready = mem_slave.arready;
            assign mem_slave.arvalid = mem_master.arvalid;
            assign mem_slave.ar = mem_master.ar;
        end

        if (SKID_R)
        begin : sk_r
            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_master.T_R_WIDTH)
                )
            mem_r_skid
              (
               .clk,
               .reset_n,

               .enable_from_src(mem_slave.rvalid),
               .data_from_src(mem_slave.r),
               .ready_to_src(mem_slave.rready),

               .enable_to_dst(mem_master.rvalid),
               .data_to_dst(mem_master.r),
               .ready_from_dst(mem_master.rready)
               );
        end
        else
        begin : c_r
            assign mem_slave.rready = mem_master.rready;
            assign mem_master.rvalid = mem_slave.rvalid;
            assign mem_master.r = mem_slave.r;
        end
    endgenerate

endmodule // ofs_plat_axi_mem_lite_if_skid
