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

    localparam PG_NUM_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS;

    // afu_main() either takes a single multiplexed PCIe port or it
    // takes a vector of ports, one per VF. This change happened at the
    // same time that MMIO CSRs were moved to an AXI-Lite interface.
    // We assume here they are correlated.
`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
    localparam NUM_PORTS = 1;
`else
    localparam NUM_PORTS = PG_NUM_PORTS;
`endif


    logic softReset;
    t_ofs_plat_power_state pwrState;

    wire rst_n = ~softReset;

    pcie_ss_axis_if afu_axi_tx_a_if[NUM_PORTS-1:0](pClk, rst_n);
    pcie_ss_axis_if afu_axi_tx_b_if[NUM_PORTS-1:0](pClk, rst_n);
    pcie_ss_axis_if afu_axi_rx_a_if[NUM_PORTS-1:0](pClk, rst_n);
    pcie_ss_axis_if afu_axi_rx_b_if[NUM_PORTS-1:0](pClk, rst_n);


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
    // AXI-Lite CSR interface. Coming into afu_main() the parameters are
    // the interface's default value.
    ofs_fim_axi_lite_if pcie_csr_axi_lite_if[NUM_PORTS-1:0](csr_clk, csr_rst_n);
`endif


    // Emulate the PCIe SS
    ase_emul_pcie_ss_axis_tlp
      #(
        .NUM_PORTS(NUM_PORTS)
        )
      pcie_ss_axis_tlp
       (
        .clk(pClk),
        .rst_n,
`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
        .afu_csr_axi_lite_if(pcie_csr_axi_lite_if),
`endif
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
        .PG_NUM_PORTS(PG_NUM_PORTS)
        )
      ase_afu_main_emul
       (
`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
        // afu_main() has a PF/VF MUX. It doesn't expect vectors of interfaces.
        .pcie_csr_axi_lite_if(pcie_csr_axi_lite_if[0]),
        .afu_axi_tx_a_if(afu_axi_tx_a_if[0]),
        .afu_axi_rx_a_if(afu_axi_rx_a_if[0]),
        .afu_axi_tx_b_if(afu_axi_tx_b_if[0]),
        .afu_axi_rx_b_if(afu_axi_rx_b_if[0]),
`endif
        .*
        );

endmodule // ase_afu_main_pcie_ss
