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


    // CSR clock, used when MMIO is mapped to an AXI-Lite bus by the PCIe SS,
    // is slow.
    localparam CSR_CLK_DELAY = 4527;   // Avoid clean alignment with pClk
    logic csr_clk = 1'b0;
    initial
    begin : csr_clk_proc
        forever
        begin
            #(CSR_CLK_DELAY);
            csr_clk = ~csr_clk;
        end
    end

    // Only power on reset is expected. Function-level reset comes on pClk.
    logic csr_rst_n = 1'b0;
    initial
    begin : csr_rst_proc
        forever
        begin
            #(CSR_CLK_DELAY * 20);
            csr_rst_n = 1'b1;
        end
    end

`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
    // Per-port AXI-Lite interface for CSRs. Emulated for FIMs that enable
    // the feature in the PCIe SS.
    ofs_fim_axi_lite_if
      #(
        .AWADDR_WIDTH(ofs_fim_cfg_pkg::MMIO_ADDR_WIDTH),
        .ARADDR_WIDTH(ofs_fim_cfg_pkg::MMIO_ADDR_WIDTH),
        .WDATA_WIDTH(ofs_fim_cfg_pkg::MMIO_DATA_WIDTH),
        .RDATA_WIDTH(ofs_fim_cfg_pkg::MMIO_DATA_WIDTH)
        )
      afu_csr_axi_lite_if[NUM_PORTS-1:0](csr_clk, csr_rst_n);
`endif


    // Emulate the PCIe SS
    ase_emul_pcie_ss_axis_tlp
      #(
        .NUM_PORTS(NUM_PORTS)
        )
      pcie_ss_axis_tlp
       (
        .clk,
        .rst_n,

`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
        .afu_csr_axi_lite_if,
`endif
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

`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
                .afu_csr_axi_lite_if(afu_csr_axi_lite_if[p]),
`endif
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
