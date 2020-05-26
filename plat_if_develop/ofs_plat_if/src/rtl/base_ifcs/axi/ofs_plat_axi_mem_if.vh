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
// General copy macros take OPER so the macro can be used in both combinational
// and registered contexts. Specify an operator: usually = or <=.
//


`define OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE(MEM_SLAVE, OPER, MEM_MASTER) \
    MEM_SLAVE.aw OPER MEM_MASTER.aw; \
    MEM_SLAVE.awvalid OPER MEM_MASTER.awvalid; \
    MEM_SLAVE.w OPER MEM_MASTER.w; \
    MEM_SLAVE.wvalid OPER MEM_MASTER.wvalid; \
    MEM_SLAVE.bready OPER MEM_MASTER.bready; \
    MEM_SLAVE.ar OPER MEM_MASTER.ar; \
    MEM_SLAVE.arvalid OPER MEM_MASTER.arvalid; \
    MEM_SLAVE.rready OPER MEM_MASTER.rready

`define OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE_COMB(MEM_SLAVE, MEM_MASTER) \
    `OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE(MEM_SLAVE, =, MEM_MASTER)

`define OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE_FF(MEM_SLAVE, MEM_MASTER) \
    `OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE(MEM_SLAVE, <=, MEM_MASTER)


`define OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER(MEM_MASTER, OPER, MEM_SLAVE) \
    MEM_MASTER.awready OPER MEM_SLAVE.awready; \
    MEM_MASTER.wready OPER MEM_SLAVE.wready; \
    MEM_MASTER.b OPER MEM_SLAVE.b; \
    MEM_MASTER.bvalid OPER MEM_SLAVE.bvalid; \
    MEM_MASTER.arready OPER MEM_SLAVE.arready; \
    MEM_MASTER.r OPER MEM_SLAVE.r; \
    MEM_MASTER.rvalid OPER MEM_SLAVE.rvalid

`define OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER_COMB(MEM_MASTER, MEM_SLAVE) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER(MEM_MASTER, =, MEM_SLAVE)

`define OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER_FF(MEM_MASTER, MEM_SLAVE) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER(MEM_MASTER, <=, MEM_SLAVE)


//
// Initialization macros.
//

`define OFS_PLAT_AXI_MEM_IF_INIT_MASTER(MEM_MASTER, OPER) \
    MEM_MASTER.aw OPER '0; \
    MEM_MASTER.awvalid OPER 1'b0; \
    MEM_MASTER.w OPER '0; \
    MEM_MASTER.wvalid OPER 1'b0; \
    MEM_MASTER.bready OPER 1'b0; \
    MEM_MASTER.ar OPER '0; \
    MEM_MASTER.arvalid OPER 1'b0; \
    MEM_MASTER.rready OPER 1'b0

`define OFS_PLAT_AXI_MEM_IF_INIT_MASTER_COMB(MEM_MASTER) \
    `OFS_PLAT_AXI_MEM_IF_INIT_MASTER(MEM_MASTER, =)

`define OFS_PLAT_AXI_MEM_IF_INIT_MASTER_FF(MEM_MASTER) \
    `OFS_PLAT_AXI_MEM_IF_INIT_MASTER(MEM_MASTER, <=)


`define OFS_PLAT_AXI_MEM_IF_INIT_SLAVE(MEM_SLAVE, OPER) \
    MEM_SLAVE.awready OPER 1'b0; \
    MEM_SLAVE.wready OPER 1'b0; \
    MEM_SLAVE.b OPER '0; \
    MEM_SLAVE.bvalid OPER 1'b0; \
    MEM_SLAVE.arready OPER 1'b0; \
    MEM_SLAVE.r OPER '0; \
    MEM_SLAVE.rvalid OPER 1'b0

`define OFS_PLAT_AXI_MEM_IF_INIT_SLAVE_COMB(MEM_SLAVE) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SLAVE(MEM_SLAVE, =)

`define OFS_PLAT_AXI_MEM_IF_INIT_SLAVE_FF(MEM_SLAVE) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SLAVE(MEM_SLAVE, <=)


//
// Field-by-field copies of structs, needed when master and slave have
// different field widths.
//

`define OFS_PLAT_AXI_MEM_IF_COPY_AW(MEM_SLAVE_AW, OPER, MEM_MASTER_AW) \
    MEM_SLAVE_AW.id OPER MEM_MASTER_AW.id; \
    MEM_SLAVE_AW.addr OPER MEM_MASTER_AW.addr; \
    MEM_SLAVE_AW.len OPER MEM_MASTER_AW.len; \
    MEM_SLAVE_AW.size OPER MEM_MASTER_AW.size; \
    MEM_SLAVE_AW.burst OPER MEM_MASTER_AW.burst; \
    MEM_SLAVE_AW.lock OPER MEM_MASTER_AW.lock; \
    MEM_SLAVE_AW.cache OPER MEM_MASTER_AW.cache; \
    MEM_SLAVE_AW.prot OPER MEM_MASTER_AW.prot; \
    MEM_SLAVE_AW.user OPER MEM_MASTER_AW.user; \
    MEM_SLAVE_AW.qos OPER MEM_MASTER_AW.qos; \
    MEM_SLAVE_AW.region OPER MEM_MASTER_AW.region; \
    MEM_SLAVE_AW.atop OPER MEM_MASTER_AW.atop

`define OFS_PLAT_AXI_MEM_IF_COPY_W(MEM_SLAVE_W, OPER, MEM_MASTER_W) \
    MEM_SLAVE_W.data OPER MEM_MASTER_W.data; \
    MEM_SLAVE_W.strb OPER MEM_MASTER_W.strb; \
    MEM_SLAVE_W.last OPER MEM_MASTER_W.last; \
    MEM_SLAVE_W.user OPER MEM_MASTER_W.user

`define OFS_PLAT_AXI_MEM_IF_COPY_AR(MEM_SLAVE_AR, OPER, MEM_MASTER_AR) \
    MEM_SLAVE_AR.id OPER MEM_MASTER_AR.id; \
    MEM_SLAVE_AR.addr OPER MEM_MASTER_AR.addr; \
    MEM_SLAVE_AR.len OPER MEM_MASTER_AR.len; \
    MEM_SLAVE_AR.size OPER MEM_MASTER_AR.size; \
    MEM_SLAVE_AR.burst OPER MEM_MASTER_AR.burst; \
    MEM_SLAVE_AR.lock OPER MEM_MASTER_AR.lock; \
    MEM_SLAVE_AR.cache OPER MEM_MASTER_AR.cache; \
    MEM_SLAVE_AR.prot OPER MEM_MASTER_AR.prot; \
    MEM_SLAVE_AR.user OPER MEM_MASTER_AR.user; \
    MEM_SLAVE_AR.qos OPER MEM_MASTER_AR.qos; \
    MEM_SLAVE_AR.region OPER MEM_MASTER_AR.region

`define OFS_PLAT_AXI_MEM_IF_COPY_B(MEM_MASTER_B, OPER, MEM_SLAVE_B) \
    MEM_MASTER_B.id OPER MEM_SLAVE_B.id; \
    MEM_MASTER_B.resp OPER MEM_SLAVE_B.resp; \
    MEM_MASTER_B.user OPER MEM_SLAVE_B.user

`define OFS_PLAT_AXI_MEM_IF_COPY_R(MEM_MASTER_R, OPER, MEM_SLAVE_R) \
    MEM_MASTER_R.id OPER MEM_SLAVE_R.id; \
    MEM_MASTER_R.data OPER MEM_SLAVE_R.data; \
    MEM_MASTER_R.resp OPER MEM_SLAVE_R.resp; \
    MEM_MASTER_R.user OPER MEM_SLAVE_R.user; \
    MEM_MASTER_R.last OPER MEM_SLAVE_R.last


//
// Standard validation macros. Copying using structs maps data incorrectly
// if the parameters to a pair of interfaces are different. Standard checks
// for incompatibility raise simulation-time errors.
//

`define OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(MEM_IFC0, MEM_IFC1) \
    initial \
    begin \
        if (MEM_IFC0.ADDR_WIDTH != MEM_IFC1.ADDR_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface ADDR_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.ADDR_WIDTH, MEM_IFC1.ADDR_WIDTH); \
        if (MEM_IFC0.DATA_WIDTH != MEM_IFC1.DATA_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface DATA_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.DATA_WIDTH, MEM_IFC1.DATA_WIDTH); \
        if (MEM_IFC0.BURST_CNT_WIDTH != MEM_IFC1.BURST_CNT_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface BURST_CNT_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.BURST_CNT_WIDTH, MEM_IFC1.BURST_CNT_WIDTH); \
        if (MEM_IFC0.RID_WIDTH != MEM_IFC1.RID_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface RID_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.RID_WIDTH, MEM_IFC1.RID_WIDTH); \
        if (MEM_IFC0.WID_WIDTH != MEM_IFC1.WID_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface WID_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.WID_WIDTH, MEM_IFC1.WID_WIDTH); \
        if (MEM_IFC0.USER_WIDTH != MEM_IFC1.USER_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface USER_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.USER_WIDTH, MEM_IFC1.USER_WIDTH); \
        if (MEM_IFC0.MASKED_SYMBOL_WIDTH != MEM_IFC1.MASKED_SYMBOL_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface MASKED_SYMBOL_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.MASKED_SYMBOL_WIDTH, MEM_IFC1.MASKED_SYMBOL_WIDTH); \
    end

`define OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(MEM_IFC0, MEM_IFC1) \
    initial \
    begin \
        if (MEM_IFC0.ADDR_WIDTH != MEM_IFC1.ADDR_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface ADDR_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.ADDR_WIDTH, MEM_IFC1.ADDR_WIDTH); \
        if (MEM_IFC0.DATA_WIDTH != MEM_IFC1.DATA_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface DATA_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.DATA_WIDTH, MEM_IFC1.DATA_WIDTH); \
        if (MEM_IFC0.RID_WIDTH != MEM_IFC1.RID_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface RID_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.RID_WIDTH, MEM_IFC1.RID_WIDTH); \
        if (MEM_IFC0.WID_WIDTH != MEM_IFC1.WID_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface WID_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.WID_WIDTH, MEM_IFC1.WID_WIDTH); \
        if (MEM_IFC0.USER_WIDTH != MEM_IFC1.USER_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-MM interface USER_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.USER_WIDTH, MEM_IFC1.USER_WIDTH); \
    end


`endif // __OFS_PLAT_AXI_MEM_IF_VH__
