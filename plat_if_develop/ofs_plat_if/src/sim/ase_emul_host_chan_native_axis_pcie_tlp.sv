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
// Emulate a primary CCI-P port and optionally some other host channel groups.
//

`include "ofs_plat_if.vh"

`ifdef OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_AXIS_PCIE_TLP

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
        .NUM_TLP_CHANNELS(ofs_plat_host_chan_pcie_tlp_pkg::NUM_FIU_PCIE_TLP_CH),
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

`endif
