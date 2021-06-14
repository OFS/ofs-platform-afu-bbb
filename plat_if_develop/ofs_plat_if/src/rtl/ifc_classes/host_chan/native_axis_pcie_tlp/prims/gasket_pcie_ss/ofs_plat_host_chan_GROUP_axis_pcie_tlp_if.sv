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
// Platform-specific interface to FIM. The interface is specified here, in
// the gaskets tree, because the data structures and protocols may be vary
// by platform.
//

interface ofs_plat_host_chan_@group@_axis_pcie_tlp_if
  #(
    // Log events for this instance?
    parameter ofs_plat_log_pkg::t_log_class LOG_CLASS = ofs_plat_log_pkg::NONE
    );

    wire clk;
    logic reset_n;

    // Debugging state.  This will typically be driven to a constant by the
    // code that instantiates the interface object.
    int unsigned instance_number;

    // PCIe PF/VF details
    pcie_ss_hdr_pkg::ReqHdr_pf_num_t pf_num;
    pcie_ss_hdr_pkg::ReqHdr_vf_num_t vf_num;
    logic vf_active;

    // AFU -> FIM TLP TX stream
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      afu_tx_a_st();

    // AFU -> FIM TLP TX B stream. The PIM uses this port for read requests.
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      afu_tx_b_st();

    // FIM -> AFU TLP RX A stream. This is the primary response stream from the host.
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      afu_rx_a_st();

    // FIM -> AFU TLP RX B stream. This stream is only FIM-generated write completions
    // to signal that the TX A/B arbitration is complete and a write is committed.
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      afu_rx_b_st();

    assign afu_tx_a_st.clk = clk;
    assign afu_tx_a_st.reset_n = reset_n;
    assign afu_tx_a_st.instance_number = instance_number;

    assign afu_tx_b_st.clk = clk;
    assign afu_tx_b_st.reset_n = reset_n;
    assign afu_tx_b_st.instance_number = instance_number;

    assign afu_rx_a_st.clk = clk;
    assign afu_rx_a_st.reset_n = reset_n;
    assign afu_rx_a_st.instance_number = instance_number;

    assign afu_rx_b_st.clk = clk;
    assign afu_rx_b_st.reset_n = reset_n;
    assign afu_rx_b_st.instance_number = instance_number;


    // synthesis translate_off
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(LOG_CLASS, "tx_a_st", afu_tx_a_st)
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(LOG_CLASS, "tx_b_st", afu_tx_b_st)
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(LOG_CLASS, "rx_a_st", afu_rx_a_st)
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(LOG_CLASS, "rx_b_st", afu_rx_b_st)
    // synthesis translate_on

endinterface // ofs_plat_host_chan_@group@_axis_pcie_tlp_if
