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

`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
    ofs_fim_axi_lite_if.source afu_csr_axi_lite_if[NUM_PORTS-1:0],
`endif

    pcie_ss_axis_if.sink afu_axi_tx_a_if[NUM_PORTS-1:0],
    pcie_ss_axis_if.sink afu_axi_tx_b_if[NUM_PORTS-1:0],
    pcie_ss_axis_if.source afu_axi_rx_a_if[NUM_PORTS-1:0],
    pcie_ss_axis_if.source afu_axi_rx_b_if[NUM_PORTS-1:0],
    output logic softReset,
    output t_ofs_plat_power_state pwrState
    );

    pcie_ss_axis_if tlp_tx_a_if[NUM_PORTS-1:0](clk, rst_n);;
    pcie_ss_axis_if tlp_rx_a_if[NUM_PORTS-1:0](clk, rst_n);;

`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
    static int log_fd = $fopen("log_ase_mmio_axi_lite.tsv", "w");
    initial
    begin : log
        afu_csr_axi_lite_if[0].debug_header(log_fd);
        $fwrite(log_fd, "\n");
    end
`endif

    //
    // Is the PCIe SS configured to separate MMIO (CSR) traffic into a separate
    // AXI-Lite interface? If so, emulate that separation here. It isn't the
    // place the FIM would separate the traffic, since we are on the AFU side
    // of the PF/VF MUX. AFUs can't tell the difference.
    //
    generate
        for (genvar p = 0; p < NUM_PORTS; p = p + 1)
        begin : mmio
`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
            ase_emul_pcie_ss_split_mmio
              #(
                // For now, pick an arbitrary VF encoding
                .PF_NUM(0),
                .VF_NUM(p),
                .VF_ACTIVE(1)
                )
              split_mmio
               (
                .afu_csr_axi_lite_if(afu_csr_axi_lite_if[p]),
                .afu_tlp_tx_if(afu_axi_tx_a_if[p]),
                .fim_tlp_tx_if(tlp_tx_a_if[p]),
                .afu_tlp_rx_if(afu_axi_rx_a_if[p]),
                .fim_tlp_rx_if(tlp_rx_a_if[p])
                );

            always @(posedge afu_csr_axi_lite_if[p].clk)
            begin
                if (afu_csr_axi_lite_if[p].rst_n)
                begin
                    afu_csr_axi_lite_if[p].debug_log(log_fd, $sformatf("afu_csr_axi_lite_if[%0d]: ", p));
                end
            end
`else
            // Keep MMIO in the TLP stream
            always_comb
            begin
                afu_axi_tx_a_if[p].tready = tlp_tx_a_if[p].tready;
                tlp_tx_a_if[p].tvalid = afu_axi_tx_a_if[p].tvalid;
                tlp_tx_a_if[p].tlast = afu_axi_tx_a_if[p].tlast;
                tlp_tx_a_if[p].tuser_vendor = afu_axi_tx_a_if[p].tuser_vendor;
                tlp_tx_a_if[p].tdata = afu_axi_tx_a_if[p].tdata;
                tlp_tx_a_if[p].tkeep = afu_axi_tx_a_if[p].tkeep;

                tlp_rx_a_if[p].tready = afu_axi_rx_a_if[p].tready;
                afu_axi_rx_a_if[p].tvalid = tlp_rx_a_if[p].tvalid;
                afu_axi_rx_a_if[p].tlast = tlp_rx_a_if[p].tlast;
                afu_axi_rx_a_if[p].tuser_vendor = tlp_rx_a_if[p].tuser_vendor;
                afu_axi_rx_a_if[p].tdata = tlp_rx_a_if[p].tdata;
                afu_axi_rx_a_if[p].tkeep = tlp_rx_a_if[p].tkeep;
            end
`endif
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
                .mx2fn_rx_port(tlp_rx_a_if),
                .fn2mx_tx_port(tlp_tx_a_if),

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
                tlp_tx_a_if[0].tready = fim_axi_tx_ab_if[0].tready;
                fim_axi_tx_ab_if[0].tvalid = tlp_tx_a_if[0].tvalid;
                fim_axi_tx_ab_if[0].tlast = tlp_tx_a_if[0].tlast;
                fim_axi_tx_ab_if[0].tuser_vendor = tlp_tx_a_if[0].tuser_vendor;
                fim_axi_tx_ab_if[0].tdata = tlp_tx_a_if[0].tdata;
                fim_axi_tx_ab_if[0].tkeep = tlp_tx_a_if[0].tkeep;

                fim_axi_rx_a_if.tready = tlp_rx_a_if[0].tready;
                tlp_rx_a_if[0].tvalid = fim_axi_rx_a_if.tvalid;
                tlp_rx_a_if[0].tlast = fim_axi_rx_a_if.tlast;
                tlp_rx_a_if[0].tuser_vendor = fim_axi_rx_a_if.tuser_vendor;
                tlp_rx_a_if[0].tdata = fim_axi_rx_a_if.tdata;
                tlp_rx_a_if[0].tkeep = fim_axi_rx_a_if.tkeep;

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


    // Force virtual active flag in RX stream from host. ASE supports only one function,
    // currently setting PF0. Transform it to VF0 here in order to support the standard
    // afu_main() collection.
    pcie_ss_axis_if fim_axi_rx_a_va(clk, rst_n);
    logic fim_axi_rx_a_va_sop;
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t fim_axi_rx_a_va_hdr;

    // Force VF active
    always_comb
    begin
        fim_axi_rx_a_va.tready = fim_axi_rx_a_if.tready;
        fim_axi_rx_a_if.tvalid = fim_axi_rx_a_va.tvalid;
        fim_axi_rx_a_if.tlast = fim_axi_rx_a_va.tlast;
        fim_axi_rx_a_if.tuser_vendor = fim_axi_rx_a_va.tuser_vendor;
        fim_axi_rx_a_if.tkeep = fim_axi_rx_a_va.tkeep;

        fim_axi_rx_a_va_hdr = pcie_ss_hdr_pkg::PCIe_PUCplHdr_t'(fim_axi_rx_a_va.tdata);
        fim_axi_rx_a_va_hdr.vf_active = 1'b1;

        fim_axi_rx_a_if.tdata = fim_axi_rx_a_va.tdata;
        if (fim_axi_rx_a_va_sop)
        begin
            fim_axi_rx_a_if.tdata[0 +: $bits(fim_axi_rx_a_va_hdr)] = fim_axi_rx_a_va_hdr;
        end
    end

    // Track SOP to find RX A headers
    always_ff @(posedge clk)
    begin
        if (fim_axi_rx_a_va.tvalid && fim_axi_rx_a_va.tready)
            fim_axi_rx_a_va_sop <= fim_axi_rx_a_va.tlast;
        if (!rst_n)
            fim_axi_rx_a_va_sop <= 1'b1;
    end

    // Instantiate the core ASE PCIe SS emulator
    ase_pcie_ss_emulator pcie_ss_emulator
       (
        .pClk(clk),
        .pck_cp2af_softReset(softReset),
        .pck_cp2af_pwrState(pwrState),
        .pck_cp2af_error(),

        .pcie_rx_if(fim_axi_rx_a_va),
        .pcie_tx_if(fim_axi_tx_if)
        );

endmodule // ase_emul_pcie_ss_axis_tlp
