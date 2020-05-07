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
// Export a CCI-P native host_chan interface to an AFU as AXI interfaces.
// There are three AXI interfaces: host memory master, MMIO (FPGA memory
// slave) and write-only MMIO slave. The write-only variant can be useful
// for 512 bit MMIO. CCI-P supports wide MMIO write but not read.
//

`include "ofs_plat_if.vh"

//
// There are three public variants:
//  - ofs_plat_host_chan_@group@_as_axi_mem - host memory only.
//  - ofs_plat_host_chan_@group@_as_axi_mem_with_mmio - host memory and
//    a single read/write MMIO interface.
//  - ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio - host memory,
//    read/write MMIO and a second write-only MMIO interface.
//

//
// Host memory as AXI memory (no MMIO).
//
module ofs_plat_host_chan_@group@_as_axi_mem
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
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

    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_plat_host_ccip_if ccip_mmio();

    ofs_plat_host_chan_@group@_as_axi_mem_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .ccip_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Tie off MMIO
    assign ccip_mmio.sTx = t_if_ccip_Tx'(0);

endmodule // ofs_plat_host_chan_@group@_as_axi_mem


//
// Host memory and FPGA MMIO master as AXI. The width of the MMIO
// port is determined by the parameters bound to mmio_to_afu.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
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

    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_slave_clk mmio_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_plat_host_ccip_if ccip_mmio();

    ofs_plat_host_chan_@group@_as_axi_mem_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .ccip_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Internal MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      mmio_if();

    // Do the CCI-P MMIO to AXI mapping
    ofs_plat_map_ccip_as_axi_mmio
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_@group@_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      axi_host_mmio
       (
        .to_fiu(ccip_mmio),
        .mmio_to_afu(mmio_if),

        .afu_clk(host_mem_to_afu.clk),
        .afu_reset_n(host_mem_to_afu.reset_n)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_axi_mem_lite_if_reg_master_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio
       (
        .mem_master(mmio_if),
        .mem_slave(mmio_to_afu)
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_mmio


//
// Host memory, FPGA MMIO master and a second write-only MMIO as AXI.
// The widths of the MMIO ports are determined by the interface parameters
// to mmio_to_afu and mmio_wr_to_afu.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
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

    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_slave_clk mmio_to_afu,
    ofs_plat_axi_mem_lite_if.to_slave_clk mmio_wr_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_plat_host_ccip_if ccip_mmio();

    ofs_plat_host_chan_@group@_as_axi_mem_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .ccip_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Internal MMIO AXI lite interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      mmio_if();

    // Do the CCI-P MMIO to AXI mapping
    ofs_plat_map_ccip_as_axi_mmio
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_@group@_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      axi_host_mmio
       (
        .to_fiu(ccip_mmio),
        .mmio_to_afu(mmio_if),

        .afu_clk(host_mem_to_afu.clk),
        .afu_reset_n(host_mem_to_afu.reset_n)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_axi_mem_lite_if_reg_master_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio
       (
        .mem_master(mmio_if),
        .mem_slave(mmio_to_afu)
        );

    // Internal second (write only) MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_wr_to_afu)
        )
      mmio_wr_if();

    // Do the CCI-P MMIO to AXI mapping
    ofs_plat_map_ccip_as_axi_mmio_wo
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_@group@_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      axi_host_mmio_wr
       (
        .to_fiu(ccip_mmio),
        .mmio_to_afu(mmio_wr_if),

        .afu_clk(host_mem_to_afu.clk),
        .afu_reset_n(host_mem_to_afu.reset_n)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_axi_mem_lite_if_reg_master_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio_wr
       (
        .mem_master(mmio_wr_if),
        .mem_slave(mmio_wr_to_afu)
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio


// ========================================================================
//
//  Internal implementation.
//
// ========================================================================

//
// Map CCI-P to target clock and then to the host memory AXI interface.
// Also return the CCI-P ports needed for mapping MMIO to AXI.
//
module ofs_plat_host_chan_@group@_as_axi_mem_impl
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
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

    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,

    // Export a CCI-P port for MMIO mapping
    ofs_plat_host_ccip_if.to_afu ccip_mmio,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    //
    // Split CCI-P into separate host memory and MMIO interfaces.
    //
    ofs_plat_host_ccip_if host_mem_ccip_if();
    ofs_plat_shim_ccip_split_mmio split_mmio
       (
        .to_fiu,
        .host_mem(host_mem_ccip_if),
        .mmio(ccip_mmio)
        );

    //
    // Now we can map to AXI.
    //
    ofs_plat_map_ccip_as_axi_host_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_ACTIVE_RD_LINES(ccip_@group@_cfg_pkg::C0_MAX_BW_ACTIVE_LINES[0]),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      axi_host_mem
       (
        .to_fiu(host_mem_ccip_if),
        .host_mem_to_afu,
        .afu_clk,
        .afu_reset_n
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem
