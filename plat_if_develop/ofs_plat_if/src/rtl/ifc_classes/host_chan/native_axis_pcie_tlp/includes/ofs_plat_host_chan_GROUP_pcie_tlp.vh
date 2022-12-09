// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_HOST_CHAN_@GROUP@_PCIE_TLP__
`define __OFS_PLAT_HOST_CHAN_@GROUP@_PCIE_TLP__

//
// Macros for emitting type-specific debug logs for the PIM's private
// encoding of PCIe TLP streams.
//
// We use these macros instead of logging in the AXI stream because the
// stream is unaware of the payload's data type.
//

`define LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_ST(LOG_CLASS, tlp_st, prefix) \
    initial \
    begin \
        static string ctx_name = $sformatf("%m.%s", prefix); \
        // Watch traffic \
        if (LOG_CLASS != ofs_plat_log_pkg::NONE) \
        begin \
            static int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS); \
            forever @(posedge tlp_st.clk) \
            begin \
                if (tlp_st.reset_n && tlp_st.tvalid && tlp_st.tready) \
                begin \
                    ofs_plat_host_chan_@group@_pcie_tlp_pkg::ofs_plat_pcie_log_tlp( \
                        log_fd, ofs_plat_log_pkg::instance_name[LOG_CLASS], \
                        ctx_name, tlp_st.instance_number, \
                        tlp_st.t.data, tlp_st.t.user, tlp_st.t.keep); \
                end \
            end \
        end \
    end

`define LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_TX(LOG_CLASS, tx_st) \
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_ST(LOG_CLASS, tx_st, `"tx_st`")

`define LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_RX(LOG_CLASS, rx_st) \
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_ST(LOG_CLASS, rx_st, `"rx_st`")

`endif // __OFS_PLAT_HOST_CHAN_@GROUP@_PCIE_TLP__
