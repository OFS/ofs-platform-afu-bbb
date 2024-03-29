// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__
`define __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__

// Macro indicates which gasket is active
`define OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_GASKET_EA_OFS_FIM 1

//
// Macros for emitting type-specific debug logs for PCIe TLP streams.
// We use these macros instead of logging in the AXI stream because the
// stream is unaware of the payload's data type.
//

`define LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP_TX(LOG_CLASS, tx_st) \
    initial \
    begin \
        static string ctx_name = $sformatf("%m.%s", `"tx_st`"); \
        // Watch traffic \
        if (LOG_CLASS != ofs_plat_log_pkg::NONE) \
        begin \
            static int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS); \
            forever @(posedge tx_st.clk) \
            begin \
                if (tx_st.reset_n && tx_st.tvalid && tx_st.tready) \
                begin \
                    ofs_plat_host_chan_@group@_fim_gasket_pkg::ofs_fim_gasket_log_pcie_tx_st( \
                        log_fd, ofs_plat_log_pkg::instance_name[LOG_CLASS], \
                        ctx_name, tx_st.instance_number, \
                        tx_st.t.data, tx_st.t.user); \
                end \
            end \
        end \
    end

`define LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP_RX(LOG_CLASS, rx_st) \
    initial \
    begin \
        static string ctx_name = $sformatf("%m.%s", `"rx_st`"); \
        // Watch traffic \
        if (LOG_CLASS != ofs_plat_log_pkg::NONE) \
        begin \
            static int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS); \
            forever @(posedge rx_st.clk) \
            begin \
                if (rx_st.reset_n && rx_st.tvalid && rx_st.tready) \
                begin \
                    ofs_plat_host_chan_@group@_fim_gasket_pkg::ofs_fim_gasket_log_pcie_rx_st( \
                        log_fd, ofs_plat_log_pkg::instance_name[LOG_CLASS], \
                        ctx_name, rx_st.instance_number, \
                        rx_st.t.data, rx_st.t.user); \
                end \
            end \
        end \
    end

`endif // __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__
