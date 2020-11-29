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

`ifndef __OFS_PLAT_LOCAL_MEM_@GROUP@_AXI_MEM_VH__
`define __OFS_PLAT_LOCAL_MEM_@GROUP@_AXI_MEM_VH__

//
// Templates for defining parameters of possible local memory interface classes.
// These are independent of the actual class of the local memory interface
// coming out of the FIU. Instead, they are aids in defining the interface
// desired by the AFU. The macros match the target interface parameters to
// the interface from the FIU.
//

//
// Local memory as an AXI interface with all but the burst count
// defined. The AFU is expected to specify its desired burst count
// and the PIM will instantiate a gearbox to translate from AFU bursts
// to platform bursts. See below for a macro variant that specifies
// the platform-specific burst size.
//
// A single interface may be defined or, more commonly, a vector
// of interfaces -- one per bank:
//
//   ofs_plat_axi_mem_if
//     #(
//       `LOCAL_MEM_@GROUP@_AXI_MEM_PARAMS
//       )
//     local_mem_to_afu[local_mem_@group@_cfg_pkg::LOCAL_MEM_NUM_BANKS]();
//
// ID fields are included in the definition because the fields
// may reach all the way to the FIM's native AXI memory implementaiton.
// Allowing an AFU to pick wider fields could result in lost ID
// data.
`define LOCAL_MEM_@GROUP@_AXI_MEM_PARAMS \
    .ADDR_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_BYTE_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_DATA_WIDTH), \
    .RID_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_RID_WIDTH), \
    .WID_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_WID_WIDTH)

// The default AXI interface exposes only data bits, not ECC. This
// version exposes ECC along with data, calling it all "data".
// These extra bits are not part of the AXI byte-based linear address
// space. Consider them more as metadata associated with each line
// of data in memory, accessible along with the rest of the line.
`define LOCAL_MEM_@GROUP@_AXI_MEM_PARAMS_FULL_BUS \
    .ADDR_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_BYTE_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH), \
    .RID_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_RID_WIDTH), \
    .WID_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_WID_WIDTH), \
    .MASKED_SYMBOL_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH)

//
// Variant of the standard parameters, including burst count width. The
// width in local_mem_@group@_cfg_pkg is the Avalon style, so subtract one
// for AXI.
//
`define LOCAL_MEM_@GROUP@_AXI_MEM_PARAMS_DEFAULT \
    .ADDR_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_BYTE_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_DATA_WIDTH), \
    .RID_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_RID_WIDTH), \
    .WID_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_WID_WIDTH), \
    .BURST_CNT_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH-1)

`define LOCAL_MEM_@GROUP@_AXI_MEM_PARAMS_FULL_BUS_DEFAULT \
    .ADDR_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_BYTE_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH), \
    .RID_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_RID_WIDTH), \
    .WID_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_WID_WIDTH), \
    .MASKED_SYMBOL_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH), \
    .BURST_CNT_WIDTH(local_mem_@group@_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH-1)

`endif // __OFS_PLAT_LOCAL_MEM_@GROUP@_AXI_MEM_VH__
