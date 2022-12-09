// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__
`define __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__

`include "ofs_pcie_ss_cfg.vh"

// Macro indicates which gasket is active
`define OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_GASKET_PCIE_SS 1

// Atomic requests are supported on all platforms except the S10 systems,
// such as d5005, that emulate the PCIe SS.
`ifndef PLATFORM_FPGA_FAMILY_S10
  `define OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_ATOMICS 1
`endif

//
// Macros for emitting type-specific debug logs for PCIe TLP streams.
// We use these macros instead of logging in the AXI stream because the
// stream is unaware of the payload's data type.
//

`define LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(LOG_CLASS, name, tlp_st) \
    initial \
    begin \
        static string ctx_name = $sformatf("%m.%s", name); \
        // Watch traffic \
        if (LOG_CLASS != ofs_plat_log_pkg::NONE) \
        begin \
            static int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS); \
            forever @(posedge tlp_st.clk) \
            begin \
                if (tlp_st.reset_n && tlp_st.tvalid && tlp_st.tready) \
                begin \
                    ofs_plat_host_chan_@group@_fim_gasket_pkg::ofs_fim_gasket_log_pcie_st( \
                        log_fd, ofs_plat_log_pkg::instance_name[LOG_CLASS], \
                        ctx_name, tlp_st.instance_number, \
                        tlp_st.t.data, tlp_st.t.keep, tlp_st.t.user); \
                end \
            end \
        end \
    end

`endif // __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__
