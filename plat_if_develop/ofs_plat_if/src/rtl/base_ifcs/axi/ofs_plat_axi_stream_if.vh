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

`ifndef __OFS_PLAT_AXI_STREAM_IF_VH__
`define __OFS_PLAT_AXI_STREAM_IF_VH__

//
// Macro for replicating properties of an ofs_plat_axi_stream_if when
// defining another instance of the interface. SystemVerilog doesn't
// allow querying a "type" parameter, so the only option is to
// generate an opaque instance of the same size, using the equivalent
// interface ofs_plat_axi_stream_opaque_if.
//
`define OFS_PLAT_AXI_STREAM_IF_REPLICATE_OPAQUE(AXI_IF) \
    .TDATA_WIDTH(AXI_IF.TDATA_WIDTH), \
    .TUSER_WIDTH(AXI_IF.TUSER_WIDTH_)

// Replicate AXI stream interface but don't set type data type so
// that other code can set it.
`define OFS_PLAT_AXI_STREAM_IF_REPLICATE_PARAMS(AXI_IF)


//
// General copy macros take OPER so the macro can be used in both combinational
// and registered contexts. Specify an operator: usually = or <=.
//

`define OFS_PLAT_AXI_STREAM_IF_FROM_MASTER_TO_SLAVE(STREAM_SLAVE, OPER, STREAM_MASTER) \
    STREAM_SLAVE.t OPER STREAM_MASTER.t; \
    STREAM_SLAVE.tvalid OPER STREAM_MASTER.tvalid

`define OFS_PLAT_AXI_STREAM_IF_FROM_MASTER_TO_SLAVE_COMB(STREAM_SLAVE, STREAM_MASTER) \
    `OFS_PLAT_AXI_STREAM_IF_FROM_MASTER_TO_SLAVE(STREAM_SLAVE, =, STREAM_MASTER)

`define OFS_PLAT_AXI_STREAM_IF_FROM_MASTER_TO_SLAVE_FF(STREAM_SLAVE, STREAM_MASTER) \
    `OFS_PLAT_AXI_STREAM_IF_FROM_MASTER_TO_SLAVE(STREAM_SLAVE, <=, STREAM_MASTER)


`define OFS_PLAT_AXI_STREAM_IF_FROM_SLAVE_TO_MASTER(STREAM_MASTER, OPER, STREAM_SLAVE) \
    STREAM_MASTER.tready OPER STREAM_SLAVE.tready

`define OFS_PLAT_AXI_STREAM_IF_FROM_SLAVE_TO_MASTER_COMB(STREAM_MASTER, STREAM_SLAVE) \
    `OFS_PLAT_AXI_STREAM_IF_FROM_SLAVE_TO_MASTER(STREAM_MASTER, =, STREAM_SLAVE)

`define OFS_PLAT_AXI_STREAM_IF_FROM_SLAVE_TO_MASTER_FF(STREAM_MASTER, STREAM_SLAVE) \
    `OFS_PLAT_AXI_STREAM_IF_FROM_SLAVE_TO_MASTER(STREAM_MASTER, <=, STREAM_SLAVE)


//
// Initialization macros.
//

`define OFS_PLAT_AXI_STREAM_IF_INIT_MASTER(STREAM_MASTER, OPER) \
    STREAM_MASTER.t OPER '0; \
    STREAM_MASTER.valid OPER 1'b0

`define OFS_PLAT_AXI_STREAM_IF_INIT_MASTER_COMB(STREAM_MASTER) \
    `OFS_PLAT_AXI_STREAM_IF_INIT_MASTER(STREAM_MASTER, =)

`define OFS_PLAT_AXI_STREAM_IF_INIT_MASTER_FF(STREAM_MASTER) \
    `OFS_PLAT_AXI_STREAM_IF_INIT_MASTER(STREAM_MASTER, <=)


`define OFS_PLAT_AXI_STREAM_IF_INIT_SLAVE(STREAM_SLAVE, OPER) \
    STREAM_SLAVE.tready OPER 1'b0

`define OFS_PLAT_AXI_STREAM_IF_INIT_SLAVE_COMB(STREAM_SLAVE) \
    `OFS_PLAT_AXI_STREAM_IF_INIT_SLAVE(STREAM_SLAVE, =)

`define OFS_PLAT_AXI_STREAM_IF_INIT_SLAVE_FF(STREAM_SLAVE) \
    `OFS_PLAT_AXI_STREAM_IF_INIT_SLAVE(STREAM_SLAVE, <=)


//
// Field-by-field copies of structs, needed when master and slave have
// different field widths.
//

`define OFS_PLAT_AXI_STREAM_IF_COPY_T(STREAM_SLAVE_T, OPER, STREAM_MASTER_T) \
    STREAM_SLAVE_T.last OPER STREAM_MASTER_T.last; \
    STREAM_SLAVE_T.user OPER STREAM_MASTER_T.user; \
    STREAM_SLAVE_T.data OPER STREAM_MASTER_T.data


//
// Standard validation macros. Copying using structs maps data incorrectly
// if the parameters to a pair of interfaces are different. Standard checks
// for incompatibility raise simulation-time errors.
//

`define OFS_PLAT_AXI_STREAM_IF_CHECK_PARAMS_MATCH(STREAM_IFC0, STREAM_IFC1) \
    initial \
    begin \
        if (STREAM_IFC0.TUSER_WIDTH != STREAM_IFC1.TUSER_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-S interface TUSER_WIDTH mismatch (%0d vs. %0d)!", \
                   STREAM_IFC0.TUSER_WIDTH, STREAM_IFC1.TUSER_WIDTH); \
        if (STREAM_IFC0.TDATA_WIDTH != STREAM_IFC1.TDATA_WIDTH) \
            $fatal(2, "** ERROR ** %m: AXI-S interface TDATA_WIDTH mismatch (%0d vs. %0d)!", \
                   STREAM_IFC0.TDATA_WIDTH, STREAM_IFC1.TDATA_WIDTH); \
    end

`endif // __OFS_PLAT_AXI_STREAM_IF_VH__
