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

`ifndef __OFS_PLAT_AVALON_MEM_IF_VH__
`define __OFS_PLAT_AVALON_MEM_IF_VH__

//
// Macro for replicating properties of an ofs_plat_avalon_mem_if when
// defininig another instance of the interface.
//
`define OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(AVALON_IF) \
    .ADDR_WIDTH(AVALON_IF.ADDR_WIDTH_), \
    .DATA_WIDTH(AVALON_IF.DATA_WIDTH_), \
    .MASKED_SYMBOL_WIDTH(AVALON_IF.MASKED_SYMBOL_WIDTH_), \
    .BURST_CNT_WIDTH(AVALON_IF.BURST_CNT_WIDTH_), \
    .USER_WIDTH(AVALON_IF.USER_WIDTH_)

`define OFS_PLAT_AVALON_MEM_IF_REPLICATE_MEM_PARAMS(AVALON_IF) \
    .ADDR_WIDTH(AVALON_IF.ADDR_WIDTH_), \
    .DATA_WIDTH(AVALON_IF.DATA_WIDTH_), \
    .MASKED_SYMBOL_WIDTH(AVALON_IF.MASKED_SYMBOL_WIDTH_)

// Replicate all parameters except tags (USER)
`define OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS_EXCEPT_TAGS(AVALON_IF) \
    .ADDR_WIDTH(AVALON_IF.ADDR_WIDTH_), \
    .DATA_WIDTH(AVALON_IF.DATA_WIDTH_), \
    .MASKED_SYMBOL_WIDTH(AVALON_IF.MASKED_SYMBOL_WIDTH_), \
    .BURST_CNT_WIDTH(AVALON_IF.BURST_CNT_WIDTH_)


//
// Utilities for operating on interface ofs_plat_avalon_mem_if.
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

`define OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE) \
    MEM_SINK.burstcount OPER MEM_SOURCE.burstcount; \
    MEM_SINK.writedata OPER MEM_SOURCE.writedata; \
    MEM_SINK.address OPER MEM_SOURCE.address; \
    MEM_SINK.write OPER MEM_SOURCE.write; \
    MEM_SINK.read OPER MEM_SOURCE.read; \
    MEM_SINK.byteenable OPER MEM_SOURCE.byteenable; \
    MEM_SINK.user OPER MEM_SOURCE.user

`define OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)

`define OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)

// Old naming, maintained for compatibility
`define OFS_PLAT_AVALON_MEM_IF_FROM_MASTER_TO_SLAVE(MEM_SINK, OPER, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_IF_FROM_MASTER_TO_SLAVE_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_IF_FROM_MASTER_TO_SLAVE_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)

// Note these do not set clk, reset or instance_number since those
// fields may be handled specially.
`define OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, OPER, MEM_SINK) \
    MEM_SOURCE.readdatavalid OPER MEM_SINK.readdatavalid; \
    MEM_SOURCE.readdata OPER MEM_SINK.readdata; \
    MEM_SOURCE.response OPER MEM_SINK.response; \
    MEM_SOURCE.readresponseuser OPER MEM_SINK.readresponseuser; \
    MEM_SOURCE.writeresponsevalid OPER MEM_SINK.writeresponsevalid; \
    MEM_SOURCE.writeresponse OPER MEM_SINK.writeresponse; \
    MEM_SOURCE.writeresponseuser OPER MEM_SINK.writeresponseuser

`define OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE_COMB(MEM_SOURCE, MEM_SINK) \
    MEM_SOURCE.waitrequest = MEM_SINK.waitrequest; \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, =, MEM_SINK)

// Note the lack of waitrequest in the non-blocking assignment. The
// ready/enable protocol must be handled explicitly.
`define OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE_FF(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, <=, MEM_SINK)

// Old naming, maintained for compatibility
`define OFS_PLAT_AVALON_MEM_IF_FROM_SLAVE_TO_MASTER(MEM_SOURCE, OPER, MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, OPER, MEM_SINK)
`define OFS_PLAT_AVALON_MEM_IF_FROM_SLAVE_TO_MASTER_COMB(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE_COMB(MEM_SOURCE, MEM_SINK)
`define OFS_PLAT_AVALON_MEM_IF_FROM_SLAVE_TO_MASTER_FF(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE_FF(MEM_SOURCE, MEM_SINK)


//
// Initialization macros ought to just be tasks in the interface, but QuestaSim
// treats tasks as active even if they are never invoked, leading to errors
// about multiple drivers.
//
// User extension fields are not initialized, leaving them at 'x and making it
// obvious that these fields are not part of the protocol.
//

`define OFS_PLAT_AVALON_MEM_IF_INIT_SOURCE(MEM_SOURCE, OPER) \
    MEM_SOURCE.burstcount OPER '0; \
    MEM_SOURCE.writedata OPER '0; \
    MEM_SOURCE.address OPER '0; \
    MEM_SOURCE.write OPER 1'b0; \
    MEM_SOURCE.read OPER 1'b0; \
    MEM_SOURCE.byteenable OPER '0

`define OFS_PLAT_AVALON_MEM_IF_INIT_SOURCE_COMB(MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SOURCE(MEM_SOURCE, =)

`define OFS_PLAT_AVALON_MEM_IF_INIT_SOURCE_FF(MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SOURCE(MEM_SOURCE, <=)

// Old naming, maintained for compatibility
`define OFS_PLAT_AVALON_MEM_IF_INIT_MASTER(MEM_SOURCE, OPER) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SOURCE(MEM_SOURCE, OPER)
`define OFS_PLAT_AVALON_MEM_IF_INIT_MASTER_COMB(MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SOURCE(MEM_SOURCE, =)
`define OFS_PLAT_AVALON_MEM_IF_INIT_MASTER_FF(MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SOURCE(MEM_SOURCE, <=)


`define OFS_PLAT_AVALON_MEM_IF_INIT_SINK(MEM_SINK, OPER) \
    MEM_SINK.waitrequest OPER 1'b0; \
    MEM_SINK.readdatavalid OPER 1'b0; \
    MEM_SINK.readdata OPER '0; \
    MEM_SINK.response OPER '0; \
    MEM_SINK.writeresponsevalid OPER 1'b0; \
    MEM_SINK.writeresponse OPER '0

`define OFS_PLAT_AVALON_MEM_IF_INIT_SINK_COMB(MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SINK(MEM_SINK, =)

`define OFS_PLAT_AVALON_MEM_IF_INIT_SINK_FF(MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SINK(MEM_SINK, <=)

// Old naming, maintained for compatibility
`define OFS_PLAT_AVALON_MEM_IF_INIT_SLAVE(MEM_SINK, OPER) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SINK(MEM_SINK, OPER)
`define OFS_PLAT_AVALON_MEM_IF_INIT_SLAVE_COMB(MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SINK(MEM_SINK, =)
`define OFS_PLAT_AVALON_MEM_IF_INIT_SLAVE_FF(MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_IF_INIT_SINK(MEM_SINK, <=)

//
// Standard validation macro to confirm that parameters that affect size match.
//

`define OFS_PLAT_AVALON_MEM_IF_CHECK_PARAMS_MATCH(MEM_IFC0, MEM_IFC1) \
    initial \
    begin \
        if (MEM_IFC0.ADDR_WIDTH != MEM_IFC1.ADDR_WIDTH) \
            $fatal(2, "** ERROR ** %m: Avalon-MM interface ADDR_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.ADDR_WIDTH, MEM_IFC1.ADDR_WIDTH); \
        if (MEM_IFC0.DATA_WIDTH != MEM_IFC1.DATA_WIDTH) \
            $fatal(2, "** ERROR ** %m: Avalon-MM interface DATA_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.DATA_WIDTH, MEM_IFC1.DATA_WIDTH); \
        if (MEM_IFC0.BURST_CNT_WIDTH != MEM_IFC1.BURST_CNT_WIDTH) \
            $fatal(2, "** ERROR ** %m: Avalon-MM interface BURST_CNT_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.BURST_CNT_WIDTH, MEM_IFC1.BURST_CNT_WIDTH); \
        if (MEM_IFC0.MASKED_SYMBOL_WIDTH != MEM_IFC1.MASKED_SYMBOL_WIDTH) \
            $fatal(2, "** ERROR ** %m: Avalon-MM interface MASKED_SYMBOL_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.MASKED_SYMBOL_WIDTH, MEM_IFC1.MASKED_SYMBOL_WIDTH); \
        if (MEM_IFC0.RESPONSE_WIDTH != MEM_IFC1.RESPONSE_WIDTH) \
            $fatal(2, "** ERROR ** %m: Avalon-MM interface RESPONSE_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.RESPONSE_WIDTH, MEM_IFC1.RESPONSE_WIDTH); \
        if (MEM_IFC0.USER_WIDTH != MEM_IFC1.USER_WIDTH) \
            $fatal(2, "** ERROR ** %m: Avalon-MM interface USER_WIDTH mismatch (%0d vs. %0d)!", \
                   MEM_IFC0.USER_WIDTH, MEM_IFC1.USER_WIDTH); \
    end

`endif // __OFS_PLAT_AVALON_MEM_IF_VH__
