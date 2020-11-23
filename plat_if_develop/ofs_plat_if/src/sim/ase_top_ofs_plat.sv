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
// Platform-specific device simulation. ASE's core library provides clocks
// and this module instantiates device models and constructs an OFS
// platform interface that wraps the simulated devices.
//

`include "ofs_plat_if.vh"

module ase_top_ofs_plat
   (
    input  logic pClk,
    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2
    );

    // Construct the simulated platform interface wrapper which will be passed
    // to the AFU.
    ofs_plat_if#(.ENABLE_LOG(1)) plat_ifc();
    logic softReset;


    // ====================================================================
    //
    //  Clocks
    //
    // ====================================================================

    ofs_plat_std_clocks_gen_resets_from_active_high clocks
       (
        .pClk,
        .pClk_reset(softReset),
        .pClkDiv2,
        .pClkDiv4,
        .uClk_usr,
        .uClk_usrDiv2,
        .clocks(plat_ifc.clocks)
        );

    assign plat_ifc.softReset_n = plat_ifc.clocks.pClk.reset_n;


`ifdef OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_AXIS_PCIE_TLP

    // ====================================================================
    //
    //  Emulate an AXI-S PCIe TLP host channel.
    //
    // ====================================================================

    ase_emul_host_chan_native_axis_pcie_tlp pcie_tlp
       (
        .clocks(plat_ifc.clocks),
        .host_chan_ports(plat_ifc.host_chan.ports),
        .softReset,
        .pwrState(plat_ifc.pwrState)
        );

`endif


`ifdef OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_CCIP

    // ====================================================================
    //
    //  Emulate a CCI-P native FIU connection.
    //
    // ====================================================================

    ase_emul_host_chan_native_ccip ccip
       (
        .clocks(plat_ifc.clocks),
        .host_chan_ports(plat_ifc.host_chan.ports),
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS
        .host_chan_g1_ports(plat_ifc.host_chan_g1.ports),
`endif
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS
        .host_chan_g2_ports(plat_ifc.host_chan_g2.ports),
`endif
        .softReset,
        .pwrState(plat_ifc.pwrState)
        );

`endif

    // ====================================================================
    //
    //  Local memory (model provided by the ASE core library)
    //
    // ====================================================================

    //
    // Main group (0)
    //
`ifdef OFS_PLAT_PARAM_LOCAL_MEM_NUM_BANKS
    localparam NUM_LOCAL_MEM_BANKS = plat_ifc.local_mem.NUM_BANKS;
    logic mem_banks_clk[NUM_LOCAL_MEM_BANKS];

  `ifdef OFS_PLAT_PARAM_LOCAL_MEM_IS_NATIVE_AVALON
    ase_sim_local_mem_ofs_avmm
  `elsif OFS_PLAT_PARAM_LOCAL_MEM_IS_NATIVE_AXI
    ase_sim_local_mem_ofs_axi
  `else
    ** Unexpected local memory type **
  `endif
      #(
        .NUM_BANKS(NUM_LOCAL_MEM_BANKS),
        .ADDR_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_ADDR_WIDTH),
        .DATA_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH),
        .BURST_CNT_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH),
  `ifdef OFS_PLAT_PARAM_LOCAL_MEM_IS_NATIVE_AXI
        .USER_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_USER_WIDTH),
        .RID_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_RID_WIDTH),
        .WID_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_WID_WIDTH),
  `endif
        .MASKED_SYMBOL_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH)
        )
      local_mem_model
       (
        .local_mem(plat_ifc.local_mem.banks),
        .clks(mem_banks_clk)
        );

    generate
        for (genvar b = 0; b < NUM_LOCAL_MEM_BANKS; b = b + 1)
        begin : b_reset
            assign plat_ifc.local_mem.banks[b].clk = mem_banks_clk[b];
            assign plat_ifc.local_mem.banks[b].reset_n = plat_ifc.softReset_n;
            assign plat_ifc.local_mem.banks[b].instance_number = b;
        end
    endgenerate
`endif

    //
    // Group 1 memory banks
    //
`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G1_NUM_BANKS
    localparam NUM_LOCAL_MEM_G1_BANKS = plat_ifc.local_mem_g1.NUM_BANKS;
    logic mem_banks_g1_clk[NUM_LOCAL_MEM_G1_BANKS];

  `ifdef OFS_PLAT_PARAM_LOCAL_MEM_G1_IS_NATIVE_AVALON
    ase_sim_local_mem_ofs_avmm
  `elsif OFS_PLAT_PARAM_LOCAL_MEM_G1_IS_NATIVE_AXI
    ase_sim_local_mem_ofs_axi
  `else
    ** Unexpected local memory type **
  `endif
      #(
        .NUM_BANKS(NUM_LOCAL_MEM_G1_BANKS),
        .ADDR_WIDTH(local_mem_g1_cfg_pkg::LOCAL_MEM_ADDR_WIDTH),
        .DATA_WIDTH(local_mem_g1_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH),
        .BURST_CNT_WIDTH(local_mem_g1_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH),
  `ifdef OFS_PLAT_PARAM_LOCAL_MEM_G1_IS_NATIVE_AXI
        .USER_WIDTH(local_mem_g1_cfg_pkg::LOCAL_MEM_USER_WIDTH),
        .RID_WIDTH(local_mem_g1_cfg_pkg::LOCAL_MEM_RID_WIDTH),
        .WID_WIDTH(local_mem_g1_cfg_pkg::LOCAL_MEM_WID_WIDTH),
  `endif
        .MASKED_SYMBOL_WIDTH(local_mem_g1_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH)
        )
      local_mem_g1_model
       (
        .local_mem(plat_ifc.local_mem_g1.banks),
        .clks(mem_banks_g1_clk)
        );

    generate
        for (genvar b = 0; b < NUM_LOCAL_MEM_G1_BANKS; b = b + 1)
        begin : b_reset_g1
            assign plat_ifc.local_mem_g1.banks[b].clk = mem_banks_g1_clk[b];
            assign plat_ifc.local_mem_g1.banks[b].reset_n = plat_ifc.softReset_n;
            assign plat_ifc.local_mem_g1.banks[b].instance_number = b;
        end
    endgenerate
`endif

    //
    // Group 2 memory banks
    //
`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G2_NUM_BANKS
    localparam NUM_LOCAL_MEM_G2_BANKS = plat_ifc.local_mem_g2.NUM_BANKS;
    logic mem_banks_g2_clk[NUM_LOCAL_MEM_G2_BANKS];

  `ifdef OFS_PLAT_PARAM_LOCAL_MEM_G2_IS_NATIVE_AVALON
    ase_sim_local_mem_ofs_avmm
  `elsif OFS_PLAT_PARAM_LOCAL_MEM_G2_IS_NATIVE_AXI
    ase_sim_local_mem_ofs_axi
  `else
    ** Unexpected local memory type **
  `endif
      #(
        .NUM_BANKS(NUM_LOCAL_MEM_G2_BANKS),
        .ADDR_WIDTH(local_mem_g2_cfg_pkg::LOCAL_MEM_ADDR_WIDTH),
        .DATA_WIDTH(local_mem_g2_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH),
        .BURST_CNT_WIDTH(local_mem_g2_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH),
  `ifdef OFS_PLAT_PARAM_LOCAL_MEM_G2_IS_NATIVE_AXI
        .USER_WIDTH(local_mem_g2_cfg_pkg::LOCAL_MEM_USER_WIDTH),
        .RID_WIDTH(local_mem_g2_cfg_pkg::LOCAL_MEM_RID_WIDTH),
        .WID_WIDTH(local_mem_g2_cfg_pkg::LOCAL_MEM_WID_WIDTH),
  `endif
        .MASKED_SYMBOL_WIDTH(local_mem_g2_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH)
        )
      local_mem_g2_model
       (
        .local_mem(plat_ifc.local_mem_g2.banks),
        .clks(mem_banks_g2_clk)
        );

    generate
        for (genvar b = 0; b < NUM_LOCAL_MEM_G2_BANKS; b = b + 1)
        begin : b_reset_g2
            assign plat_ifc.local_mem_g2.banks[b].clk = mem_banks_g2_clk[b];
            assign plat_ifc.local_mem_g2.banks[b].reset_n = plat_ifc.softReset_n;
            assign plat_ifc.local_mem_g2.banks[b].instance_number = b;
        end
    endgenerate
`endif

    //
    // Group 3 memory banks
    //
`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G3_NUM_BANKS
    localparam NUM_LOCAL_MEM_G3_BANKS = plat_ifc.local_mem_g3.NUM_BANKS;
    logic mem_banks_g3_clk[NUM_LOCAL_MEM_G3_BANKS];

  `ifdef OFS_PLAT_PARAM_LOCAL_MEM_G3_IS_NATIVE_AVALON
    ase_sim_local_mem_ofs_avmm
  `elsif OFS_PLAT_PARAM_LOCAL_MEM_G3_IS_NATIVE_AXI
    ase_sim_local_mem_ofs_axi
  `else
    ** Unexpected local memory type **
  `endif
      #(
        .NUM_BANKS(NUM_LOCAL_MEM_G3_BANKS),
        .ADDR_WIDTH(local_mem_g3_cfg_pkg::LOCAL_MEM_ADDR_WIDTH),
        .DATA_WIDTH(local_mem_g3_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH),
        .BURST_CNT_WIDTH(local_mem_g3_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH),
  `ifdef OFS_PLAT_PARAM_LOCAL_MEM_G3_IS_NATIVE_AXI
        .USER_WIDTH(local_mem_g3_cfg_pkg::LOCAL_MEM_USER_WIDTH),
        .RID_WIDTH(local_mem_g3_cfg_pkg::LOCAL_MEM_RID_WIDTH),
        .WID_WIDTH(local_mem_g3_cfg_pkg::LOCAL_MEM_WID_WIDTH),
  `endif
        .MASKED_SYMBOL_WIDTH(local_mem_g3_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH)
        )
      local_mem_g3_model
       (
        .local_mem(plat_ifc.local_mem_g3.banks),
        .clks(mem_banks_g3_clk)
        );

    generate
        for (genvar b = 0; b < NUM_LOCAL_MEM_G3_BANKS; b = b + 1)
        begin : b_reset_g3
            assign plat_ifc.local_mem_g3.banks[b].clk = mem_banks_g3_clk[b];
            assign plat_ifc.local_mem_g3.banks[b].reset_n = plat_ifc.softReset_n;
            assign plat_ifc.local_mem_g3.banks[b].instance_number = b;
        end
    endgenerate
`endif


    // ====================================================================
    //
    //  Instantiate the AFU
    //
    // ====================================================================

    `PLATFORM_SHIM_MODULE_NAME `PLATFORM_SHIM_MODULE_NAME
       (
        .plat_ifc
        );

endmodule // ase_top_ofs_plat
