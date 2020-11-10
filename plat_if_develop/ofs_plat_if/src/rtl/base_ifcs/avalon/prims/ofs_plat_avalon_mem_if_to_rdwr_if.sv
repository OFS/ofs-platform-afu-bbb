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
// Map a normal Avalon memory source to a split-bus Avalon sink.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_if_to_rdwr_if
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink,
    ofs_plat_avalon_mem_if.to_source mem_source
    );

    always_comb
    begin
        mem_source.waitrequest = mem_sink.rd_waitrequest || mem_sink.wr_waitrequest;
        mem_source.readdatavalid = mem_sink.rd_readdatavalid;
        mem_source.readdata = mem_sink.rd_readdata;
        mem_source.response = mem_sink.rd_response;
        mem_source.readresponseuser = mem_sink.rd_readresponseuser;
        mem_source.writeresponsevalid = mem_sink.wr_writeresponsevalid;
        mem_source.writeresponse = mem_sink.wr_response;
        mem_source.writeresponseuser = mem_sink.wr_writeresponseuser;

        mem_sink.rd_address = mem_source.address;
        mem_sink.rd_read = mem_source.read && !mem_source.waitrequest;
        mem_sink.rd_burstcount = mem_source.burstcount;
        mem_sink.rd_byteenable = mem_source.byteenable;
        mem_sink.rd_user = mem_source.user;

        mem_sink.wr_address = mem_source.address;
        mem_sink.wr_write = mem_source.write && !mem_source.waitrequest;
        mem_sink.wr_burstcount = mem_source.burstcount;
        mem_sink.wr_writedata = mem_source.writedata;
        mem_sink.wr_byteenable = mem_source.byteenable;
        mem_sink.wr_user = mem_source.user;
    end

endmodule // ofs_plat_avalon_mem_if_to_rdwr_if
