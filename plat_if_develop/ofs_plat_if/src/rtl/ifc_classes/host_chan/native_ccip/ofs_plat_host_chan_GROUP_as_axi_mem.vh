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

`ifndef __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AXI_MEM_RDWR__
`define __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AXI_MEM_RDWR__

//
// Macros for setting parameters to AXI memory interfaces.
//

// CCI-P to AXI host memory ofs_plat_axi_mem_if parameters.
// AFUs may set BURST_CNT_WIDTH, RID_WIDTH, WID_WIDTH and USER_WIDTH to
// whatever works in the AFU. The PIM will transform bursts into legal
// CCI-P requests.
`define HOST_CHAN_@GROUP@_AXI_MEM_PARAMS \
    .ADDR_WIDTH(ccip_if_pkg::CCIP_CLADDR_WIDTH + $clog2(ccip_if_pkg::CCIP_CLDATA_BYTE_WIDTH)), \
    .DATA_WIDTH(ccip_if_pkg::CCIP_CLDATA_WIDTH)

// CCI-P to AXI MMIO ofs_plat_axi_mem_lite_if parameters. In order to
// keep the MMIO representation general, independent of particular
// platform protocols, addresses are to bytes within the space. AFUs that
// deal only with aligned data can simply ignore the low address bits.
// CCI-P's MMIO addresses are to 32 bit words, so 2 low bits of address
// are added here. On native CCI-P platforms these bits will always be 0.
//
// The read ID field holds the CCI-P tid and the index of the requested
// word on the bus. CCI-P minimum addressable MMIO size is 32 bits.
`define HOST_CHAN_@GROUP@_AXI_MMIO_PARAMS(BUSWIDTH) \
    .ADDR_WIDTH(ccip_if_pkg::CCIP_MMIOADDR_WIDTH + 2), \
    .DATA_WIDTH(BUSWIDTH), \
    .RID_WIDTH($clog2(BUSWIDTH / 32) + ccip_if_pkg::CCIP_TID_WIDTH)

`endif // __OFS_PLAT_HOST_CHAN_@GROUP@_AS_AXI_MEM_RDWR__
