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
// Emulate PCIe SS ports. The ports will then either be passed to an afu_main()
// emulator or wrapped in PIM host channel interfaces.
//
// Just like the FIM, the virtual interfaces exposed to an AFU must be
// multiplexed into a single stream before being passed to ASE. The multiplexing
// is implemented here using modules taken from the FIM. They are renamed to
// avoid module name conflicts.
//

`include "ofs_plat_if.vh"

module ase_emul_pcie_ss_axis_tlp
  #(
    parameter NUM_PORTS = 1
    )
   (
    input  logic clk,
    input  logic rst_n,

    pcie_ss_axis_if.sink afu_axi_tx_a_if[NUM_PORTS-1:0],
    pcie_ss_axis_if.sink afu_axi_tx_b_if[NUM_PORTS-1:0],
    pcie_ss_axis_if.source afu_axi_rx_a_if[NUM_PORTS-1:0],
    pcie_ss_axis_if.source afu_axi_rx_b_if[NUM_PORTS-1:0],
    output logic softReset,
    output t_ofs_plat_power_state pwrState
    );

    //
    // The ASE PCIe SS DPI-C emulator is a single TX/RX TLP pair. Use variants of the
    // FIM's PF/VF MUX and A/B port arbitration to reduce the AFU TLP interface to
    // the emulated physical device.
    //

    pcie_ss_axis_if fim_axi_tx_ab_if[2](clk, rst_n);
    pcie_ss_axis_if fim_axi_rx_a_if(clk, rst_n);
    pcie_ss_axis_if fim_axi_rx_b_if(clk, rst_n);

    ase_emul_pf_vf_mux_top
      #(
        .MUX_NAME("A"),
        .N(NUM_PORTS)
        )
      pf_vf_mux_a
       (
        .clk,
        .rst_n,

        .ho2mx_rx_port(fim_axi_rx_a_if),
        .mx2ho_tx_port(fim_axi_tx_ab_if[0]),
        .mx2fn_rx_port(afu_axi_rx_a_if),
        .fn2mx_tx_port(afu_axi_tx_a_if),

        .out_fifo_err(),
        .out_fifo_perr()
        );

    ase_emul_pf_vf_mux_top
      #(
        .MUX_NAME("B"),
        .N(NUM_PORTS)
        )
      pf_vf_mux_b
       (
        .clk,
        .rst_n,

        .ho2mx_rx_port(fim_axi_rx_b_if),
        .mx2ho_tx_port(fim_axi_tx_ab_if[1]),
        .mx2fn_rx_port(afu_axi_rx_b_if),
        .fn2mx_tx_port(afu_axi_tx_b_if),

        .out_fifo_err(),
        .out_fifo_perr()
        );


    //
    // Merge the A/B TX ports into a single port.
    //
    pcie_ss_axis_if fim_axi_tx_arb_if(clk, rst_n);

    ase_emul_pcie_ss_axis_mux
      #(
        .NUM_CH(2)
        )
      tx_ab_mux
       (
        .clk,
        .rst_n,
        .sink(fim_axi_tx_ab_if),
        .source(fim_axi_tx_arb_if)
        );


    //
    // Generate local commit messages for write requests now that A/B arbitration
    // is complete. Commits are on RX B.
    //
    pcie_ss_axis_if fim_axi_tx_if(clk, rst_n);

    ase_emul_pcie_arb_local_commit local_commit
       (
        .clk,
        .rst_n,

        .sink(fim_axi_tx_arb_if),
        // Final merged TX stream, passed to ASE for emulation
        .source(fim_axi_tx_if),
        // Synthesized write completions
        .commit(fim_axi_rx_b_if)
        );

    ase_pcie_ss_emulator pcie_ss_emulator
       (
        .pClk(clk),
        .pck_cp2af_softReset(softReset),
        .pck_cp2af_pwrState(pwrState),
        .pck_cp2af_error(),

        .pcie_rx_if(fim_axi_rx_a_if),
        .pcie_tx_if(fim_axi_tx_if)
        );

endmodule // ase_emul_pcie_ss_axis_tlp
