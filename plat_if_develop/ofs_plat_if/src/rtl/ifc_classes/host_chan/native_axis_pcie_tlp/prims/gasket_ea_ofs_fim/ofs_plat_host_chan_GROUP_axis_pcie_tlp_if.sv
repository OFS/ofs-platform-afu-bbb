// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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

    // AFU -> FIM TLP TX stream
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata_vec),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tx_tuser_vec)
        )
      afu_tx_st();

    // FIM -> AFU TLP RX stream
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata_vec),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_rx_tuser_vec)
        )
      afu_rx_st();

    // FIM -> AFU interrupt responses
    ofs_plat_axi_stream_if
      #(
        .LOG_CLASS(LOG_CLASS),
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_irq_tdata),
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


    // synthesis translate_off
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP_TX(LOG_CLASS, afu_tx_st)
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP_RX(LOG_CLASS, afu_rx_st)
    // synthesis translate_on

endinterface // ofs_plat_host_chan_@group@_axis_pcie_tlp_if
