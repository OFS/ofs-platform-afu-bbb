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

    // Work out whether the MMIO interface supports 512 bit writes
`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
    // The PCIe SS AXI-Lite CSR does not support 512 bit MMIO writes
    localparam MMIO_512_WRITE_SUPPORTED = 0;
`else
    localparam MMIO_512_WRITE_SUPPORTED = 1;
`endif

endpackage
