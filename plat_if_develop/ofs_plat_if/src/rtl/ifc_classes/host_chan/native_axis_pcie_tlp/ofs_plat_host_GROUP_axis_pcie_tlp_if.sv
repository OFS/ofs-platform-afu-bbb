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

interface ofs_plat_host_@group@_axis_pcie_tlp_if
  #(
    // Log events for this instance?
    parameter ofs_plat_log_pkg::t_log_class LOG_CLASS = ofs_plat_log_pkg::NONE
    );

    wire clk;
    logic reset_n;

    // Debugging state.  This will typically be driven to a constant by the
    // code that instantiates the interface object.
    int unsigned instance_number;

    typedef ofs_fim_if_pkg::t_axis_pcie_tdata [ofs_fim_if_pkg::FIM_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_tdata_vec;
    typedef ofs_fim_if_pkg::t_axis_pcie_tx_tuser [ofs_fim_if_pkg::FIM_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_tx_tuser_vec;
    typedef ofs_fim_if_pkg::t_axis_pcie_rx_tuser [ofs_fim_if_pkg::FIM_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_rx_tuser_vec;

    ofs_plat_axi_stream_if
      #(
        .LOG_CLASS(LOG_CLASS),
        .TDATA_TYPE(t_ofs_plat_axis_pcie_tdata_vec),
        .TUSER_TYPE(t_ofs_plat_axis_pcie_tx_tuser_vec)
        )
      afu_tx_st();

    ofs_plat_axi_stream_if
      #(
        .LOG_CLASS(LOG_CLASS),
        .TDATA_TYPE(t_ofs_plat_axis_pcie_tdata_vec),
        .TUSER_TYPE(t_ofs_plat_axis_pcie_rx_tuser_vec)
        )
      afu_rx_st();

    ofs_plat_axi_stream_if
      #(
        .LOG_CLASS(LOG_CLASS),
        .TDATA_TYPE(ofs_fim_if_pkg::t_axis_irq_tdata),
        .TUSER_TYPE(logic)
        )
      afu_irq_rx_st();

    assign afu_tx_st.clk = clk;
    assign afu_tx_st.reset_n = reset_n;
    assign afu_tx_st.instance_number = instance_number;

    assign afu_rx_st.clk = clk;
    assign afu_rx_st.reset_n = reset_n;
    assign afu_rx_st.instance_number = instance_number;

    assign afu_irq_rx_st.clk = clk;
    assign afu_irq_rx_st.reset_n = reset_n;
    assign afu_irq_rx_st.instance_number = instance_number;

endinterface
