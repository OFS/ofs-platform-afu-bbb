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

//
// Clock crossing for all five AXI memory channels. This shim does no credit
// management.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_lite_if_async_shim
  #(
    // Extra pipeline stages without flow control added on input to each FIFO
    // to relax timing. FIFO buffer space is reserved to store requests that
    // arrive after almost full is asserted. This is all managed internally.
    parameter ADD_TIMING_REG_STAGES = 2,

    // If the master guarantees to reserve space for all responses then the
    // ready signals on slave responses pipelines can be ignored, perhaps
    // improving timing.
    parameter SLAVE_RESPONSES_ALWAYS_READY = 0
    )
   (
    ofs_plat_axi_mem_lite_if.to_slave mem_slave,
    ofs_plat_axi_mem_lite_if.to_master mem_master
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(mem_slave, mem_master)
    // synthesis translate_on

    logic master_reset_n;
    ofs_plat_prim_clock_crossing_reset_async m_reset_n
       (
        .clk(mem_master.clk),
        .reset_in(mem_master.reset_n),
        .reset_out(master_reset_n)
        );

    logic slave_reset_n;
    ofs_plat_prim_clock_crossing_reset_async s_reset_n
       (
        .clk(mem_slave.clk),
        .reset_in(mem_slave.reset_n),
        .reset_out(slave_reset_n)
        );

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_slave.T_AW_WIDTH)
        )
      aw
       (
        .clk_in(mem_master.clk),
        .reset_n_in(master_reset_n),

        .ready_in(mem_master.awready),
        .valid_in(mem_master.awvalid),
        .data_in(mem_master.aw),

        .clk_out(mem_slave.clk),
        .reset_n_out(slave_reset_n),

        .ready_out(mem_slave.awready),
        .valid_out(mem_slave.awvalid),
        .data_out(mem_slave.aw)
        );

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_slave.T_W_WIDTH)
        )
      w
       (
        .clk_in(mem_master.clk),
        .reset_n_in(master_reset_n),

        .ready_in(mem_master.wready),
        .valid_in(mem_master.wvalid),
        .data_in(mem_master.w),

        .clk_out(mem_slave.clk),
        .reset_n_out(slave_reset_n),

        .ready_out(mem_slave.wready),
        .valid_out(mem_slave.wvalid),
        .data_out(mem_slave.w)
        );


    logic slave_bready;
    assign mem_slave.bready = (SLAVE_RESPONSES_ALWAYS_READY ? 1'b1 : slave_bready);

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(SLAVE_RESPONSES_ALWAYS_READY ? ADD_TIMING_REG_STAGES : 0),
        .ADD_TIMING_READY_STAGES(0),
        .READY_FROM_ALMOST_FULL(0),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_slave.T_B_WIDTH)
        )
      b
       (
        .clk_in(mem_slave.clk),
        .reset_n_in(slave_reset_n),

        .ready_in(slave_bready),
        .valid_in(mem_slave.bvalid),
        .data_in(mem_slave.b),

        .clk_out(mem_master.clk),
        .reset_n_out(master_reset_n),

        .ready_out(mem_master.bready),
        .valid_out(mem_master.bvalid),
        .data_out(mem_master.b)
        );


    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_slave.T_AR_WIDTH)
        )
      ar
       (
        .clk_in(mem_master.clk),
        .reset_n_in(master_reset_n),

        .ready_in(mem_master.arready),
        .valid_in(mem_master.arvalid),
        .data_in(mem_master.ar),

        .clk_out(mem_slave.clk),
        .reset_n_out(slave_reset_n),

        .ready_out(mem_slave.arready),
        .valid_out(mem_slave.arvalid),
        .data_out(mem_slave.ar)
        );

    logic slave_rready;
    assign mem_slave.rready = (SLAVE_RESPONSES_ALWAYS_READY ? 1'b1 : slave_rready);

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(SLAVE_RESPONSES_ALWAYS_READY ? ADD_TIMING_REG_STAGES : 0),
        .ADD_TIMING_READY_STAGES(0),
        .READY_FROM_ALMOST_FULL(0),
        .N_ENTRIES(16),
        .DATA_WIDTH(mem_slave.T_R_WIDTH)
        )
      r
       (
        .clk_in(mem_slave.clk),
        .reset_n_in(slave_reset_n),

        .ready_in(slave_rready),
        .valid_in(mem_slave.rvalid),
        .data_in(mem_slave.r),

        .clk_out(mem_master.clk),
        .reset_n_out(master_reset_n),

        .ready_out(mem_master.rready),
        .valid_out(mem_master.rvalid),
        .data_out(mem_master.r)
        );

endmodule // ofs_plat_axi_mem_lite_if_async_shim


// Same as standard crossing, but set the slave's clock
module ofs_plat_axi_mem_lite_if_async_shim_set_slave
  #(
    parameter ADD_TIMING_REG_STAGES = 2,
    parameter SLAVE_RESPONSES_ALWAYS_READY = 0
    )
   (
    ofs_plat_axi_mem_lite_if.to_slave_clk mem_slave,
    ofs_plat_axi_mem_lite_if.to_master mem_master,

    input  logic slave_clk,
    input  logic slave_reset_n
    );

    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mem_slave)
        )
      mem_slave_with_clk();

    assign mem_slave_with_clk.clk = slave_clk;
    assign mem_slave_with_clk.reset_n = slave_reset_n;
    assign mem_slave_with_clk.instance_number = mem_master.instance_number;

    ofs_plat_axi_mem_lite_if_connect_master_clk con_slave
       (
        .mem_master(mem_slave_with_clk),
        .mem_slave
        );

    ofs_plat_axi_mem_lite_if_async_shim
      #(
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SLAVE_RESPONSES_ALWAYS_READY(SLAVE_RESPONSES_ALWAYS_READY)
        )
      cc
       (
        .mem_slave(mem_slave_with_clk),
        .mem_master
        );

endmodule // ofs_plat_axi_mem_lite_if_async_shim_set_slave
