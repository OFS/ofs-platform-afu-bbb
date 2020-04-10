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

//
// Map a normal Avalon memory master to a split-bus Avalon slave.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_if_to_rdwr_if
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_if.to_master mem_master
    );

    always_comb
    begin
        mem_master.waitrequest = mem_slave.rd_waitrequest || mem_slave.wr_waitrequest;
        mem_master.readdatavalid = mem_slave.rd_readdatavalid;
        mem_master.readdata = mem_slave.rd_readdata;
        mem_master.response = mem_slave.rd_response;
        mem_master.writeresponsevalid = mem_slave.wr_writeresponsevalid;
        mem_master.writeresponse = mem_slave.wr_response;

        mem_slave.rd_address = mem_master.address;
        mem_slave.rd_read = mem_master.read && !mem_master.waitrequest;
        mem_slave.rd_burstcount = mem_master.burstcount;
        mem_slave.rd_byteenable = mem_master.byteenable;
        mem_slave.rd_function = '0;

        mem_slave.wr_address = mem_master.address;
        mem_slave.wr_write = mem_master.write && !mem_master.waitrequest;
        mem_slave.wr_burstcount = mem_master.burstcount;
        mem_slave.wr_writedata = mem_master.writedata;
        mem_slave.wr_byteenable = mem_master.byteenable;
        mem_slave.wr_function = '0;
    end

endmodule // ofs_plat_avalon_mem_if_to_rdwr_if
