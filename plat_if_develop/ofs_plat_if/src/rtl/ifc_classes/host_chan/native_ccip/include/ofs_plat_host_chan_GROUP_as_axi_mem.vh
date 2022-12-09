// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AXI_MEM_RDWR__
`define __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AXI_MEM_RDWR__

//
// Macros for setting parameters to AXI memory interfaces.
//

// AXI host memory ofs_plat_axi_mem_if parameters.
// AFUs may set BURST_CNT_WIDTH, RID_WIDTH, WID_WIDTH and USER_WIDTH to
// whatever works in the AFU. The PIM will transform bursts into legal
// host channel requests.
`define HOST_CHAN_@GROUP@_AXI_MEM_PARAMS \
    .ADDR_WIDTH(ofs_plat_host_chan_@group@_pkg::ADDR_WIDTH_BYTES), \
    .DATA_WIDTH(ofs_plat_host_chan_@group@_pkg::DATA_WIDTH)

// AXI MMIO ofs_plat_axi_mem_lite_if parameters. In order to
// keep the MMIO representation general, independent of particular
// platform protocols, addresses are to bytes within the space. AFUs that
// deal only with aligned data can simply ignore the low address bits.
//
// The read ID field holds the tag and the index of the requested
// word on the bus.
`define HOST_CHAN_@GROUP@_AXI_MMIO_PARAMS(BUSWIDTH) \
    .ADDR_WIDTH(ofs_plat_host_chan_@group@_pkg::MMIO_ADDR_WIDTH_BYTES), \
    .DATA_WIDTH(BUSWIDTH), \
    .RID_WIDTH($clog2(BUSWIDTH / 32) + ccip_if_pkg::CCIP_TID_WIDTH)

`endif // __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AXI_MEM_RDWR__
