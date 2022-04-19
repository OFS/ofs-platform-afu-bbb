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

`include "ofs_plat_if.vh"

module afu
   (
    // Host memory (AXI)
    ofs_plat_axi_mem_if.to_sink host_mem_if,

    // FPGA MMIO source (AXI)
    ofs_plat_axi_mem_lite_if.to_source mmio64_if,

    // pClk is used to compute the frequency of the AFU's clk, since pClk
    // is a known frequency.
    input  logic pClk
    );

    logic clk;
    assign clk = host_mem_if.clk;
    logic reset_n;
    assign reset_n = host_mem_if.reset_n;

    localparam NUM_ENGINES = 1;

    engine_csr_if eng_csr_glob();
    engine_csr_if eng_csr[NUM_ENGINES]();


    // ====================================================================
    //
    //  Global CSRs (mostly to tell SW about the AFU configuration)
    //
    // ====================================================================

    // Test UUID. Multiple tests may share an AFU UUID and are differentiated
    // with test IDs.
    logic [127:0] test_id = 128'h6b1c7c24_7cd5_4b5d_b3dd_c4ce111cfa4f;

    always_comb
    begin
        eng_csr_glob.rd_data[0] = test_id[63:0];
        eng_csr_glob.rd_data[1] = test_id[127:64];
        eng_csr_glob.rd_data[2] = { 56'd0,
                                    8'(NUM_ENGINES) };

        for (int e = 3; e < eng_csr_glob.NUM_CSRS; e = e + 1)
        begin
            eng_csr_glob.rd_data[e] = 64'(0);
        end

        // This signal means nothing
        eng_csr_glob.status_active = 1'b0;
    end


    // ====================================================================
    //
    //  Engines (one per host memory port)
    //
    // ====================================================================

    host_mem_atomic_engine_axi
      #(
        .ENGINE_NUMBER(0),
        .ENGINE_GROUP(0)
        )
      eng
       (
        .host_mem_if(host_mem_if),
        .csrs(eng_csr[0])
        );


    // ====================================================================
    //
    //  Instantiate control via CSRs
    //
    // ====================================================================

    csr_mgr_axi
      #(
        .NUM_ENGINES(NUM_ENGINES)
        )
      csr_mgr
       (
        .mmio_if(mmio64_if),
        .pClk,

        .eng_csr_glob,
        .eng_csr
        );

endmodule // afu
