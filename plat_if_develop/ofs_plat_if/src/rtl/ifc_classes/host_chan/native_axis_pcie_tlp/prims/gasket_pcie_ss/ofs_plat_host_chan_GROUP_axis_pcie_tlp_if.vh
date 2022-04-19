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
