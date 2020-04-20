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

`ifndef __OFS_PLAT_AXI_MEM_IF_VH__
`define __OFS_PLAT_AXI_MEM_IF_VH__

//
// Macro for replicating properties of an ofs_plat_axi_mem_if when
// defininig another instance of the interface.
//
`define OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(AXI_IF) \
    .ADDR_WIDTH(AXI_IF.ADDR_WIDTH_), \
    .DATA_WIDTH(AXI_IF.DATA_WIDTH_), \
    .BURST_CNT_WIDTH(AXI_IF.BURST_CNT_WIDTH_), \
    .RID_WIDTH(AXI_IF.RID_WIDTH_), \
    .WID_WIDTH(AXI_IF.WID_WIDTH_), \
    .USER_WIDTH(AXI_IF.USER_WIDTH_)

`define OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(AXI_IF) \
    .ADDR_WIDTH(AXI_IF.ADDR_WIDTH_), \
    .DATA_WIDTH(AXI_IF.DATA_WIDTH_)


//
// Macro for replicating properties of an ofs_plat_axi_mem_lite_if when
// defininig another instance of the interface.
//
`define OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(AXI_IF) \
    .ADDR_WIDTH(AXI_IF.ADDR_WIDTH_), \
    .DATA_WIDTH(AXI_IF.DATA_WIDTH_), \
    .RID_WIDTH(AXI_IF.RID_WIDTH_), \
    .WID_WIDTH(AXI_IF.WID_WIDTH_), \
    .USER_WIDTH(AXI_IF.USER_WIDTH_)


// ========================================================================
//
//  Because they have the same port names, these macros will work with
//  both AXI memory and AXI lite memory interfaces.
//
// ========================================================================

//
// Ideally, the macros here would instead be tasks in the interface intself.
// Unfortunately, tasks within an interface can't use the interface as a
// parameter type. You can't build a task in an interface that operates on an
// instance of interface object. Instead, we resort to these ugly macros.
// Macros allow modules to operate without knowing some of the minor interface
// fields.
//

`define OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE_COMB(MEM_SLAVE, MEM_MASTER) \
    MEM_SLAVE.aw = MEM_MASTER.aw; \
    MEM_SLAVE.awvalid = MEM_MASTER.awvalid; \
    MEM_SLAVE.w = MEM_MASTER.w; \
    MEM_SLAVE.wvalid = MEM_MASTER.wvalid; \
    MEM_SLAVE.bready = MEM_MASTER.bready; \
    MEM_SLAVE.ar = MEM_MASTER.ar; \
    MEM_SLAVE.arvalid = MEM_MASTER.arvalid; \
    MEM_SLAVE.rready = MEM_MASTER.rready

`define OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE_FF(MEM_SLAVE, MEM_MASTER) \
    MEM_SLAVE.aw <= MEM_MASTER.aw; \
    MEM_SLAVE.awvalid <= MEM_MASTER.awvalid; \
    MEM_SLAVE.w <= MEM_MASTER.w; \
    MEM_SLAVE.wvalid <= MEM_MASTER.wvalid; \
    MEM_SLAVE.bready <= MEM_MASTER.bready; \
    MEM_SLAVE.ar <= MEM_MASTER.ar; \
    MEM_SLAVE.arvalid <= MEM_MASTER.arvalid; \
    MEM_SLAVE.rready <= MEM_MASTER.rready

`define OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER_COMB(MEM_MASTER, MEM_SLAVE) \
    MEM_MASTER.awready = MEM_SLAVE.awready; \
    MEM_MASTER.wready = MEM_SLAVE.wready; \
    MEM_MASTER.b = MEM_SLAVE.b; \
    MEM_MASTER.bvalid = MEM_SLAVE.bvalid; \
    MEM_MASTER.arready = MEM_SLAVE.arready; \
    MEM_MASTER.r = MEM_SLAVE.r; \
    MEM_MASTER.rvalid = MEM_SLAVE.rvalid

`define OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER_FF(MEM_MASTER, MEM_SLAVE) \
    MEM_MASTER.awready <= MEM_SLAVE.awready; \
    MEM_MASTER.wready <= MEM_SLAVE.wready; \
    MEM_MASTER.b <= MEM_SLAVE.b; \
    MEM_MASTER.bvalid <= MEM_SLAVE.bvalid; \
    MEM_MASTER.arready <= MEM_SLAVE.arready; \
    MEM_MASTER.r <= MEM_SLAVE.r; \
    MEM_MASTER.rvalid <= MEM_SLAVE.rvalid


//
// Initialization macros.
//

`define OFS_PLAT_AXI_MEM_IF_INIT_MASTER_COMB(MEM_MASTER) \
    MEM_MASTER.aw = '0; \
    MEM_MASTER.awvalid = 1'b0; \
    MEM_MASTER.w = '0; \
    MEM_MASTER.wvalid = 1'b0; \
    MEM_MASTER.bready = 1'b0; \
    MEM_MASTER.ar = '0; \
    MEM_MASTER.arvalid = 1'b0; \
    MEM_MASTER.rready = 1'b0

`define OFS_PLAT_AXI_MEM_IF_INIT_MASTER_FF(MEM_MASTER) \
    MEM_MASTER.aw <= '0; \
    MEM_MASTER.awvalid <= 1'b0; \
    MEM_MASTER.w <= '0; \
    MEM_MASTER.wvalid <= 1'b0; \
    MEM_MASTER.bready <= 1'b0; \
    MEM_MASTER.ar <= '0; \
    MEM_MASTER.arvalid <= 1'b0; \
    MEM_MASTER.rready <= 1'b0

`define OFS_PLAT_AXI_MEM_IF_INIT_SLAVE_COMB(MEM_SLAVE) \
    MEM_SLAVE.awready = 1'b0; \
    MEM_SLAVE.wready = 1'b0; \
    MEM_SLAVE.b = '0; \
    MEM_SLAVE.bvalid = 1'b0; \
    MEM_SLAVE.arready = 1'b0; \
    MEM_SLAVE.r = '0; \
    MEM_SLAVE.rvalid = 1'b0

`define OFS_PLAT_AXI_MEM_IF_INIT_SLAVE_FF(MEM_SLAVE) \
    MEM_SLAVE.awready <= 1'b0; \
    MEM_SLAVE.wready <= 1'b0; \
    MEM_SLAVE.b <= '0; \
    MEM_SLAVE.bvalid <= 1'b0; \
    MEM_SLAVE.arready <= 1'b0; \
    MEM_SLAVE.r <= '0; \
    MEM_SLAVE.rvalid <= 1'b0


`endif // __OFS_PLAT_AXI_MEM_IF_VH__
