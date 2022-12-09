// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
