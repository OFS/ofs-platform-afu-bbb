//
// Copyright (c) 2019, Intel Corporation
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
// Map CCI-P host memory traffic to an AXI channel.
//
module ofs_plat_map_ccip_as_axi_host_mem
  #(
    // When non-zero, add a clock crossing to move the AXI
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Sizes of the response buffers in the ROB and clock crossing.
    parameter MAX_ACTIVE_RD_LINES = 256,
    parameter MAX_ACTIVE_WR_LINES = 256,

    // Does this platform's CCI-P implementation support byte write ranges?
    parameter BYTE_EN_SUPPORTED = 1,

    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    // CCI-P interface to FIU
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Generated AXI host memory interface
    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,

    // Used for AFU clock/reset_n when ADD_CLOCK_CROSSING is nonzero
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    logic clk;
    assign clk = to_fiu.clk;

    logic reset_n;
    assign reset_n = to_fiu.reset_n;

    t_if_ccip_Rx sRx;
    assign sRx = to_fiu.sRx;


    // ====================================================================
    //
    //  Begin with the AFU connection (host_mem_to_afu) and work down
    //  toward the FIU.
    //
    // ====================================================================

    //
    // Bind the proper clock to the AFU interface. If there is no clock
    // crossing requested then it's just the FIU CCI-P clock.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      axi_afu_clk_if();

    assign axi_afu_clk_if.clk = (ADD_CLOCK_CROSSING == 0) ? clk : afu_clk;
    assign axi_afu_clk_if.reset_n = (ADD_CLOCK_CROSSING == 0) ? reset_n : afu_reset_n;
    assign axi_afu_clk_if.instance_number = to_fiu.instance_number;

    // synthesis translate_off
    always_ff @(negedge axi_afu_clk_if.clk)
    begin
        if (axi_afu_clk_if.reset_n === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: axi_afu_clk_if.reset_n port is uninitialized!");
        end
    end
    // synthesis translate_on

    ofs_plat_axi_mem_if_connect_slave_clk
      conn_afu_clk
       (
        .mem_master(host_mem_to_afu),
        .mem_slave(axi_afu_clk_if)
        );

    //
    // Map AXI master to Avalon split-bus read/write slave.
    //

    // Larger of RID/WID
    localparam ID_WIDTH = (host_mem_to_afu.RID_WIDTH > host_mem_to_afu.WID_WIDTH) ?
                          host_mem_to_afu.RID_WIDTH : host_mem_to_afu.WID_WIDTH;
    // Avalon user width must hold AXI "id" and "user" fields
    localparam AVMM_USER_WIDTH = host_mem_to_afu.USER_WIDTH + 1 + ID_WIDTH;

    ofs_plat_avalon_mem_rdwr_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        .ADDR_WIDTH(host_mem_to_afu.ADDR_LINE_IDX_WIDTH),
        .DATA_WIDTH(host_mem_to_afu.DATA_WIDTH_),
        .MASKED_SYMBOL_WIDTH(host_mem_to_afu.MASKED_SYMBOL_WIDTH_),
        .BURST_CNT_WIDTH(host_mem_to_afu.BURST_CNT_WIDTH_ + 1),
        .USER_WIDTH(AVMM_USER_WIDTH)
        )
      avmm_rdwr_if();

    ofs_plat_axi_mem_if_to_avalon_rdwr_if
      #(
        .GEN_RD_RESPONSE_METADATA(1),
        .RD_RESPONSE_FIFO_DEPTH(MAX_ACTIVE_RD_LINES)
        )
      axi_to_avmm_rdwr
       (
        .axi_master(axi_afu_clk_if),
        .avmm_slave(avmm_rdwr_if)
        );

    //
    // Now use the Avalon path to CCI-P.
    //
    ofs_plat_map_ccip_as_avalon_host_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_ACTIVE_RD_LINES(MAX_ACTIVE_RD_LINES),
        .MAX_ACTIVE_WR_LINES(MAX_ACTIVE_WR_LINES),
        .BYTE_EN_SUPPORTED(BYTE_EN_SUPPORTED),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      avmm_rdwr_to_ccip
       (
        .to_fiu,
        .host_mem_to_afu(avmm_rdwr_if),
        .afu_clk,
        .afu_reset_n
        );

endmodule // ofs_plat_map_ccip_as_axi_host_mem
