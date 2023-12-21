// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Common PCIe SS emulation for afu_main() in ASE. Instantiate a PCIe SS TLP
// emulator and then pass it to the platform-specific afu_main() ase wrapper.

module ase_afu_main_pcie_ss
   (
    input  logic pClk,
    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2
    );

`ifdef AFU_MAIN_HAS_PF_VF_MUX
    // afu_main() has a PF/VF MUX. Only generate one port into it.
    localparam NUM_PORTS = 1;
`else
    localparam NUM_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS;
`endif

    logic softReset;
    t_ofs_plat_power_state pwrState;

    wire rst_n = ~softReset;

    pcie_ss_axis_if afu_axi_tx_a_if[NUM_PORTS-1:0](pClk, rst_n);
    pcie_ss_axis_if afu_axi_tx_b_if[NUM_PORTS-1:0](pClk, rst_n);
    pcie_ss_axis_if afu_axi_rx_a_if[NUM_PORTS-1:0](pClk, rst_n);
    pcie_ss_axis_if afu_axi_rx_b_if[NUM_PORTS-1:0](pClk, rst_n);

    // Emulate the PCIe SS
    ase_emul_pcie_ss_axis_tlp
      #(
        .NUM_PORTS(NUM_PORTS),
        .NUM_AFU_PORTS(`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS)
        )
      pcie_ss_axis_tlp
       (
        .clk(pClk),
        .rst_n,

        .afu_axi_tx_a_if,
        .afu_axi_tx_b_if,
        .afu_axi_rx_a_if,
        .afu_axi_rx_b_if,
        .softReset,
        .pwrState
        );

    // Platform-specific top-level emulation. This module will be supplied by
    // OFS sources specific to a given board.
    ase_afu_main_emul
      #(
        // The true number of ports, after demultiplexing
        .PG_NUM_PORTS(`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS)
        )
      ase_afu_main_emul
       (
`ifdef AFU_MAIN_HAS_PF_VF_MUX
        .afu_axi_tx_a_if(afu_axi_tx_a_if[0]),
        .afu_axi_tx_b_if(afu_axi_tx_b_if[0]),
        .afu_axi_rx_a_if(afu_axi_rx_a_if[0]),
        .afu_axi_rx_b_if(afu_axi_rx_b_if[0]),
`endif
        .*
        );

endmodule // ase_afu_main_pcie_ss
