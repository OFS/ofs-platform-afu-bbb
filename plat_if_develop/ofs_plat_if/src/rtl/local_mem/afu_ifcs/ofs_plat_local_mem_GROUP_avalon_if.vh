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

`ifndef __OFS_PLAT_LOCAL_MEM_GROUP_AVALON_IF_VH__
`define __OFS_PLAT_LOCAL_MEM_GROUP_AVALON_IF_VH__

//
// Templates for defining parameters of possible local memory interface classes.
// These are independent of the actual class of the local memory interface
// coming out of the FIU. Instead, they are aids in defining the interface
// desired by the AFU. The macros match the target interface parameters to
// the interface from the FIU.
//

//
//  Local memory as an Avalon interface. Typical definition:
//
//     ofs_plat_avalon_mem_if
//       #(
//         `OFS_PLAT_LOCAL_MEM_GROUP_AS_AVALON_IF_PARAMS
//         )
//       local_mem_to_afu[local_mem_GROUP_cfg_pkg::LOCAL_MEM_NUM_BANKS]();
//
`define OFS_PLAT_LOCAL_MEM_GROUP_AS_AVALON_IF_PARAMS \
    .NUM_INSTANCES(local_mem_GROUP_cfg_pkg::LOCAL_MEM_NUM_BANKS), \
    .ADDR_WIDTH(local_mem_GROUP_cfg_pkg::LOCAL_MEM_ADDR_WIDTH), \
    .DATA_WIDTH(local_mem_GROUP_cfg_pkg::LOCAL_MEM_DATA_WIDTH), \
    .BURST_CNT_WIDTH(local_mem_GROUP_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH)

`endif // __OFS_PLAT_LOCAL_MEM_GROUP_AVALON_IF_VH__
