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
// CCI-P host interface.
//

`include "ofs_plat_if.vh"

interface ofs_plat_host_ccip_if
  #(
    parameter ENABLE_LOG = 0         // Log events for this instance?
    );

    wire clk;
    logic reset;    // ACTIVE HIGH

    // CCI-P Protocol Error Detected
    logic error;

    // The CCI-P interface predates stable support for SystemVerilog interfaces,
    // so uses structs to wrap all signals.

    // CCI-P Rx Port
    t_if_ccip_Rx sRx;
    // CCI-P Tx Port
    t_if_ccip_Tx sTx;

    //
    // Connection to the platform (FPGA Interface Manager)
    //
    modport to_fiu
       (
        input  clk,
        input  reset,
        input  error,
        input  sRx,
        output sTx
        );

    //
    // Connection to the AFU (user logic)
    //
    modport to_afu
       (
        output clk,
        output reset,
        output error,
        output sRx,
        input  sTx
        );

endinterface // ofs_plat_host_ccip_if
