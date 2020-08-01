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
// Export a PCIe TLP native host_chan interface to an AFU as AXI interfaces.
// There are three AXI interfaces: host memory master, MMIO (FPGA memory
// slave) and write-only MMIO slave. The write-only variant can be useful
// for 512 bit MMIO.
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
    // When non-zero, add a clock crossing to move the AFU
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
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Internal dummy MMIO AXI interfaces. They are required by the
    // internal mapper but will be dropped by Quartus.
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_@GROUP@_AXI_MMIO_PARAMS(64)
        )
      axi_mmio();

    assign axi_mmio.clk = host_mem_to_afu.clk;
    assign axi_mmio.reset_n = host_mem_to_afu.reset_n;
    assign axi_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_@GROUP@_AXI_MMIO_PARAMS(64)
        )
      axi_wo_mmio();

    assign axi_wo_mmio.clk = host_mem_to_afu.clk;
    assign axi_wo_mmio.reset_n = host_mem_to_afu.reset_n;
    assign axi_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_axi_mem_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .axi_mmio,
        .axi_wo_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Tie off MMIO
    always_comb
    begin
        axi_mmio.awready = 1'b1;
        axi_mmio.wready = 1'b1;
        axi_mmio.bvalid = 1'b0;
        axi_mmio.arready = 1'b1;
        axi_mmio.rvalid = 1'b0;

        axi_wo_mmio.awready = 1'b1;
        axi_wo_mmio.wready = 1'b1;
        axi_wo_mmio.bvalid = 1'b0;
        axi_wo_mmio.arready = 1'b1;
        axi_wo_mmio.rvalid = 1'b0;
    end

endmodule // ofs_plat_host_chan_@group@_as_axi_mem


//
// Host memory and FPGA MMIO master as AXI. The width of the MMIO
// port is determined by the parameters bound to mmio_to_afu.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU
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
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_slave_clk mmio_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Internal MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      axi_mmio();

    assign axi_mmio.clk = to_fiu.clk;
    assign axi_mmio.reset_n = to_fiu.reset_n;
    assign axi_mmio.instance_number = to_fiu.instance_number;

    // Internal dummy MMIO write only AXI interface. It is required
    // by the internal mapper but will be dropped by Quartus.
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_@GROUP@_AXI_MMIO_PARAMS(64)
        )
      axi_wo_mmio();

    assign axi_wo_mmio.clk = to_fiu.clk;
    assign axi_wo_mmio.reset_n = to_fiu.reset_n;
    assign axi_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_axi_mem_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .axi_mmio,
        .axi_wo_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Add clock crossing or register stages, as requested.
    // Force an extra one for timing.
    generate
        if (ADD_CLOCK_CROSSING)
        begin : cc
            ofs_plat_axi_mem_lite_if_async_shim_set_slave
              #(
                .ADD_TIMING_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              cc_mmio
               (
                .mem_master(axi_mmio),
                .mem_slave(mmio_to_afu),
                .slave_clk(host_mem_to_afu.clk),
                .slave_reset_n(host_mem_to_afu.reset_n)
                );
        end
        else
        begin : nc
            ofs_plat_axi_mem_lite_if_reg_master_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_master(axi_mmio),
                .mem_slave(mmio_to_afu)
                );
        end
    endgenerate


    // Tie off dummy write-only MMIO
    always_comb
    begin
        axi_wo_mmio.awready = 1'b1;
        axi_wo_mmio.wready = 1'b1;
        axi_wo_mmio.bvalid = 1'b0;
        axi_wo_mmio.arready = 1'b1;
        axi_wo_mmio.rvalid = 1'b0;
    end

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_mmio


//
// Host memory, FPGA MMIO master and a second write-only MMIO as AXI.
// The widths of the MMIO ports are determined by the interface parameters
// to mmio_to_afu and mmio_wr_to_afu.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU
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
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_slave_clk mmio_to_afu,
    ofs_plat_axi_mem_lite_if.to_slave_clk mmio_wr_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Internal MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      axi_mmio();

    assign axi_mmio.clk = to_fiu.clk;
    assign axi_mmio.reset_n = to_fiu.reset_n;
    assign axi_mmio.instance_number = to_fiu.instance_number;

    // Internal write-only MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_wr_to_afu)
        )
      axi_wo_mmio();

    assign axi_wo_mmio.clk = to_fiu.clk;
    assign axi_wo_mmio.reset_n = to_fiu.reset_n;
    assign axi_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_axi_mem_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .axi_mmio,
        .axi_wo_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Add clock crossing or register stages, as requested.
    // Force an extra one for timing.
    generate
        if (ADD_CLOCK_CROSSING)
        begin : cc
            ofs_plat_axi_mem_lite_if_async_shim_set_slave
              #(
                .ADD_TIMING_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              cc_mmio
               (
                .mem_master(axi_mmio),
                .mem_slave(mmio_to_afu),
                .slave_clk(host_mem_to_afu.clk),
                .slave_reset_n(host_mem_to_afu.reset_n)
                );

            ofs_plat_axi_mem_lite_if_async_shim_set_slave
              #(
                .ADD_TIMING_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              cc_mmio_wo
               (
                .mem_master(axi_wo_mmio),
                .mem_slave(mmio_wr_to_afu),
                .slave_clk(host_mem_to_afu.clk),
                .slave_reset_n(host_mem_to_afu.reset_n)
                );
        end
        else
        begin : nc
            ofs_plat_axi_mem_lite_if_reg_master_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_master(axi_mmio),
                .mem_slave(mmio_to_afu)
                );

            ofs_plat_axi_mem_lite_if_reg_master_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio_wo
               (
                .mem_master(axi_wo_mmio),
                .mem_slave(mmio_wr_to_afu)
                );
        end
    endgenerate

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio


// ========================================================================
//
//  Internal implementation.
//
// ========================================================================

//
// Map AXI-MM to target clock and then to the host memory PCIe TLP
// interface.
//
module ofs_plat_host_chan_@group@_as_axi_mem_impl
  #(
    // When non-zero, add a clock crossing to move the AFU interfaces
    // to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,

    // Export an AXI lite port for MMIO mapping
    ofs_plat_axi_mem_lite_if.to_slave axi_mmio,
    // Export a second AXI lite port for MMIO write-only mapping. This
    // may be used when the AFU will receive wide MMIO writes but only
    // respond with narrow (e.g. 64 bit) MMIO reads.
    ofs_plat_axi_mem_lite_if.to_slave axi_wo_mmio,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    parameter int MAX_BW_ACTIVE_RD_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_RD /
                      ofs_plat_host_chan_@group@_gen_tlps_pkg::NUM_PIM_PCIE_TLP_CH;
    parameter int MAX_BW_ACTIVE_WR_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_WR /
                      ofs_plat_host_chan_@group@_gen_tlps_pkg::NUM_PIM_PCIE_TLP_CH;

    // ====================================================================
    //  Bind the proper clock to the AFU interface. If there is no clock
    //  crossing requested then it's just the FIU clock.
    // ====================================================================

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      axi_afu_clk_if();

    assign axi_afu_clk_if.clk = (ADD_CLOCK_CROSSING == 0) ? to_fiu.clk : afu_clk;
    assign axi_afu_clk_if.reset_n = (ADD_CLOCK_CROSSING == 0) ? to_fiu.reset_n : afu_reset_n;
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


    // ====================================================================
    //  Cross to the FIU clock, sort responses and map bursts to FIU sizes.
    // ====================================================================

    // ofs_plat_axi_mem_if_async_rob records the ROB indices of read and
    // write requests in ID fields. The original values are recorded in the
    // ROB and returned to the master.
    localparam ROB_RID_WIDTH = $clog2(MAX_BW_ACTIVE_RD_LINES);
    localparam ROB_WID_WIDTH = $clog2(MAX_BW_ACTIVE_WR_LINES);

    // Maximum burst that fits in the largest allowed TLP packet
    localparam FIU_BURST_CNT_MAX = ofs_plat_host_chan_@group@_pcie_tlp_pkg::MAX_PAYLOAD_SIZE /
                                   host_mem_to_afu.DATA_WIDTH_;

    ofs_plat_axi_mem_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(host_mem_to_afu),
        .BURST_CNT_WIDTH($clog2(FIU_BURST_CNT_MAX)),
        .USER_WIDTH(host_mem_to_afu.USER_WIDTH_),
        .RID_WIDTH(ROB_RID_WIDTH),
        .WID_WIDTH(ROB_WID_WIDTH)
        )
      axi_fiu_clk_if();

    assign axi_fiu_clk_if.clk = to_fiu.clk;
    assign axi_fiu_clk_if.reset_n = to_fiu.reset_n;
    assign axi_fiu_clk_if.instance_number = to_fiu.instance_number;

    // The AXI interface is always sorted here, despite the AXI bus not
    // requiring sorted responses. We do this because large AXI bursts are
    // broken into smaller PCIe TLP bursts. These smaller PCIe bursts
    // might be reordered by the PCIe network. AXI requires that
    // responses for a single request be returned in order. In order
    // to guarantee this, we sort responses.
    ofs_plat_map_axi_mem_if_to_host_mem
      #(
        // Temporarily use natural alignment until we deal with 4KB
        // page crossings.
        .NATURAL_ALIGNMENT(1),
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_ACTIVE_RD_LINES(MAX_BW_ACTIVE_RD_LINES),
        .MAX_ACTIVE_WR_LINES(MAX_BW_ACTIVE_WR_LINES)
        )
      rob
       (
        .mem_master(axi_afu_clk_if),
        .mem_slave(axi_fiu_clk_if)
        );


    // ====================================================================
    //  Basic mapping from AXI-MM to TLPs, all in the FIU clock domain.
    // ====================================================================

    // The AXI-MM interface (axi_fiu_clk_if) is in the FIU domain and
    // bursts are sized properly for PCIe. All that remains is to map
    // AXI-MM bursts to PCIe TLP.

    ofs_plat_host_chan_@group@_map_as_axi_mem_if tlp_as_axi_mem
       (
        .mem_master(axi_fiu_clk_if),
        .mmio_slave(axi_mmio),
        .mmio_wo_slave(axi_wo_mmio),
        .to_fiu_tlp(to_fiu)
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem
