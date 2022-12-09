// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Emulate PCIe host channels
//

`include "ofs_plat_if.vh"

module ase_emul_host_chan_native_axis_pcie_tlp
   (
    input  wire t_ofs_plat_std_clocks clocks,
    ofs_plat_host_chan_axis_pcie_tlp_if host_chan_ports[`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS],
    output logic softReset,
    output t_ofs_plat_power_state pwrState
    );

    genvar p;
    generate
        for (p = 0; p < `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS; p = p + 1)
        begin
            assign host_chan_ports[p].clk = clocks.pClk.clk;
            assign host_chan_ports[p].reset_n = ~softReset;
            assign host_chan_ports[p].instance_number = p;
        end
    endgenerate

    axis_pcie_tlp_emulator
      #(
        .NUM_TLP_CHANNELS(ofs_plat_host_chan_fim_gasket_pkg::NUM_FIM_PCIE_TLP_CH),
        .MAX_OUTSTANDING_DMA_RD_REQS(ofs_plat_host_chan_pcie_tlp_pkg::MAX_OUTSTANDING_DMA_RD_REQS),
        .MAX_OUTSTANDING_MMIO_RD_REQS(ofs_plat_host_chan_pcie_tlp_pkg::MAX_OUTSTANDING_MMIO_RD_REQS),
        .NUM_AFU_INTERRUPTS(ofs_plat_host_chan_pcie_tlp_pkg::NUM_AFU_INTERRUPTS),
        .MAX_PAYLOAD_BYTES(ofs_plat_host_chan_pcie_tlp_pkg::MAX_PAYLOAD_SIZE / 8)
        )
      axi_pcie_tlp_emulator
       (
        .pClk(clocks.pClk.clk),
        .pcie_tlp_if(host_chan_ports[0]),
        .pck_cp2af_softReset(softReset),
        .pck_cp2af_pwrState(pwrState),
        .pck_cp2af_error()
        );

endmodule // ase_emul_host_chan_native_axis_pcie_tlp
