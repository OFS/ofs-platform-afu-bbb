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
// Emulate PCIe host channels
//
// ASE emulates the PCIe SS interface, simulating only a single physical TX/RX
// port pair. Just like the FIM, the virtual interfaces exposed to an AFU must
// be multiplexed into a single stream before being passed to ASE. The multiplexing
// is implemented here using modules taken from the FIM. They are renamed to
// avoid module name conflicts.
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

    genvar p;
    generate
        for (p = 0; p < NUM_PORTS; p = p + 1)
        begin
            assign host_chan_ports[p].clk = clocks.ports[p].pClk.clk;
            assign host_chan_ports[p].reset_n = clocks.ports[p].pClk.reset_n;
            assign host_chan_ports[p].instance_number = p;

            assign port_clk[p] = host_chan_ports[p].clk;
            assign port_rst_n[p] = host_chan_ports[p].reset_n;

            // For now, pick an arbitrary VF encoding
            assign host_chan_ports[p].pf_num = 0;
            assign host_chan_ports[p].vf_num = p;
            assign host_chan_ports[p].vf_active = 1'b1;


            // Map the PIM's host_chan interface to the FIM's PCIe SS interface using
            // the same module as on HW.
            map_fim_pcie_ss_to_host_chan map_host_chan
               (
                .pcie_ss_tx_a_st(afu_axi_tx_a_if[p]),
                .pcie_ss_tx_b_st(afu_axi_tx_b_if[p]),
                .pcie_ss_rx_a_st(afu_axi_rx_a_if[p]),
                .pcie_ss_rx_b_st(afu_axi_rx_b_if[p]),

                .pim_tx_a_st(host_chan_ports[p].afu_tx_a_st),
                .pim_tx_b_st(host_chan_ports[p].afu_tx_b_st),
                .pim_rx_a_st(host_chan_ports[p].afu_rx_a_st),
                .pim_rx_b_st(host_chan_ports[p].afu_rx_b_st)
                );
        end
    endgenerate


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
        .pClk(clocks.pClk.clk),
        .pck_cp2af_softReset(softReset),
        .pck_cp2af_pwrState(pwrState),
        .pck_cp2af_error(),

        .pcie_rx_if(fim_axi_rx_a_if),
        .pcie_tx_if(fim_axi_tx_if)
        );

endmodule // ase_emul_host_chan_native_axis_pcie_tlp
