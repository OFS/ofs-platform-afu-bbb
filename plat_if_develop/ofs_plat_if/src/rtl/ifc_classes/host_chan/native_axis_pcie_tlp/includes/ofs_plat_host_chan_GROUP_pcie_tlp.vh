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
