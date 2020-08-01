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
    ofs_plat_axi_mem_if.to_slave mem_slave,
    ofs_plat_axi_mem_if.to_master mem_master
    );

    logic clk;
    assign clk = mem_master.clk;
    logic reset_n;
    assign reset_n = mem_master.reset_n;

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_slave, mem_master)
    // synthesis translate_on

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

endmodule // ofs_plat_axi_mem_if_skid
