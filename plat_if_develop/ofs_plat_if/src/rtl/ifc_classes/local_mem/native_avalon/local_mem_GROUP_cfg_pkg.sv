//
// Copyright (c) 2017, Intel Corporation
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

`include "ofs_plat_if_top_config.vh"

package local_mem_@group@_cfg_pkg;

    localparam LOCAL_MEM_VERSION_NUMBER = 1;

    localparam LOCAL_MEM_NUM_BANKS = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_NUM_BANKS;

    // LOCAL_MEM_ADDR_WIDTH is always the line index, ignore byte offsets, independent
    // of Avalon vs. AXI. Avalon uses this directly. AXI uses byte address width below.
    localparam LOCAL_MEM_ADDR_WIDTH = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_ADDR_WIDTH;
    localparam LOCAL_MEM_DATA_WIDTH = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_DATA_WIDTH;
    localparam LOCAL_MEM_ECC_WIDTH = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_ECC_WIDTH;

    // Memory controllers may expose memory available for ECC by making
    // the bus wider.
    localparam LOCAL_MEM_FULL_BUS_WIDTH = LOCAL_MEM_DATA_WIDTH + LOCAL_MEM_ECC_WIDTH;
    // The memory controller may either expose ECC bits as extra data
    // bytes, in which case masked writes tend to treat them as normal
    // 8 bit data, or as parity bits. In the 8 bit data case, the mask
    // is widened to match data_width+ecc_width as 8 bit symbols. In
    // the parity case, the number of masks is unchanged. Instead,
    // each mask bit covers more than 8 bits of data.
    localparam LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MASKED_FULL_SYMBOL_WIDTH;

    localparam LOCAL_MEM_BURST_CNT_WIDTH = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_BURST_CNT_WIDTH;

    // Number of bytes in a data line
    localparam LOCAL_MEM_DATA_N_BYTES = LOCAL_MEM_DATA_WIDTH / 8;
    localparam LOCAL_MEM_FULL_BUS_N_BYTES = LOCAL_MEM_FULL_BUS_WIDTH / LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH;

    localparam LOCAL_MEM_LINE_ADDR_WIDTH = LOCAL_MEM_ADDR_WIDTH;
    localparam LOCAL_MEM_BYTE_ADDR_WIDTH = LOCAL_MEM_ADDR_WIDTH + $clog2(LOCAL_MEM_DATA_N_BYTES);

    // User bits are organized with { AFU user bits, FIM user bits, PIM user bits }.
    // Only the FIM's user width is in the macro.
    localparam LOCAL_MEM_USER_WIDTH = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_USER_WIDTH +
                                      ofs_plat_local_mem_avalon_mem_pkg::LM_AVALON_UFLAG_WIDTH;

    // The native Avalon interface doesn't define these AXI parameters
    localparam LOCAL_MEM_RID_WIDTH = 8;
    localparam LOCAL_MEM_WID_WIDTH = 8;


    // Base types
    // --------------------------------------------------------------------

    typedef logic [LOCAL_MEM_ADDR_WIDTH-1:0] t_local_mem_addr;
    typedef logic [LOCAL_MEM_DATA_WIDTH-1:0] t_local_mem_data;
    typedef logic [LOCAL_MEM_ECC_WIDTH-1:0] t_local_mem_ecc;
    typedef logic [LOCAL_MEM_FULL_BUS_WIDTH-1:0] t_local_mem_full_bus;

    typedef logic [LOCAL_MEM_BURST_CNT_WIDTH-1:0] t_local_mem_burst_cnt;

    // Byte-level mask of a data line
    typedef logic [LOCAL_MEM_DATA_N_BYTES-1:0] t_local_mem_byte_mask;
    typedef logic [LOCAL_MEM_FULL_BUS_N_BYTES-1:0] t_local_mem_bus_byte_mask;

endpackage // local_mem_@group@_cfg_pkg
