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

module afu
   (
    // Local memory group 0
    ofs_plat_avalon_mem_if.to_slave local_mem_g0[local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS],

    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_master mmio64_if,

    // pClk is used to compute the frequency of the AFU's clk, since pClk
    // is a known frequency.
    input  logic pClk,

    // AFU Power State
    input  t_ofs_plat_power_state pwrState
    );

    localparam NUM_ENGINES = local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS;

    engine_csr_if eng_csr_glob();
    engine_csr_if eng_csr[NUM_ENGINES]();


    // ====================================================================
    //
    //  Global CSRs (mostly to tell SW about the AFU configuration)
    //
    // ====================================================================

    // Test UUID. Multiple tests may share an AFU UUID and are differentiated
    // with test IDs.
    logic [127:0] test_id = 128'hf8c7e210_7050_4315_b70e_c6c8074fb2b5;

    always_comb
    begin
        eng_csr_glob.rd_data[0] = test_id[63:0];
        eng_csr_glob.rd_data[1] = test_id[127:64];

        for (int e = 2; e < eng_csr_glob.NUM_CSRS; e = e + 1)
        begin
            eng_csr_glob.rd_data[e] = 64'(0);
        end

        // This signal means nothing
        eng_csr_glob.status_active = 1'b0;
    end


    // ====================================================================
    //
    //  Engines (one per local memory port)
    //
    // ====================================================================

    genvar b;
    generate
        for (b = 0; b < local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb
            local_mem_engine
              #(
                .ENGINE_NUMBER(b)
                )
              eng
               (
                .local_mem_if(local_mem_g0[b]),
                .csrs(eng_csr[b])
                );
        end
    endgenerate


    // ====================================================================
    //
    //  Instantiate control via CSRs
    //
    // ====================================================================

    csr_mgr
      #(
        .NUM_ENGINES(NUM_ENGINES),
        .MMIO_ADDR_WIDTH(mmio64_if.ADDR_WIDTH)
        )
      csr_mgr
       (
        .clk(mmio64_if.clk),
        .reset(mmio64_if.reset),
        .pClk,

        .wr_write(mmio64_if.write),
        .wr_address(mmio64_if.address),
        .wr_writedata(mmio64_if.writedata),

        .rd_read(mmio64_if.read),
        .rd_address(mmio64_if.address),
        .rd_readdatavalid(mmio64_if.readdatavalid),
        .rd_readdata(mmio64_if.readdata),

        .eng_csr_glob,
        .eng_csr
        );

    assign mmio64_if.response = 2'b0;
    assign mmio64_if.waitrequest = 1'b0;

endmodule // afu
