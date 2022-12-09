// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_LOCAL_MEM_@GROUP@_AVALON_MEM_VH__
`define __OFS_PLAT_LOCAL_MEM_@GROUP@_AVALON_MEM_VH__

//
// Templates for defining parameters of possible local memory interface classes.
// These are independent of the actual class of the local memory interface
// coming out of the FIU. Instead, they are aids in defining the interface
// desired by the AFU. The macros match the target interface parameters to
// the interface from the FIU.
//

//
// Local memory as an Avalon interface with all but the burst count
// defined. The AFU is expected to specify its desired burst count
// and the PIM will instantiate a gearbox to translate from AFU bursts
// to platform bursts. See below for a macro variant that specifies
// the platform-specific burst size.
//
// A single interface may be defined or, more commonly, a vector
// of interfaces -- one per bank:
//
//   ofs_plat_avalon_mem_if
//     #(
//       `LOCAL_MEM_@GROUP@_AVALON_MEM_PARAMS
//       )
//     local_mem_to_afu[local_mem_@group@_cfg_pkg::LOCAL_MEM_NUM_BANKS]();
//
`define LOCAL_MEM_@GROUP@_AVALON_MEM_PARAMS \
    .ADDR_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_DATA_WIDTH)

// The default Avalon interface exposes only data bits, not ECC. This
// version exposes ECC along with data, calling it all "data".
`define LOCAL_MEM_@GROUP@_AVALON_MEM_PARAMS_FULL_BUS \
    .ADDR_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH), \
    .MASKED_SYMBOL_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH)

//
// Variant of the standard parameters, including burst count width.
//
`define LOCAL_MEM_@GROUP@_AVALON_MEM_PARAMS_DEFAULT \
    .ADDR_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_DATA_WIDTH), \
    .BURST_CNT_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH)

`define LOCAL_MEM_@GROUP@_AVALON_MEM_PARAMS_FULL_BUS_DEFAULT \
    .ADDR_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH), \
    .MASKED_SYMBOL_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH), \
    .BURST_CNT_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH)

`endif // __OFS_PLAT_LOCAL_MEM_@GROUP@_AVALON_MEM_VH__
