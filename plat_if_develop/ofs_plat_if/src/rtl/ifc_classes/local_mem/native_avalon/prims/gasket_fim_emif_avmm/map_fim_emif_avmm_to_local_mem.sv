// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Map the local memory AVMM interface exposed by the FIM to the PIM's
// representation. The payload is the same in both.
//

`include "ofs_plat_if.vh"

module map_fim_emif_avmm_to_local_mem
  #(
    // Instance number is just used for debugging as a tag
    parameter INSTANCE_NUMBER = 0
    )
   (
    // FIM interface
    ofs_fim_emif_avmm_if.user fim_mem_bank,

    // PIM interface
    ofs_plat_avalon_mem_if.to_source_clk afu_mem_bank
    );

    logic mb_rst_n = 1'b0;
    always @(posedge fim_mem_bank.clk)
    begin
      mb_rst_n <= fim_mem_bank.rst_n;
    end

    assign afu_mem_bank.clk = fim_mem_bank.clk;
    assign afu_mem_bank.reset_n = mb_rst_n;
    assign afu_mem_bank.instance_number = INSTANCE_NUMBER;

    assign afu_mem_bank.waitrequest = fim_mem_bank.waitrequest;

    assign fim_mem_bank.address = afu_mem_bank.address;
    assign fim_mem_bank.write = afu_mem_bank.write;
    assign fim_mem_bank.read = afu_mem_bank.read;
    assign fim_mem_bank.burstcount = afu_mem_bank.burstcount;
    assign fim_mem_bank.writedata = afu_mem_bank.writedata;
    assign fim_mem_bank.byteenable = afu_mem_bank.byteenable;

    assign afu_mem_bank.readdatavalid = fim_mem_bank.readdatavalid;
    assign afu_mem_bank.readdata = fim_mem_bank.readdata;
    assign afu_mem_bank.response = '0;
    assign afu_mem_bank.readresponseuser = '0;

    assign afu_mem_bank.writeresponsevalid = 1'b0;
    assign afu_mem_bank.writeresponse = '0;
    assign afu_mem_bank.writeresponseuser = '0;

endmodule // map_fim_emif_avmm_to_local_mem
