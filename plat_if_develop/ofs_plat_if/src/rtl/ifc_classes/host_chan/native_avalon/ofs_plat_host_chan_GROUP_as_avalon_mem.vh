// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AVALON_MEM__
`define __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AVALON_MEM__

//
// Macros for setting parameters to Avalon interfaces.
//

// AFUs may set BURST_CNT_WIDTH to whatever works in the AFU. The PIM will
// transform bursts into legal platform requests.
`define HOST_CHAN_@GROUP@_AVALON_MEM_PARAMS \
    .ADDR_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_ADDR_WIDTH), \
    .DATA_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_DATA_WIDTH)

`define HOST_CHAN_@GROUP@_AVALON_MEM_RDWR_PARAMS \
    .ADDR_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_ADDR_WIDTH), \
    .DATA_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_DATA_WIDTH)

`endif // __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AVALON_MEM__
