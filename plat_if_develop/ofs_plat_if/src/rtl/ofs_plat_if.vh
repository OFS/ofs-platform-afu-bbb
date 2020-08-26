//
// Copyright (c) 2019, Intel Corporation
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
// Wrapper interface for passing all top-level interfaces into an AFU.
// Every platform must provide this interface.
//

`ifndef __OFS_PLAT_IF_VH__
`define __OFS_PLAT_IF_VH__

`include "ofs_plat_if_top_config.vh"
`include "ofs_plat_clocks.vh"
`include "ofs_plat_host_ccip_if.vh"
`include "ofs_plat_avalon_mem_if.vh"
`include "ofs_plat_avalon_mem_rdwr_if.vh"
`include "ofs_plat_axi_mem_if.vh"
`include "ofs_plat_axi_stream_if.vh"

`ifdef OFS_PLAT_PARAM_HOST_CHAN_NATIVE_CLASS
  `include "ofs_plat_host_chan_wrapper.vh"
`endif

`ifdef OFS_PLAT_PARAM_LOCAL_MEM_NATIVE_CLASS
  `include "ofs_plat_local_mem_wrapper.vh"
`endif

`ifdef OFS_PLAT_PARAM_HSSI_NATIVE_CLASS
  `include "ofs_plat_hssi_wrapper.vh"
`endif

// Compatibility mode for OPAE SDK's Platform Interface Manager
`ifndef AFU_TOP_REQUIRES_OFS_PLAT_IF_AFU
  `include "platform_shim_ccip_std_afu.vh"
`endif

//
// Two-bit power state, originally defined in CCI-P.
//
typedef logic [1:0] t_ofs_plat_power_state;

`endif // __OFS_PLAT_IF_VH__
