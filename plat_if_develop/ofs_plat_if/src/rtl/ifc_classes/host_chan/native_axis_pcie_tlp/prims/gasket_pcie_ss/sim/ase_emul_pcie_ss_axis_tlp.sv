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

`ifdef ASE_MAJOR_VERSION
    localparam ASE_VERSION = `ASE_MAJOR_VERSION;
`else
    localparam ASE_VERSION = 1;
`endif

    //
    // The ASE PCIe SS DPI-C emulator is a single TX/RX TLP pair. Use variants of the
    // FIM's PF/VF MUX and A/B port arbitration to reduce the AFU TLP interface to
    // the emulated physical device.
    //

    pcie_ss_axis_if fim_axi_tx_ab_if[2](clk, rst_n);
    pcie_ss_axis_if fim_axi_rx_a_if(clk, rst_n);
    pcie_ss_axis_if fim_axi_rx_b_if(clk, rst_n);

    generate
        if (NUM_PORTS > 1) begin : mux
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
        end
        else
        begin : nm
            // No MUX needed when there is just one port
            always_comb
            begin
                afu_axi_tx_a_if[0].tready = fim_axi_tx_ab_if[0].tready;
                fim_axi_tx_ab_if[0].tvalid = afu_axi_tx_a_if[0].tvalid;
                fim_axi_tx_ab_if[0].tlast = afu_axi_tx_a_if[0].tlast;
                fim_axi_tx_ab_if[0].tuser_vendor = afu_axi_tx_a_if[0].tuser_vendor;
                fim_axi_tx_ab_if[0].tdata = afu_axi_tx_a_if[0].tdata;
                fim_axi_tx_ab_if[0].tkeep = afu_axi_tx_a_if[0].tkeep;

                fim_axi_rx_a_if.tready = afu_axi_rx_a_if[0].tready;
                afu_axi_rx_a_if[0].tvalid = fim_axi_rx_a_if.tvalid;
                afu_axi_rx_a_if[0].tlast = fim_axi_rx_a_if.tlast;
                afu_axi_rx_a_if[0].tuser_vendor = fim_axi_rx_a_if.tuser_vendor;
                afu_axi_rx_a_if[0].tdata = fim_axi_rx_a_if.tdata;
                afu_axi_rx_a_if[0].tkeep = fim_axi_rx_a_if.tkeep;

                afu_axi_tx_b_if[0].tready = fim_axi_tx_ab_if[1].tready;
                fim_axi_tx_ab_if[1].tvalid = afu_axi_tx_b_if[0].tvalid;
                fim_axi_tx_ab_if[1].tlast = afu_axi_tx_b_if[0].tlast;
                fim_axi_tx_ab_if[1].tuser_vendor = afu_axi_tx_b_if[0].tuser_vendor;
                fim_axi_tx_ab_if[1].tdata = afu_axi_tx_b_if[0].tdata;
                fim_axi_tx_ab_if[1].tkeep = afu_axi_tx_b_if[0].tkeep;

                fim_axi_rx_b_if.tready = afu_axi_rx_b_if[0].tready;
                afu_axi_rx_b_if[0].tvalid = fim_axi_rx_b_if.tvalid;
                afu_axi_rx_b_if[0].tlast = fim_axi_rx_b_if.tlast;
                afu_axi_rx_b_if[0].tuser_vendor = fim_axi_rx_b_if.tuser_vendor;
                afu_axi_rx_b_if[0].tdata = fim_axi_rx_b_if.tdata;
                afu_axi_rx_b_if[0].tkeep = fim_axi_rx_b_if.tkeep;
            end
        end
    endgenerate

    //
    // Merge the A/B TX ports into a single port.
    //
    pcie_ss_axis_if fim_axi_tx_mrg_if(clk, rst_n);

    ase_emul_pcie_ss_axis_mux
      #(
        .NUM_CH(2)
        )
      tx_ab_mux
       (
        .clk,
        .rst_n,
        .sink(fim_axi_tx_ab_if),
        .source(fim_axi_tx_mrg_if)
        );


    //
    // Route RX read completions and write commits to the proper channels, based on
    // the FIM configuration. The FIM may route RX completions to either RX-A or RX-B,
    // depending on the PCIe SS mode. When the PCIe SS sorts responses, completions
    // are routed to a private stream. The FIM can also be configured to put store
    // commits on either RX-A or RX-B.
    //

    //
    // It is not supported to send both write commits and read completions to
    // the RX-B channel.
    //
    initial
    begin
        assert ((ofs_plat_host_chan_fim_gasket_pkg::CPL_CHAN != ofs_plat_host_chan_fim_gasket_pkg::PCIE_CHAN_B) ||
                (ofs_plat_host_chan_fim_gasket_pkg::WR_COMMIT_CHAN != ofs_plat_host_chan_fim_gasket_pkg::PCIE_CHAN_B)) else
          $fatal(2, "Illegal FIM configuration: both CPL_CHAN and WR_COMMIT_CHAN are RX-B!");
    end

    pcie_ss_axis_if fim_axi_rx_commit_if(clk, rst_n);
    pcie_ss_axis_if fim_axi_rx_emul_if(clk, rst_n);

    generate
        if (ofs_plat_host_chan_fim_gasket_pkg::WR_COMMIT_CHAN == ofs_plat_host_chan_fim_gasket_pkg::PCIE_CHAN_A)
        begin : commit_a
            //
            // Write commits go to RX-A. The commit stream must be merged into
            // the emulation stream, which already has at least MMIO requests, with
            // an arbiter.
            //

            // Input to the arbiter
            pcie_ss_axis_if fim_axi_rx_arb_if[2](clk, rst_n);

            // Read completions might be routed to RX-B, depending on the FIM
            // configuration. This flag governs the routing of the current message.
            logic rx_emul_to_rx_b;

            // rx_emul_if will route either to RX-A (fim_axi_rx_arb_if[0]) or to
            // fim_axi_rx_b_if.
            assign fim_axi_rx_emul_if.tready = rx_emul_to_rx_b ? fim_axi_rx_b_if.tready :
                                                                 fim_axi_rx_arb_if[0].tready;

            // RX stream when routing to RX-A
            assign fim_axi_rx_arb_if[0].tvalid = fim_axi_rx_emul_if.tvalid && !rx_emul_to_rx_b;
            assign fim_axi_rx_arb_if[0].tlast = fim_axi_rx_emul_if.tlast;
            assign fim_axi_rx_arb_if[0].tuser_vendor = fim_axi_rx_emul_if.tuser_vendor;
            assign fim_axi_rx_arb_if[0].tdata = fim_axi_rx_emul_if.tdata;
            assign fim_axi_rx_arb_if[0].tkeep = fim_axi_rx_emul_if.tkeep;

            // FIM-generated write commits, merged into RX-A
            assign fim_axi_rx_commit_if.tready = fim_axi_rx_arb_if[1].tready;
            assign fim_axi_rx_arb_if[1].tvalid = fim_axi_rx_commit_if.tvalid;
            assign fim_axi_rx_arb_if[1].tlast = fim_axi_rx_commit_if.tlast;
            assign fim_axi_rx_arb_if[1].tuser_vendor = fim_axi_rx_commit_if.tuser_vendor;
            assign fim_axi_rx_arb_if[1].tdata = fim_axi_rx_commit_if.tdata;
            assign fim_axi_rx_arb_if[1].tkeep = fim_axi_rx_commit_if.tkeep;

            // Merge the RX emulation and write commit streams into RX-A
            ase_emul_pcie_ss_axis_mux
              #(
                .NUM_CH(2)
                )
              rx_ab_mux
               (
                .clk,
                .rst_n,
                .sink(fim_axi_rx_arb_if),
                .source(fim_axi_rx_a_if)
                );

            // RX stream when routing read completions to RX-B
            assign fim_axi_rx_b_if.tvalid = fim_axi_rx_emul_if.tvalid && rx_emul_to_rx_b;
            assign fim_axi_rx_b_if.tlast = fim_axi_rx_emul_if.tlast;
            assign fim_axi_rx_b_if.tuser_vendor = fim_axi_rx_emul_if.tuser_vendor;
            assign fim_axi_rx_b_if.tdata = fim_axi_rx_emul_if.tdata;
            assign fim_axi_rx_b_if.tkeep = fim_axi_rx_emul_if.tkeep;


            //
            // Routing calculation of read completions on RX, either to RX-A or RX-B.
            // Completions may be multiple beats.
            //
            logic rx_emul_is_cpl_sop;
            logic rx_emul_is_cpl_multi;
            logic rx_emul_is_sop;
            pcie_ss_hdr_pkg::PCIe_CplHdr_t rx_emul_hdr;

            // Send a completion on the incoming RX stream to RX-B?
            assign rx_emul_to_rx_b =
                   (ofs_plat_host_chan_fim_gasket_pkg::CPL_CHAN == ofs_plat_host_chan_fim_gasket_pkg::PCIE_CHAN_B) &&
                   (rx_emul_is_cpl_sop || rx_emul_is_cpl_multi);

            // Is the current messages on the incoming RX stream a completion?
            assign rx_emul_hdr = pcie_ss_hdr_pkg::PCIe_CplHdr_t'(fim_axi_rx_emul_if.tdata);
            assign rx_emul_is_cpl_sop =
                   (rx_emul_is_sop && fim_axi_rx_emul_if.tvalid) ?
                     pcie_ss_hdr_pkg::func_is_completion(rx_emul_hdr.fmt_type) : 1'b0;

            // Track multi-beat completions
            always_ff @(posedge clk)
            begin
                if (fim_axi_rx_emul_if.tvalid && fim_axi_rx_emul_if.tready)
                begin
                    if (fim_axi_rx_emul_if.tlast)
                    begin
                        // EOP
                        rx_emul_is_sop <= 1'b1;
                        rx_emul_is_cpl_multi <= 1'b0;
                    end
                    else
                    begin
                        // Not EOP
                        rx_emul_is_sop <= 1'b0;
                        if (rx_emul_is_cpl_sop)
                        begin
                            // Start of a multi-beat completion
                            rx_emul_is_cpl_multi <= 1'b1;
                        end
                    end
                end

                if (!rst_n)
                begin
                    rx_emul_is_sop <= 1'b1;
                    rx_emul_is_cpl_multi <= 1'b0;
                end
            end
        end
        else
        begin : commit_b
            //
            // Write commits go to RX-B. Since completions must then go to RX-A
            // the code is simple.
            //
            assign fim_axi_rx_emul_if.tready = fim_axi_rx_a_if.tready;
            assign fim_axi_rx_a_if.tvalid = fim_axi_rx_emul_if.tvalid;
            assign fim_axi_rx_a_if.tlast = fim_axi_rx_emul_if.tlast;
            assign fim_axi_rx_a_if.tuser_vendor = fim_axi_rx_emul_if.tuser_vendor;
            assign fim_axi_rx_a_if.tdata = fim_axi_rx_emul_if.tdata;
            assign fim_axi_rx_a_if.tkeep = fim_axi_rx_emul_if.tkeep;

            assign fim_axi_rx_commit_if.tready = fim_axi_rx_b_if.tready;
            assign fim_axi_rx_b_if.tvalid = fim_axi_rx_commit_if.tvalid;
            assign fim_axi_rx_b_if.tlast = fim_axi_rx_commit_if.tlast;
            assign fim_axi_rx_b_if.tuser_vendor = fim_axi_rx_commit_if.tuser_vendor;
            assign fim_axi_rx_b_if.tdata = fim_axi_rx_commit_if.tdata;
            assign fim_axi_rx_b_if.tkeep = fim_axi_rx_commit_if.tkeep;
        end
    endgenerate

    //
    // Generate local commit messages for write requests now that A/B arbitration
    // is complete.
    //
    pcie_ss_axis_if fim_axi_tx_if(clk, rst_n);

    ase_emul_pcie_arb_local_commit local_commit
       (
        .clk,
        .rst_n,

        .sink(fim_axi_tx_mrg_if),
        // Final merged TX stream, passed to ASE for emulation
        .source(fim_axi_tx_if),
        // Synthesized write completions
        .commit(fim_axi_rx_commit_if)
        );


    // Instantiate the core ASE PCIe SS emulator
    ase_pcie_ss_emulator pcie_ss_emulator
       (
        .pClk(clk),
        .pck_cp2af_softReset(softReset),
        .pck_cp2af_pwrState(pwrState),
        .pck_cp2af_error(),

        .pcie_rx_if(fim_axi_rx_emul_if),
        .pcie_tx_if(fim_axi_tx_if)
        );

endmodule // ase_emul_pcie_ss_axis_tlp
