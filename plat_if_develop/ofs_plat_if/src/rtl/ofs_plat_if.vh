// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Wrapper interface for passing all top-level interfaces into an AFU.
// Every platform must provide this interface.
//

`ifndef __OFS_PLAT_IF_VH__
`define __OFS_PLAT_IF_VH__

`include "ofs_plat_if_top_config.vh"


// PKG_SORT_IGNORE_START --
//  This marker causes the PIM's sort_sv_packages.py to ignore everything
//  from here to the ignore end marker below. The package sorter uses a
//  very simple parser to detect what looks like a SystemVerilog package
//  reference in order to emit packages in dependence order. The code
//  or include files below contain macros that refer to packages but
//  do not represent true package to package dependence.

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

// PKG_SORT_IGNORE_END


//
// Two-bit power state, originally defined in CCI-P.
//
typedef logic [1:0] t_ofs_plat_power_state;

`endif // __OFS_PLAT_IF_VH__
