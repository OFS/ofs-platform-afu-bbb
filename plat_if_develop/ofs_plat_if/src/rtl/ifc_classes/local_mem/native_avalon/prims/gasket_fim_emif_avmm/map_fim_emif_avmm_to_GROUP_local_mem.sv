//
// Copyright (c) 2022, Intel Corporation
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
// Map the local memory AVMM interface exposed by the FIM to the PIM's
// representation. The payload is the same in both.
//

`include "ofs_plat_if.vh"

module map_fim_emif_avmm_to_@group@_local_mem
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

endmodule // map_fim_emif_avmm_to_@group@_local_mem
