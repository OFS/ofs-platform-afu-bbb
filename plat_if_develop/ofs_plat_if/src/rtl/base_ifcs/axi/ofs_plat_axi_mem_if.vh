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
// defining another instance of the interface.
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

// Replicate all parameters except tags (RID, WID, USER)
`define OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS_EXCEPT_TAGS(AXI_IF) \
    .ADDR_WIDTH(AXI_IF.ADDR_WIDTH_), \
    .DATA_WIDTH(AXI_IF.DATA_WIDTH_), \
    .BURST_CNT_WIDTH(AXI_IF.BURST_CNT_WIDTH_)


//
// Macro for replicating properties of an ofs_plat_axi_mem_lite_if when
// defining another instance of the interface.
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


`define OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE) \
    MEM_SINK.aw OPER MEM_SOURCE.aw; \
    MEM_SINK.awvalid OPER MEM_SOURCE.awvalid; \
    MEM_SINK.w OPER MEM_SOURCE.w; \
    MEM_SINK.wvalid OPER MEM_SOURCE.wvalid; \
    MEM_SINK.bready OPER MEM_SOURCE.bready; \
    MEM_SINK.ar OPER MEM_SOURCE.ar; \
    MEM_SINK.arvalid OPER MEM_SOURCE.arvalid; \
    MEM_SINK.rready OPER MEM_SOURCE.rready

`define OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)

`define OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)

 // Old naming, maintained for compatibility
`define OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE(MEM_SINK, OPER, MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE)
`define OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)
`define OFS_PLAT_AXI_MEM_IF_FROM_MASTER_TO_SLAVE_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)


`define OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, OPER, MEM_SINK) \
    MEM_SOURCE.awready OPER MEM_SINK.awready; \
    MEM_SOURCE.wready OPER MEM_SINK.wready; \
    MEM_SOURCE.b OPER MEM_SINK.b; \
    MEM_SOURCE.bvalid OPER MEM_SINK.bvalid; \
    MEM_SOURCE.arready OPER MEM_SINK.arready; \
    MEM_SOURCE.r OPER MEM_SINK.r; \
    MEM_SOURCE.rvalid OPER MEM_SINK.rvalid

`define OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE_COMB(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, =, MEM_SINK)

`define OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE_FF(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, <=, MEM_SINK)

 // Old naming, maintained for compatibility
`define OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER(MEM_SOURCE, OPER, MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, OPER, MEM_SINK) \
`define OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER_COMB(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, =, MEM_SINK)
`define OFS_PLAT_AXI_MEM_IF_FROM_SLAVE_TO_MASTER_FF(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, <=, MEM_SINK)


//
// Initialization macros.
//

`define OFS_PLAT_AXI_MEM_IF_INIT_SOURCE(MEM_SOURCE, OPER) \
    MEM_SOURCE.aw OPER '0; \
    MEM_SOURCE.awvalid OPER 1'b0; \
    MEM_SOURCE.w OPER '0; \
    MEM_SOURCE.wvalid OPER 1'b0; \
    MEM_SOURCE.bready OPER 1'b0; \
    MEM_SOURCE.ar OPER '0; \
    MEM_SOURCE.arvalid OPER 1'b0; \
    MEM_SOURCE.rready OPER 1'b0

`define OFS_PLAT_AXI_MEM_IF_INIT_SOURCE_COMB(MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SOURCE(MEM_SOURCE, =)
`define OFS_PLAT_AXI_MEM_IF_INIT_SOURCE_FF(MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SOURCE(MEM_SOURCE, <=)

 // Old naming, maintained for compatibility
`define OFS_PLAT_AXI_MEM_IF_INIT_MASTER(MEM_SOURCE, OPER) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SOURCE(MEM_SOURCE, OPER)
`define OFS_PLAT_AXI_MEM_IF_INIT_MASTER_COMB(MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SOURCE(MEM_SOURCE, =)
`define OFS_PLAT_AXI_MEM_IF_INIT_MASTER_FF(MEM_SOURCE) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SOURCE(MEM_SOURCE, <=)


`define OFS_PLAT_AXI_MEM_IF_INIT_SINK(MEM_SINK, OPER) \
    MEM_SINK.awready OPER 1'b0; \
    MEM_SINK.wready OPER 1'b0; \
    MEM_SINK.b OPER '0; \
    MEM_SINK.bvalid OPER 1'b0; \
    MEM_SINK.arready OPER 1'b0; \
    MEM_SINK.r OPER '0; \
    MEM_SINK.rvalid OPER 1'b0

`define OFS_PLAT_AXI_MEM_IF_INIT_SINK_COMB(MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SINK(MEM_SINK, =)

`define OFS_PLAT_AXI_MEM_IF_INIT_SINK_FF(MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SINK(MEM_SINK, <=)

 // Old naming, maintained for compatibility
`define OFS_PLAT_AXI_MEM_IF_INIT_SLAVE(MEM_SINK, OPER) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SINK(MEM_SINK, OPER)
`define OFS_PLAT_AXI_MEM_IF_INIT_SLAVE_COMB(MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SINK(MEM_SINK, =)
`define OFS_PLAT_AXI_MEM_IF_INIT_SLAVE_FF(MEM_SINK) \
    `OFS_PLAT_AXI_MEM_IF_INIT_SINK(MEM_SINK, <=)


//
// Field-by-field copies of structs, needed when source and sink have
// different field widths.
//

`define OFS_PLAT_AXI_MEM_IF_COPY_AW(MEM_SINK_AW, OPER, MEM_SOURCE_AW) \
    MEM_SINK_AW.id OPER MEM_SOURCE_AW.id; \
    MEM_SINK_AW.addr OPER MEM_SOURCE_AW.addr; \
    MEM_SINK_AW.len OPER MEM_SOURCE_AW.len; \
    MEM_SINK_AW.size OPER MEM_SOURCE_AW.size; \
    MEM_SINK_AW.burst OPER MEM_SOURCE_AW.burst; \
    MEM_SINK_AW.lock OPER MEM_SOURCE_AW.lock; \
    MEM_SINK_AW.cache OPER MEM_SOURCE_AW.cache; \
    MEM_SINK_AW.prot OPER MEM_SOURCE_AW.prot; \
    MEM_SINK_AW.user OPER MEM_SOURCE_AW.user; \
    MEM_SINK_AW.qos OPER MEM_SOURCE_AW.qos; \
    MEM_SINK_AW.region OPER MEM_SOURCE_AW.region; \
    MEM_SINK_AW.atop OPER MEM_SOURCE_AW.atop

`define OFS_PLAT_AXI_MEM_IF_COPY_W(MEM_SINK_W, OPER, MEM_SOURCE_W) \
    MEM_SINK_W.data OPER MEM_SOURCE_W.data; \
    MEM_SINK_W.strb OPER MEM_SOURCE_W.strb; \
    MEM_SINK_W.last OPER MEM_SOURCE_W.last; \
    MEM_SINK_W.user OPER MEM_SOURCE_W.user

`define OFS_PLAT_AXI_MEM_IF_COPY_AR(MEM_SINK_AR, OPER, MEM_SOURCE_AR) \
    MEM_SINK_AR.id OPER MEM_SOURCE_AR.id; \
    MEM_SINK_AR.addr OPER MEM_SOURCE_AR.addr; \
    MEM_SINK_AR.len OPER MEM_SOURCE_AR.len; \
    MEM_SINK_AR.size OPER MEM_SOURCE_AR.size; \
    MEM_SINK_AR.burst OPER MEM_SOURCE_AR.burst; \
    MEM_SINK_AR.lock OPER MEM_SOURCE_AR.lock; \
    MEM_SINK_AR.cache OPER MEM_SOURCE_AR.cache; \
    MEM_SINK_AR.prot OPER MEM_SOURCE_AR.prot; \
    MEM_SINK_AR.user OPER MEM_SOURCE_AR.user; \
    MEM_SINK_AR.qos OPER MEM_SOURCE_AR.qos; \
    MEM_SINK_AR.region OPER MEM_SOURCE_AR.region

`define OFS_PLAT_AXI_MEM_IF_COPY_B(MEM_SOURCE_B, OPER, MEM_SINK_B) \
    MEM_SOURCE_B.id OPER MEM_SINK_B.id; \
    MEM_SOURCE_B.resp OPER MEM_SINK_B.resp; \
    MEM_SOURCE_B.user OPER MEM_SINK_B.user

`define OFS_PLAT_AXI_MEM_IF_COPY_R(MEM_SOURCE_R, OPER, MEM_SINK_R) \
    MEM_SOURCE_R.id OPER MEM_SINK_R.id; \
    MEM_SOURCE_R.data OPER MEM_SINK_R.data; \
    MEM_SOURCE_R.resp OPER MEM_SINK_R.resp; \
    MEM_SOURCE_R.user OPER MEM_SINK_R.user; \
    MEM_SOURCE_R.last OPER MEM_SINK_R.last


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
