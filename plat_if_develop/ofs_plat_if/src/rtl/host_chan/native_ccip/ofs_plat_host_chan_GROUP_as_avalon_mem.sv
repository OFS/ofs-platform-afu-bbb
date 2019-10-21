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

//
// Export a CCI-P native host_chan interface to an AFU as Avalon interfaces.
// There are three Avalon interfaces: host memory master, MMIO (FPGA memory
// slave) and write-only MMIO slave. The write-only variant can be useful
// for 512 bit MMIO. CCI-P supports wide MMIO write but not read.
//

`include "ofs_plat_if.vh"

//
// There are three public variants:
//  - ofs_plat_host_chan_GROUP_as_avalon_mem - host memory only.
//  - ofs_plat_host_chan_GROUP_as_avalon_mem_with_mmio - host memory and
//    a single read/write MMIO interface.
//  - ofs_plat_host_chan_GROUP_as_avalon_mem_with_dual_mmio - host memory,
//    read/write MMIO and a second write-only MMIO interface.
//

//
// Host memory as Avalon (no MMIO).
//
module ofs_plat_host_chan_GROUP_as_avalon_mem
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset pair passed in afu_clk/afu_reset.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_master_clk host_mem_to_afu,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,

    // Map pwrState to the target clock domain.
    input  t_ofs_plat_power_state fiu_pwrState,
    output t_ofs_plat_power_state afu_pwrState
    );

    ofs_plat_host_chan_GROUP_as_avalon_mem_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .sRx(),
        .c2Tx(t_if_ccip_c2_Tx'(0)),
        .afu_clk,
        .fiu_pwrState,
        .afu_pwrState
        );

endmodule // ofs_plat_host_chan_GROUP_as_avalon_mem


//
// Host memory and FPGA MMIO master as Avalon. The width of the MMIO
// port is determined by the parameters bound to mmio_to_afu.
//
module ofs_plat_host_chan_GROUP_as_avalon_mem_with_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset pair passed in afu_clk/afu_reset.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_master_clk host_mem_to_afu,
    ofs_plat_avalon_mem_if.to_slave_clk mmio_to_afu,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,

    // Map pwrState to the target clock domain.
    input  t_ofs_plat_power_state fiu_pwrState,
    output t_ofs_plat_power_state afu_pwrState
    );

    logic clk;
    assign clk = host_mem_to_afu.clk;
    logic reset;
    assign reset = host_mem_to_afu.reset;

    t_if_ccip_Rx sRx;
    t_if_ccip_c2_Tx c2Tx;

    ofs_plat_host_chan_GROUP_as_avalon_mem_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .sRx,
        .c2Tx,
        .afu_clk,
        .fiu_pwrState,
        .afu_pwrState
        );

    // Internal MMIO Avalon interface
    ofs_plat_avalon_mem_if
      #(
        .ADDR_WIDTH(mmio_to_afu.ADDR_WIDTH_),
        .DATA_WIDTH(mmio_to_afu.DATA_WIDTH_),
        .BURST_CNT_WIDTH(mmio_to_afu.BURST_CNT_WIDTH_)
        )
      mmio_if();

    // Do the CCI-P MMIO to Avalon mapping
    ofs_plat_map_ccip_as_avalon_mmio
      #(
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_GROUP_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      av_host_mmio
       (
        .clk,
        .reset,
        .sRx,
        .c2Tx,
        .mmio_to_afu(mmio_if)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_avalon_mem_if_reg_master_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio
       (
        .mem_master(mmio_if),
        .mem_slave(mmio_to_afu)
        );

endmodule // ofs_plat_host_chan_GROUP_as_avalon_mem_with_mmio


//
// Host memory, FPGA MMIO master and a second write-only MMIO as Avalon.
// The widths of the MMIO ports are determined by the interface parameters
// to mmio_to_afu and mmio_wr_to_afu.
//
module ofs_plat_host_chan_GROUP_as_avalon_mem_with_dual_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset pair passed in afu_clk/afu_reset.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_master_clk host_mem_to_afu,
    ofs_plat_avalon_mem_if.to_slave_clk mmio_to_afu,
    ofs_plat_avalon_mem_if.to_slave_clk mmio_wr_to_afu,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,

    // Map pwrState to the target clock domain.
    input  t_ofs_plat_power_state fiu_pwrState,
    output t_ofs_plat_power_state afu_pwrState
    );

    logic clk;
    assign clk = host_mem_to_afu.clk;
    logic reset;
    assign reset = host_mem_to_afu.reset;

    t_if_ccip_Rx sRx;
    t_if_ccip_c2_Tx c2Tx;

    ofs_plat_host_chan_GROUP_as_avalon_mem_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .sRx,
        .c2Tx,
        .afu_clk,
        .fiu_pwrState,
        .afu_pwrState
        );

    // Internal MMIO Avalon interface
    ofs_plat_avalon_mem_if
      #(
        .ADDR_WIDTH(mmio_to_afu.ADDR_WIDTH_),
        .DATA_WIDTH(mmio_to_afu.DATA_WIDTH_),
        .BURST_CNT_WIDTH(mmio_to_afu.BURST_CNT_WIDTH_)
        )
      mmio_if();

    // Do the CCI-P MMIO to Avalon mapping
    ofs_plat_map_ccip_as_avalon_mmio
      #(
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_GROUP_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      av_host_mmio
       (
        .clk,
        .reset,
        .sRx,
        .c2Tx,
        .mmio_to_afu(mmio_if)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_avalon_mem_if_reg_master_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio
       (
        .mem_master(mmio_if),
        .mem_slave(mmio_to_afu)
        );

    // Internal second (write only) MMIO Avalon interface
    ofs_plat_avalon_mem_if
      #(
        .ADDR_WIDTH(mmio_wr_to_afu.ADDR_WIDTH_),
        .DATA_WIDTH(mmio_wr_to_afu.DATA_WIDTH_),
        .BURST_CNT_WIDTH(mmio_wr_to_afu.BURST_CNT_WIDTH_)
        )
      mmio_wr_if();

    // Do the CCI-P MMIO to Avalon mapping
    ofs_plat_map_ccip_as_avalon_mmio
      #(
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_GROUP_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS),
        .WRITE_ONLY_MODE(1)
        )
      av_host_mmio_wr
       (
        .clk,
        .reset,
        .sRx,
        .c2Tx(),	// No writing to CCI-P in write only mode
        .mmio_to_afu(mmio_wr_if)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_avalon_mem_if_reg_master_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio_wr
       (
        .mem_master(mmio_wr_if),
        .mem_slave(mmio_wr_to_afu)
        );

endmodule // ofs_plat_host_chan_GROUP_as_avalon_mem_with_dual_mmio


// ========================================================================
//
//  Internal implementation.
//
// ========================================================================

//
// Map CCI-P to target clock and then to the host memory Avalon interface.
// Also return the CCI-P ports needed for mapping MMIO to Avalon.
//
module ofs_plat_host_chan_GROUP_as_avalon_mem_impl
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset pair passed in afu_clk/afu_reset.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_master_clk host_mem_to_afu,
    // These ports may be used for MMIO mapping
    output t_if_ccip_Rx sRx,
    input t_if_ccip_c2_Tx c2Tx,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,

    // Map pwrState to the target clock domain.
    input  t_ofs_plat_power_state fiu_pwrState,
    output t_ofs_plat_power_state afu_pwrState
    );

    //
    // Transform native CCI-P signals to the AFU's requested clock domain.
    //
    ofs_plat_host_ccip_if std_ccip_if();
    ofs_plat_host_chan_GROUP_as_ccip
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     afu_ccip
       (
        .to_fiu(to_fiu),
        .to_afu(std_ccip_if),
        .afu_clk,
        .fiu_pwrState,
        .afu_pwrState
        );

    //
    // Later stages depend on CCI-P write responses always being packed: a
    // single write response per multi-line write request. Make sure that
    // is true.
    //
    ofs_plat_host_ccip_if eop_ccip_if();
    ofs_plat_shim_ccip_detect_eop
      #(
        .MAX_ACTIVE_WR_REQS(ccip_GROUP_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0])
        )
      eop
       (
        .to_fiu(std_ccip_if),
        .to_afu(eop_ccip_if)
        );

    //
    // Sort write responses.
    //
    ofs_plat_host_ccip_if rob_wr_ccip_if();
    ofs_plat_shim_ccip_rob_wr
      #(
        .MAX_ACTIVE_WR_REQS(ccip_GROUP_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0])
        )
      rob_wr
       (
        .to_fiu(eop_ccip_if),
        .to_afu(rob_wr_ccip_if)
        );

    //
    // Sort read responses.
    //
    ofs_plat_host_ccip_if#(.LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)) sorted_ccip_if();
    ofs_plat_shim_ccip_rob_rd
      #(
        .MAX_ACTIVE_RD_REQS(ccip_GROUP_cfg_pkg::C0_MAX_BW_ACTIVE_LINES[0])
        )
      rob_rd
       (
        .to_fiu(rob_wr_ccip_if),
        .to_afu(sorted_ccip_if)
        );


    //
    // Now we can map to Avalon.
    //
    ofs_plat_map_ccip_as_avalon_host_mem av_host_mem
       (
        .clk(sorted_ccip_if.clk),
        .reset(sorted_ccip_if.reset),
        .instance_number(sorted_ccip_if.instance_number),
        .sRx(sorted_ccip_if.sRx),
        .c0Tx(sorted_ccip_if.sTx.c0),
        .c1Tx(sorted_ccip_if.sTx.c1),
        .host_mem_to_afu
        );

    // Expose the ports required to implement MMIO to Avalon mapping
    assign sRx = sorted_ccip_if.sRx;
    assign sorted_ccip_if.sTx.c2 = c2Tx;

endmodule // ofs_plat_host_chan_GROUP_as_avalon_mem
