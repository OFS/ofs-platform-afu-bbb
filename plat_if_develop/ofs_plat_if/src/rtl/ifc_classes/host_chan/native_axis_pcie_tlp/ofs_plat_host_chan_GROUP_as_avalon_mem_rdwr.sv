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
// Export a PCIe TLP native host_chan interface to an AFU as Avalon interfaces.
// There are three Avalon interfaces: host memory source, MMIO (FPGA memory
// sink) and write-only MMIO sink. The write-only variant can be useful
// for 512 bit MMIO. CCI-P supports wide MMIO write but not read.
//
// The extension rd_user field is returned as rd_readresponsuser, but only
// on the first read flit. The wr_user value is returned in
// wr_writeresponseuser. The low bits of wr_user that correspond to flags
// for fences and interrupts are not guaranteed to be returned as set
// in the request.
//

`include "ofs_plat_if.vh"

//
// There are three public variants:
//  - ofs_plat_host_chan_@group@_as_avalon_mem_rdwr - host memory only.
//  - ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_with_mmio - host memory and
//    a single read/write MMIO interface.
//  - ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_with_dual_mmio - host memory,
//    read/write MMIO and a second write-only MMIO interface.
//
// *** The bus size of Avalon-based MMIO is chosen by setting ADDR_WIDTH
// *** and DATA_WIDTH of the interface. See the .vh file corresponding
// *** to this module for details.
//

//
// Host memory as Avalon split-bus read/write (no MMIO).
//
module ofs_plat_host_chan_@group@_as_avalon_mem_rdwr
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
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_source_clk host_mem_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Internal dummy MMIO Avalon interfaces. They are required by the
    // internal mapper but will be dropped by Quartus.
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_@GROUP@_AVALON_MMIO_PARAMS(64)
        )
      avmm_mmio();

    assign avmm_mmio.clk = host_mem_to_afu.clk;
    assign avmm_mmio.reset_n = host_mem_to_afu.reset_n;
    assign avmm_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_@GROUP@_AVALON_MMIO_PARAMS(64)
        )
      avmm_wo_mmio();

    assign avmm_wo_mmio.clk = host_mem_to_afu.clk;
    assign avmm_wo_mmio.reset_n = host_mem_to_afu.reset_n;
    assign avmm_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .avmm_mmio,
        .avmm_wo_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Tie off MMIO
    always_comb
    begin
        avmm_mmio.waitrequest = 1'b0;
        avmm_mmio.readdatavalid = 1'b0;
        avmm_mmio.writeresponsevalid = 1'b0;

        avmm_wo_mmio.waitrequest = 1'b0;
        avmm_wo_mmio.readdatavalid = 1'b0;
        avmm_wo_mmio.writeresponsevalid = 1'b0;
    end

endmodule // ofs_plat_host_chan_@group@_as_avalon_mem_rdwr


//
// Host memory and FPGA MMIO source as Avalon. The width of the MMIO
// port is determined by the parameters bound to mmio_to_afu.
//
module ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_with_mmio
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
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_source_clk host_mem_to_afu,
    ofs_plat_avalon_mem_if.to_sink_clk mmio_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Internal MMIO Avalon interface
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      avmm_mmio();

    assign avmm_mmio.clk = to_fiu.clk;
    assign avmm_mmio.reset_n = to_fiu.reset_n;
    assign avmm_mmio.instance_number = to_fiu.instance_number;

    // Internal dummy MMIO write only Avalon interface. It is required
    // by the internal mapper but will be dropped by Quartus.
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_@GROUP@_AVALON_MMIO_PARAMS(64)
        )
      avmm_wo_mmio();

    assign avmm_wo_mmio.clk = to_fiu.clk;
    assign avmm_wo_mmio.reset_n = to_fiu.reset_n;
    assign avmm_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .avmm_mmio,
        .avmm_wo_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Add clock crossing or register stages, as requested.
    // Force an extra one for timing.
    generate
        if (ADD_CLOCK_CROSSING)
        begin : cc
            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio_to_afu)
                )
              avmm_mmio_afu_clk();

            ofs_plat_avalon_mem_if_async_shim_set_sink
              #(
                .COMMAND_FIFO_DEPTH(4),
                .RESPONSE_FIFO_DEPTH(ofs_plat_host_chan_@group@_pcie_tlp_pkg::MAX_OUTSTANDING_MMIO_RD_REQS),
                .PRESERVE_WR_RESP(0)
                )
              cc_mmio
               (
                .mem_source(avmm_mmio),
                .mem_sink(avmm_mmio_afu_clk),
                .sink_clk(host_mem_to_afu.clk),
                .sink_reset_n(host_mem_to_afu.reset_n)
                );

            ofs_plat_avalon_mem_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_source(avmm_mmio_afu_clk),
                .mem_sink(mmio_to_afu)
                );
        end
        else
        begin : nc
            ofs_plat_avalon_mem_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_source(avmm_mmio),
                .mem_sink(mmio_to_afu)
                );
        end
    endgenerate


    // Tie off dummy write-only MMIO
    always_comb
    begin
        avmm_wo_mmio.waitrequest = 1'b0;
        avmm_wo_mmio.readdatavalid = 1'b0;
        avmm_wo_mmio.writeresponsevalid = 1'b0;
    end

endmodule // ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_with_mmio


//
// Host memory, FPGA MMIO source and a second write-only MMIO as Avalon.
// The widths of the MMIO ports are determined by the interface parameters
// to mmio_to_afu and mmio_wr_to_afu.
//
module ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_with_dual_mmio
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
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_source_clk host_mem_to_afu,
    ofs_plat_avalon_mem_if.to_sink_clk mmio_to_afu,
    ofs_plat_avalon_mem_if.to_sink_clk mmio_wr_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Internal MMIO Avalon interface
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      avmm_mmio();

    assign avmm_mmio.clk = to_fiu.clk;
    assign avmm_mmio.reset_n = to_fiu.reset_n;
    assign avmm_mmio.instance_number = to_fiu.instance_number;

    // Internal write-only MMIO Avalon interface
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio_wr_to_afu)
        )
      avmm_wo_mmio();

    assign avmm_wo_mmio.clk = to_fiu.clk;
    assign avmm_wo_mmio.reset_n = to_fiu.reset_n;
    assign avmm_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .avmm_mmio,
        .avmm_wo_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Add clock crossing or register stages, as requested.
    // Force an extra one for timing.
    generate
        if (ADD_CLOCK_CROSSING)
        begin : cc
            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio_to_afu)
                )
              avmm_mmio_afu_clk();

            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio_wr_to_afu)
                )
              avmm_wo_mmio_afu_clk();

            ofs_plat_avalon_mem_if_async_shim_set_sink
              #(
                .COMMAND_FIFO_DEPTH(4),
                .RESPONSE_FIFO_DEPTH(ofs_plat_host_chan_@group@_pcie_tlp_pkg::MAX_OUTSTANDING_MMIO_RD_REQS),
                .PRESERVE_WR_RESP(0)
                )
              cc_mmio
               (
                .mem_source(avmm_mmio),
                .mem_sink(avmm_mmio_afu_clk),
                .sink_clk(host_mem_to_afu.clk),
                .sink_reset_n(host_mem_to_afu.reset_n)
                );

            ofs_plat_avalon_mem_if_async_shim_set_sink
              #(
                .COMMAND_FIFO_DEPTH(4),
                .RESPONSE_FIFO_DEPTH(ofs_plat_host_chan_@group@_pcie_tlp_pkg::MAX_OUTSTANDING_MMIO_RD_REQS),
                .PRESERVE_WR_RESP(0)
                )
              cc_mmio_wo
               (
                .mem_source(avmm_wo_mmio),
                .mem_sink(avmm_wo_mmio_afu_clk),
                .sink_clk(host_mem_to_afu.clk),
                .sink_reset_n(host_mem_to_afu.reset_n)
                );

            ofs_plat_avalon_mem_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_source(avmm_mmio_afu_clk),
                .mem_sink(mmio_to_afu)
                );

            ofs_plat_avalon_mem_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio_wo
               (
                .mem_source(avmm_wo_mmio_afu_clk),
                .mem_sink(mmio_wr_to_afu)
                );
        end
        else
        begin : nc
            ofs_plat_avalon_mem_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_source(avmm_mmio),
                .mem_sink(mmio_to_afu)
                );

            ofs_plat_avalon_mem_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio_wo
               (
                .mem_source(avmm_wo_mmio),
                .mem_sink(mmio_wr_to_afu)
                );
        end
    endgenerate

endmodule // ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_with_dual_mmio


// ========================================================================
//
//  Internal implementation.
//
// ========================================================================

//
// Map Avalon-MM to target clock and then to the host memory PCIe TLP
// interface.
//
module ofs_plat_host_chan_@group@_as_avalon_mem_rdwr_impl
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

    ofs_plat_avalon_mem_rdwr_if.to_source_clk host_mem_to_afu,

    // Export an Avalon port for MMIO mapping
    ofs_plat_avalon_mem_if.to_sink avmm_mmio,
    // Export a second Avalon port for MMIO write-only mapping. This
    // may be used when the AFU will receive wide MMIO writes but only
    // respond with narrow (e.g. 64 bit) MMIO reads.
    ofs_plat_avalon_mem_if.to_sink avmm_wo_mmio,

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

    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      avmm_afu_clk_if();

    logic afu_reset_n_q = 1'b0;
    always @(posedge afu_clk)
    begin
        afu_reset_n_q <= afu_reset_n;
    end

    assign avmm_afu_clk_if.clk = (ADD_CLOCK_CROSSING == 0) ? to_fiu.clk : afu_clk;
    assign avmm_afu_clk_if.reset_n = (ADD_CLOCK_CROSSING == 0) ? to_fiu.reset_n : afu_reset_n_q;
    assign avmm_afu_clk_if.instance_number = to_fiu.instance_number;

    // synthesis translate_off
    always_ff @(negedge avmm_afu_clk_if.clk)
    begin
        if (avmm_afu_clk_if.reset_n === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: avmm_afu_clk_if.reset_n port is uninitialized!");
        end
    end
    // synthesis translate_on

    ofs_plat_avalon_mem_rdwr_if_connect_sink_clk
      conn_afu_clk
       (
        .mem_source(host_mem_to_afu),
        .mem_sink(avmm_afu_clk_if)
        );


    // ====================================================================
    //  Cross to the FIU clock, sort responses and map bursts to FIU sizes.
    // ====================================================================

    // ofs_plat_avalon_mem_rdwr_if_async_rob records the ROB indices
    // of read and write requests in rd_user and wr_user fields after the
    // UC_AVALON_UFLAGs. Size the user fields using whichever index space
    // is larger.
    localparam ROB_IDX_WIDTH =
        $clog2((MAX_BW_ACTIVE_RD_LINES > MAX_BW_ACTIVE_WR_LINES) ? MAX_BW_ACTIVE_RD_LINES :
                                                                   MAX_BW_ACTIVE_WR_LINES);
    localparam USER_WIDTH =
        ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX + 1 + ROB_IDX_WIDTH;

    // Maximum burst that fits in the largest allowed TLP packet
    localparam FIU_BURST_CNT_MAX = ofs_plat_host_chan_@group@_pcie_tlp_pkg::MAX_PAYLOAD_SIZE /
                                   host_mem_to_afu.DATA_WIDTH_;

    ofs_plat_avalon_mem_rdwr_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_MEM_PARAMS(host_mem_to_afu),
        .BURST_CNT_WIDTH($clog2(1 + FIU_BURST_CNT_MAX)),
        .USER_WIDTH(USER_WIDTH)
        )
      avmm_fiu_clk_if();

    assign avmm_fiu_clk_if.clk = to_fiu.clk;
    assign avmm_fiu_clk_if.reset_n = to_fiu.reset_n;
    assign avmm_fiu_clk_if.instance_number = to_fiu.instance_number;

    // The Avalon interface is always sorted here, despite the Avalon bus not
    // requiring sorted responses. We do this because large Avalon bursts are
    // broken into smaller PCIe TLP bursts. These smaller PCIe bursts
    // might be reordered by the PCIe network. Avalon requires that
    // responses for a single request be returned in order. In order
    // to guarantee this, we sort responses.
    ofs_plat_map_avalon_mem_rdwr_if_to_host_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_ACTIVE_RD_LINES(MAX_BW_ACTIVE_RD_LINES),
        .MAX_ACTIVE_WR_LINES(MAX_BW_ACTIVE_WR_LINES),
        .USER_ROB_IDX_START(ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX+1),
        // Don't allow packets to cross 4KB pages due to PCIe requirement.
        .PAGE_SIZE(4096)
        )
      rob
       (
        .mem_source(avmm_afu_clk_if),
        .mem_sink(avmm_fiu_clk_if)
        );


    // ====================================================================
    //  Basic mapping from Avalon-MM to TLPs, all in the FIU clock domain.
    // ====================================================================

    // The Avalon-MM interface (avmm_fiu_clk_if) is in the FIU domain and
    // bursts are sized properly for PCIe. All that remains is to map
    // Avalon-MM bursts to PCIe TLP.

    ofs_plat_host_chan_@group@_map_as_avalon_mem_if
      #(
        .USER_ROB_IDX_START(ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX+1)
        )
      tlp_as_avalon_mem
       (
        .mem_source(avmm_fiu_clk_if),
        .mmio_sink(avmm_mmio),
        .mmio_wo_sink(avmm_wo_mmio),
        .to_fiu_tlp(to_fiu)
        );

endmodule // ofs_plat_host_chan_@group@_as_avalon_mem_rdwr
