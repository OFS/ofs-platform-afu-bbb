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

`ifndef __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__
`define __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__

//
// Macros for emitting type-specific debug logs for PCIe TLP streams.
// We use these macros instead of logging in the AXI stream because the
// stream is unaware of the payload's data type.
//

`define LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_TX(LOG_CLASS, tx_st) \
    initial \
    begin \
        string ctx_name = $sformatf("%m.%s", `"tx_st`"); \
        // Watch traffic \
        if (LOG_CLASS != ofs_plat_log_pkg::NONE) \
        begin \
            int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS); \
            forever @(posedge tx_st.clk) \
            begin \
                if (tx_st.reset_n && tx_st.tvalid && tx_st.tready) \
                begin \
                    ofs_plat_host_chan_@GROUP@_pcie_tlp_pkg::log_afu_tx_st( \
                        log_fd, ofs_plat_log_pkg::instance_name[LOG_CLASS], \
                        ctx_name, tx_st.instance_number, \
                        tx_st.t.data, tx_st.t.user); \
                end \
            end \
        end \
    end

`define LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_RX(LOG_CLASS, rx_st) \
    initial \
    begin \
        string ctx_name = $sformatf("%m.%s", `"rx_st`"); \
        // Watch traffic \
        if (LOG_CLASS != ofs_plat_log_pkg::NONE) \
        begin \
            int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS); \
            forever @(posedge rx_st.clk) \
            begin \
                if (rx_st.reset_n && rx_st.tvalid && rx_st.tready) \
                begin \
                    ofs_plat_host_chan_@GROUP@_pcie_tlp_pkg::log_afu_rx_st( \
                        log_fd, ofs_plat_log_pkg::instance_name[LOG_CLASS], \
                        ctx_name, rx_st.instance_number, \
                        rx_st.t.data, rx_st.t.user); \
                end \
            end \
        end \
    end

`endif // __OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_IF__
