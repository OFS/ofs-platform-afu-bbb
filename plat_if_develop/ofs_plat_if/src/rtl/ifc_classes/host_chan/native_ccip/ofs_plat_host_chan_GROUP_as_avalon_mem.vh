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

`ifndef __OFS_PLAT_HOST_CHAN_XGROUPX_AS_AVALON_MEM__
`define __OFS_PLAT_HOST_CHAN_XGROUPX_AS_AVALON_MEM__

//
// Macros for setting parameters to Avalon interfaces.
//

// CCI-P to Avalon host memory ofs_plat_avalon_mem_rdwr_if parameters.
// AFUs may set BURST_CNT_WIDTH to whatever works in the AFU. The PIM will
// transform bursts into legal CCI-P requests.
`define HOST_CHAN_XGROUPX_AVALON_MEM_PARAMS \
    .ADDR_WIDTH(ccip_if_pkg::CCIP_CLADDR_WIDTH), \
    .DATA_WIDTH(ccip_if_pkg::CCIP_CLDATA_WIDTH)

// CCI-P to Avalon MMIO ofs_plat_avalon_mem_if parameters. Transform the address
// width from the CCI-P DWORD index to the specified bus width.
`define HOST_CHAN_XGROUPX_AVALON_MMIO_PARAMS(BUSWIDTH) \
    .ADDR_WIDTH(ccip_if_pkg::CCIP_MMIOADDR_WIDTH - $clog2(BUSWIDTH/32)), \
    .DATA_WIDTH(BUSWIDTH), \
    .BURST_CNT_WIDTH(1)


`endif // __OFS_PLAT_HOST_CHAN_XGROUPX_AS_AVALON_MEM__
