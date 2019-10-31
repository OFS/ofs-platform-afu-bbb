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

`include "ofs_plat_if.vh"

//
// Wire together two Avalon split bus memory instances.
//
module ofs_plat_avalon_mem_rdwr_if_connect
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master mem_master
    );

    always_comb
    begin
        `ofs_plat_avalon_mem_rdwr_if_from_master_to_slave_comb(mem_slave, mem_master);
        `ofs_plat_avalon_mem_rdwr_if_from_slave_to_master_comb(mem_master, mem_slave);
    end

endmodule // ofs_plat_avalon_mem_rdwr_if_connect


// Same as standard connection, but pass clk and reset from slave to master
module ofs_plat_avalon_mem_rdwr_if_connect_slave_clk
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master_clk mem_master
    );

    assign mem_master.clk = mem_slave.clk;
    assign mem_master.reset = mem_slave.reset;

    // Debugging signal
    assign mem_master.instance_number = mem_slave.instance_number;

    always_comb
    begin
        `ofs_plat_avalon_mem_rdwr_if_from_master_to_slave_comb(mem_slave, mem_master);
        `ofs_plat_avalon_mem_rdwr_if_from_slave_to_master_comb(mem_master, mem_slave);
    end

endmodule // ofs_plat_avalon_mem_rdwr_if_connect_slave_clk


// Same as standard connection, but pass clk and reset from master to slave
module ofs_plat_avalon_mem_rdwr_if_connect_master_clk
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave_clk mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master mem_master
    );

    assign mem_slave.clk = mem_master.clk;
    assign mem_slave.reset = mem_master.reset;

    // Debugging signal
    assign mem_slave.instance_number = mem_master.instance_number;

    always_comb
    begin
        `ofs_plat_avalon_mem_rdwr_if_from_master_to_slave_comb(mem_slave, mem_master);
        `ofs_plat_avalon_mem_rdwr_if_from_slave_to_master_comb(mem_master, mem_slave);
    end

endmodule // ofs_plat_avalon_mem_rdwr_if_connect_master_clk
