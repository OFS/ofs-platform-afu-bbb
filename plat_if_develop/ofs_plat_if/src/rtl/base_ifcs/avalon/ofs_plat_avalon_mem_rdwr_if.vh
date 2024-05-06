// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_AVALON_MEM_RDWR_IF_VH__
`define __OFS_PLAT_AVALON_MEM_RDWR_IF_VH__

//
// Macros for replicating properties of an ofs_plat_avalon_mem_rdwr_if when
// defininig another instance of the interface.
//
`define OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(AVALON_IF) \
    .ADDR_WIDTH(AVALON_IF.ADDR_WIDTH), \
    .DATA_WIDTH(AVALON_IF.DATA_WIDTH), \
    .MASKED_SYMBOL_WIDTH(AVALON_IF.MASKED_SYMBOL_WIDTH), \
    .BURST_CNT_WIDTH(AVALON_IF.BURST_CNT_WIDTH), \
    .USER_WIDTH(AVALON_IF.USER_WIDTH)

`define OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_MEM_PARAMS(AVALON_IF) \
    .ADDR_WIDTH(AVALON_IF.ADDR_WIDTH), \
    .DATA_WIDTH(AVALON_IF.DATA_WIDTH), \
    .MASKED_SYMBOL_WIDTH(AVALON_IF.MASKED_SYMBOL_WIDTH)

// Replicate all parameters except tags (USER)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(AVALON_IF) \
    .ADDR_WIDTH(AVALON_IF.ADDR_WIDTH), \
    .DATA_WIDTH(AVALON_IF.DATA_WIDTH), \
    .MASKED_SYMBOL_WIDTH(AVALON_IF.MASKED_SYMBOL_WIDTH), \
    .BURST_CNT_WIDTH(AVALON_IF.BURST_CNT_WIDTH)


//
// Utilities for operating on interface ofs_plat_avalon_mem_rdwr_if.
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

`define OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE) \
    MEM_SINK.rd_read OPER MEM_SOURCE.rd_read; \
    MEM_SINK.rd_burstcount OPER MEM_SOURCE.rd_burstcount; \
    MEM_SINK.rd_byteenable OPER MEM_SOURCE.rd_byteenable; \
    MEM_SINK.rd_address OPER MEM_SOURCE.rd_address; \
    MEM_SINK.rd_user OPER MEM_SOURCE.rd_user

`define OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE) \
    MEM_SINK.wr_burstcount OPER MEM_SOURCE.wr_burstcount; \
    MEM_SINK.wr_writedata OPER MEM_SOURCE.wr_writedata; \
    MEM_SINK.wr_address OPER MEM_SOURCE.wr_address; \
    MEM_SINK.wr_write OPER MEM_SOURCE.wr_write; \
    MEM_SINK.wr_byteenable OPER MEM_SOURCE.wr_byteenable; \
    MEM_SINK.wr_user OPER MEM_SOURCE.wr_user

`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE); \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE)

`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)

`define OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)

`define OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)

// Old naming, maintained for compatibility
`define OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_MASTER_TO_SLAVE(MEM_SINK, OPER, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_MASTER_TO_SLAVE(MEM_SINK, OPER, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_MASTER_TO_SLAVE(MEM_SINK, OPER, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK(MEM_SINK, OPER, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_MASTER_TO_SLAVE_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_MASTER_TO_SLAVE_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_MASTER_TO_SLAVE_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_MASTER_TO_SLAVE_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_MASTER_TO_SLAVE_COMB(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK(MEM_SINK, =, MEM_SOURCE)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_MASTER_TO_SLAVE_FF(MEM_SINK, MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_SOURCE_TO_SINK(MEM_SINK, <=, MEM_SOURCE)


// Note these do not set clk, reset or instance_number since those
// fields may be handled specially.
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, OPER, MEM_SINK) \
    MEM_SOURCE.rd_readdata OPER MEM_SINK.rd_readdata; \
    MEM_SOURCE.rd_readdatavalid OPER MEM_SINK.rd_readdatavalid; \
    MEM_SOURCE.rd_response OPER MEM_SINK.rd_response; \
    MEM_SOURCE.rd_readresponseuser OPER MEM_SINK.rd_readresponseuser; \
    MEM_SOURCE.wr_writeresponsevalid OPER MEM_SINK.wr_writeresponsevalid; \
    MEM_SOURCE.wr_response OPER MEM_SINK.wr_response; \
    MEM_SOURCE.wr_writeresponseuser OPER MEM_SINK.wr_writeresponseuser

`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE_COMB(MEM_SOURCE, MEM_SINK) \
    MEM_SOURCE.rd_waitrequest = MEM_SINK.rd_waitrequest; \
    MEM_SOURCE.wr_waitrequest = MEM_SINK.wr_waitrequest; \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, =, MEM_SINK)

// Note the lack of waitrequest in the non-blocking assignment. The
// ready/enable protocol must be handled explicitly.
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE_FF(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, <=, MEM_SINK)

// Old naming, maintained for compatibility
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SLAVE_TO_MASTER(MEM_SOURCE, OPER, MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, OPER, MEM_SINK)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SLAVE_TO_MASTER_COMB(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE_COMB(MEM_SOURCE, MEM_SINK)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SLAVE_TO_MASTER_FF(MEM_SOURCE, MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE(MEM_SOURCE, <=, MEM_SINK)


//
// Initialization macros ought to just be tasks in the interface, but QuestaSim
// treats tasks as active even if they are never invoked, leading to errors
// about multiple drivers.
//
// User extension fields are not initialized, leaving them at 'x and making it
// obvious that these fields are not part of the protocol.
//

`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SOURCE(MEM_SOURCE, OPER) \
    MEM_SOURCE.rd_read OPER 1'b0; \
    MEM_SOURCE.rd_burstcount OPER '0; \
    MEM_SOURCE.rd_byteenable OPER '0; \
    MEM_SOURCE.rd_address OPER '0; \
    MEM_SOURCE.wr_burstcount OPER '0; \
    MEM_SOURCE.wr_writedata OPER '0; \
    MEM_SOURCE.wr_address OPER '0; \
    MEM_SOURCE.wr_write OPER 1'b0; \
    MEM_SOURCE.wr_byteenable OPER '0

`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SOURCE_COMB(MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SOURCE(MEM_SOURCE, =)

`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SOURCE_FF(MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SOURCE(MEM_SOURCE, <=)

// Old naming, maintained for compatibility
`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_MASTER(MEM_SOURCE, OPER) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SOURCE(MEM_SOURCE, OPER)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_MASTER_COMB(MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SOURCE(MEM_SOURCE, =)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_MASTER_FF(MEM_SOURCE) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SOURCE(MEM_SOURCE, <=)


`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SINK(MEM_SINK, OPER) \
    MEM_SINK.rd_waitrequest OPER 1'b0; \
    MEM_SINK.rd_readdata OPER '0; \
    MEM_SINK.rd_readdatavalid OPER 1'b0; \
    MEM_SINK.rd_response OPER '0; \
    MEM_SINK.wr_waitrequest OPER 1'b0; \
    MEM_SINK.wr_writeresponsevalid OPER 1'b0; \
    MEM_SINK.wr_response OPER '0

`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SINK_COMB(MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SINK(MEM_SINK, =)

`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SINK_FF(MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SINK(MEM_SINK, <=)

// Old naming, maintained for compatibility
`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SLAVE(MEM_SINK, OPER) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SINK(MEM_SINK, OPER)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SLAVE_COMB(MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SINK(MEM_SINK, =)
`define OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SLAVE_FF(MEM_SINK) \
    `OFS_PLAT_AVALON_MEM_RDWR_IF_INIT_SINK(MEM_SINK, <=)


//
// Standard validation macro to confirm that parameters that affect size match.
//

`define OFS_PLAT_AVALON_MEM_RDWR_IF_CHECK_PARAMS_MATCH(MEM_IFC0, MEM_IFC1) \
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

`endif // __OFS_PLAT_AVALON_MEM_RDWR_IF_VH__
