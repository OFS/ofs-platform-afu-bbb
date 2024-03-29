// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Emulate PCIe host channels where the channels are PCIe SS TLP streams.
//

`include "ofs_plat_if.vh"

module ase_emul_host_chan_native_axis_pcie_tlp
   (
    input  wire t_ofs_plat_std_clocks clocks,
    ofs_plat_host_chan_axis_pcie_tlp_if host_chan_ports[`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS],
    output logic softReset,
    output t_ofs_plat_power_state pwrState
    );

    localparam NUM_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS;

    wire clk = clocks.ports[0].pClk.clk;
    wire rst_n = ~softReset;

    // The PF/VF MUX expects port ordering as [NUM_PORTS-1:0]
    logic port_clk[NUM_PORTS-1:0];
    logic port_rst_n[NUM_PORTS-1:0];
    pcie_ss_axis_if afu_axi_tx_a_if[NUM_PORTS-1:0](port_clk, port_rst_n);
    pcie_ss_axis_if afu_axi_tx_b_if[NUM_PORTS-1:0](port_clk, port_rst_n);
    pcie_ss_axis_if afu_axi_rx_a_if[NUM_PORTS-1:0](port_clk, port_rst_n);
    pcie_ss_axis_if afu_axi_rx_b_if[NUM_PORTS-1:0](port_clk, port_rst_n);

    // Emulate the PCIe SS
    ase_emul_pcie_ss_axis_tlp
      #(
        .NUM_PORTS(NUM_PORTS)
        )
      pcie_ss_axis_tlp
       (
        .clk,
        .rst_n,

        .afu_axi_tx_a_if,
        .afu_axi_tx_b_if,
        .afu_axi_rx_a_if,
        .afu_axi_rx_b_if,
        .softReset,
        .pwrState
        );

    genvar p;
    generate
        for (p = 0; p < NUM_PORTS; p = p + 1)
        begin
            // Map the PIM's host_chan interface to the FIM's PCIe SS interface using
            // the same module as on HW.
            map_fim_pcie_ss_to_pim_host_chan
              #(
                .INSTANCE_NUMBER(p),

                // For now, pick an arbitrary VF encoding
                .PF_NUM(0),
                .VF_NUM(p),
                .VF_ACTIVE(1)
                )
             map_host_chan
               (
                .clk(clocks.ports[p].pClk.clk),
                .reset_n(clocks.ports[p].pClk.reset_n),

                .pcie_ss_tx_a_st(afu_axi_tx_a_if[p]),
                .pcie_ss_tx_b_st(afu_axi_tx_b_if[p]),
                .pcie_ss_rx_a_st(afu_axi_rx_a_if[p]),
                .pcie_ss_rx_b_st(afu_axi_rx_b_if[p]),

                .port(host_chan_ports[p])
                );

            assign port_clk[p] = host_chan_ports[p].clk;
            assign port_rst_n[p] = host_chan_ports[p].reset_n;
        end
    endgenerate

endmodule // ase_emul_host_chan_native_axis_pcie_tlp
