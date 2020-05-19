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
    .BURST_CNT_WIDTH(AVALON_IF.BURST_CNT_WIDTH_)

`define OFS_PLAT_AVALON_MEM_IF_REPLICATE_MEM_PARAMS(AVALON_IF) \
    .ADDR_WIDTH(AVALON_IF.ADDR_WIDTH_), \
    .DATA_WIDTH(AVALON_IF.DATA_WIDTH_), \
    .MASKED_SYMBOL_WIDTH(AVALON_IF.MASKED_SYMBOL_WIDTH_)


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

`define OFS_PLAT_AVALON_MEM_IF_FROM_MASTER_TO_SLAVE_COMB(MEM_SLAVE, MEM_MASTER) \
    MEM_SLAVE.burstcount = MEM_MASTER.burstcount; \
    MEM_SLAVE.writedata = MEM_MASTER.writedata; \
    MEM_SLAVE.address = MEM_MASTER.address; \
    MEM_SLAVE.write = MEM_MASTER.write; \
    MEM_SLAVE.read = MEM_MASTER.read; \
    MEM_SLAVE.byteenable = MEM_MASTER.byteenable; \
    MEM_SLAVE.user = MEM_MASTER.user

`define OFS_PLAT_AVALON_MEM_IF_FROM_MASTER_TO_SLAVE_FF(MEM_SLAVE, MEM_MASTER) \
    MEM_SLAVE.burstcount <= MEM_MASTER.burstcount; \
    MEM_SLAVE.writedata <= MEM_MASTER.writedata; \
    MEM_SLAVE.address <= MEM_MASTER.address; \
    MEM_SLAVE.write <= MEM_MASTER.write; \
    MEM_SLAVE.read <= MEM_MASTER.read; \
    MEM_SLAVE.byteenable <= MEM_MASTER.byteenable; \
    MEM_SLAVE.user <= MEM_MASTER.user

// Note these do not set clk, reset or instance_number since those
// fields may be handled specially.
`define OFS_PLAT_AVALON_MEM_IF_FROM_SLAVE_TO_MASTER_COMB(MEM_MASTER, MEM_SLAVE) \
    MEM_MASTER.waitrequest = MEM_SLAVE.waitrequest; \
    MEM_MASTER.readdatavalid = MEM_SLAVE.readdatavalid; \
    MEM_MASTER.readdata = MEM_SLAVE.readdata; \
    MEM_MASTER.response = MEM_SLAVE.response; \
    MEM_MASTER.readresponseuser = MEM_SLAVE.readresponseuser; \
    MEM_MASTER.writeresponsevalid = MEM_SLAVE.writeresponsevalid; \
    MEM_MASTER.writeresponse = MEM_SLAVE.writeresponse; \
    MEM_MASTER.writeresponseuser = MEM_SLAVE.writeresponseuser

// Note the lack of waitrequest in the non-blocking assignment. The
// ready/enable protocol must be handled explicitly.
`define OFS_PLAT_AVALON_MEM_IF_FROM_SLAVE_TO_MASTER_FF(MEM_MASTER, MEM_SLAVE) \
    MEM_MASTER.readdatavalid <= MEM_SLAVE.readdatavalid; \
    MEM_MASTER.readdata <= MEM_SLAVE.readdata; \
    MEM_MASTER.response <= MEM_SLAVE.response; \
    MEM_MASTER.readresponseuser <= MEM_SLAVE.readresponseuser; \
    MEM_MASTER.writeresponsevalid <= MEM_SLAVE.writeresponsevalid; \
    MEM_MASTER.writeresponse <= MEM_SLAVE.writeresponse; \
    MEM_MASTER.writeresponseuser <= MEM_SLAVE.writeresponseuser


//
// Initialization macros ought to just be tasks in the interface, but QuestSim
// treats tasks as active even if they are never invoked, leading to errors
// about multiple drivers.
//
// User extension fields are not initialized, leaving them at 'x and making it
// obvious that these fields are not part of the protocol.
//

`define OFS_PLAT_AVALON_MEM_IF_INIT_MASTER_COMB(MEM_MASTER) \
    MEM_MASTER.burstcount = '0; \
    MEM_MASTER.writedata = '0; \
    MEM_MASTER.address = '0; \
    MEM_MASTER.write = 1'b0; \
    MEM_MASTER.read = 1'b0; \
    MEM_MASTER.byteenable = '0

`define OFS_PLAT_AVALON_MEM_IF_INIT_MASTER_FF(MEM_MASTER) \
    MEM_MASTER.burstcount <= '0; \
    MEM_MASTER.writedata <= '0; \
    MEM_MASTER.address <= '0; \
    MEM_MASTER.write <= 1'b0; \
    MEM_MASTER.read <= 1'b0; \
    MEM_MASTER.byteenable <= '0

`define OFS_PLAT_AVALON_MEM_IF_INIT_SLAVE_COMB(MEM_SLAVE) \
    MEM_SLAVE.waitrequest = 1'b0; \
    MEM_SLAVE.readdatavalid = 1'b0; \
    MEM_SLAVE.readdata = '0; \
    MEM_SLAVE.response = '0; \
    MEM_SLAVE.writeresponsevalid = 1'b0; \
    MEM_SLAVE.writeresponse = '0

`define OFS_PLAT_AVALON_MEM_IF_INIT_SLAVE_FF(MEM_SLAVE) \
    MEM_SLAVE.waitrequest <= 1'b0; \
    MEM_SLAVE.readdatavalid <= 1'b0; \
    MEM_SLAVE.readdata <= '0; \
    MEM_SLAVE.response <= '0; \
    MEM_SLAVE.writeresponsevalid <= 1'b0; \
    MEM_SLAVE.writeresponse <= '0


`endif // __OFS_PLAT_AVALON_MEM_IF_VH__
