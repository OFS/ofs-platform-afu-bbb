// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Platform-independent configuration details for host channels, available
// on any platform.
//

package ofs_plat_host_chan_@group@_pkg;

    localparam NUM_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_NUM_PORTS;

    localparam DATA_WIDTH = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_DATA_WIDTH;
    localparam DATA_WIDTH_BYTES = DATA_WIDTH / 8;

    // Address width to address lines (DATA_WIDTH)
    localparam ADDR_WIDTH_LINES = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_ADDR_WIDTH;
    // Address width to address bytes
    localparam ADDR_WIDTH_BYTES = ADDR_WIDTH_LINES + $clog2(DATA_WIDTH_BYTES);

    // AFU's MMIO address size (byte-level, despite PCIe using 32 bit
    // DWORD granularity.
    localparam MMIO_ADDR_WIDTH_BYTES = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MMIO_ADDR_WIDTH;
    localparam MMIO_DATA_WIDTH = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MMIO_DATA_WIDTH;

    // Non-zero when 512 bit MMIO writes are supported
    localparam MMIO_512_WRITE_SUPPORTED = 1;

endpackage
