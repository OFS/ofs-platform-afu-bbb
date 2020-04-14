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
// Split a CCI-P interface into separate host memory and MMIO interfaces.
// The result is a pair of CCI-P interfaces, with all MMIO traffic
// directed to one and all non-MMIO traffic to the host memory interface.
//

`include "ofs_plat_if.vh"

module ofs_plat_shim_ccip_split_mmio
   (
    // Connection toward the FIU (both host memory and MMIO)
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Host memory traffic
    ofs_plat_host_ccip_if.to_afu host_mem,

    // MMIO traffic
    ofs_plat_host_ccip_if.to_afu mmio
    );

    assign host_mem.clk = to_fiu.clk;
    assign mmio.clk = to_fiu.clk;

    assign host_mem.reset_n = to_fiu.reset_n;
    assign mmio.reset_n = to_fiu.reset_n;

    assign host_mem.error = to_fiu.error;
    assign mmio.error = to_fiu.error;

    assign host_mem.instance_number = to_fiu.instance_number;
    assign mmio.instance_number = to_fiu.instance_number;


    //
    // Host memory connections
    //
    assign to_fiu.sTx.c0 = host_mem.sTx.c0;
    assign to_fiu.sTx.c1 = host_mem.sTx.c1;

    assign host_mem.sRx.c0TxAlmFull = to_fiu.sRx.c0TxAlmFull;
    assign host_mem.sRx.c1TxAlmFull = to_fiu.sRx.c1TxAlmFull;
    assign host_mem.sRx.c1 = to_fiu.sRx.c1;

    always_comb
    begin
        host_mem.sRx.c0 = to_fiu.sRx.c0;
        host_mem.sRx.c0.mmioRdValid = 1'b0;
        host_mem.sRx.c0.mmioWrValid = 1'b0;
    end


    //
    // MMIO connections
    //
    assign to_fiu.sTx.c2 = mmio.sTx.c2;

    assign mmio.sRx.c0TxAlmFull = 1'b1;
    assign mmio.sRx.c1TxAlmFull = 1'b1;
    assign mmio.sRx.c1 = t_if_ccip_c1_Rx'(0);

    always_comb
    begin
        mmio.sRx.c0 = to_fiu.sRx.c0;
        mmio.sRx.c0.rspValid = 1'b0;
    end

endmodule // ofs_plat_shim_ccip_split_mmio
