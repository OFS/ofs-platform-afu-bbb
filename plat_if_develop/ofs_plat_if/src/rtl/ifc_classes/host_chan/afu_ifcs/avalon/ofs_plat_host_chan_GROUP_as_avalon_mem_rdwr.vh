// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AVALON_MEM_RDWR__
`define __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AVALON_MEM_RDWR__

//
// Macros for setting parameters to Avalon split-bus read/write interfaces.
//

// Avalon host memory ofs_plat_avalon_mem_rdwr_if parameters.
// AFUs may set BURST_CNT_WIDTH to whatever works in the AFU. The PIM will
// transform bursts into legal native host channel requests.
`define HOST_CHAN_@GROUP@_AVALON_MEM_RDWR_PARAMS \
    .ADDR_WIDTH(ofs_plat_host_chan_@group@_pkg::ADDR_WIDTH_LINES), \
    .DATA_WIDTH(ofs_plat_host_chan_@group@_pkg::DATA_WIDTH)

// Avalon MMIO ofs_plat_avalon_mem_if parameters. For Avalon MMIO
// we encode the address as the index of BUSWIDTH-sized words in the
// MMIO space. For example, for 64 bit BUSWIDTH address 1 is the second
// 64 bit word in MMIO space. Smaller requests in the MMIO space use
// byteenable.
`define HOST_CHAN_@GROUP@_AVALON_MMIO_PARAMS(BUSWIDTH) \
    .ADDR_WIDTH(ofs_plat_host_chan_@group@_pkg::MMIO_ADDR_WIDTH_BYTES - $clog2(BUSWIDTH/8)), \
    .DATA_WIDTH(BUSWIDTH), \
    .BURST_CNT_WIDTH(1)


`endif // __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AVALON_MEM_RDWR__
