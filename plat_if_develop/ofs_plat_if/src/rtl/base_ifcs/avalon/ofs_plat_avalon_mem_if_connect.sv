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
// Wire together two Avalon memory instances.
//
module ofs_plat_avalon_mem_if_connect
   (
    ofs_plat_avalon_mem_if.to_slave mem_slave,
    ofs_plat_avalon_mem_if.to_master mem_master
    );

    always_comb
    begin
        mem_master.clk = mem_slave.clk;
        mem_master.reset = mem_slave.reset;

        mem_master.waitrequest = mem_slave.waitrequest;
        mem_master.readdata = mem_slave.readdata;
        mem_master.readdatavalid = mem_slave.readdatavalid;

        mem_slave.burstcount = mem_master.burstcount;
        mem_slave.writedata = mem_master.writedata;
        mem_slave.address = mem_master.address;
        mem_slave.write = mem_master.write;
        mem_slave.read = mem_master.read;
        mem_slave.byteenable = mem_master.byteenable;

        // Debugging signal
        mem_master.instance_number = mem_slave.instance_number;
    end

endmodule // ofs_plat_avalon_mem_if_connect
