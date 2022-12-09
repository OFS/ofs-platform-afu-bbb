// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
