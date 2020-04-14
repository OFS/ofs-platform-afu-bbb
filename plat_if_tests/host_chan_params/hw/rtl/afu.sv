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
  #(
    parameter NUM_PORTS_G0 = 1,
    parameter NUM_PORTS_G1 = 0
    )
   (
`ifdef TEST_PARAM_IFC_CCIP
    // Host memory CCI-P
    ofs_plat_host_ccip_if.to_fiu host_mem_if[NUM_PORTS_G0],
    // Zero length is illegal -- force minimum size 1 dummy entry
    ofs_plat_host_ccip_if.to_fiu host_mem_g1_if[NUM_PORTS_G1 > 0 ? NUM_PORTS_G1 : 1],
`endif
`ifdef TEST_PARAM_IFC_AVALON
    // Host memory (Avalon)
    ofs_plat_avalon_mem_rdwr_if.to_slave host_mem_if[NUM_PORTS_G0],
    // Zero length is illegal -- force minimum size 1 dummy entry
    ofs_plat_avalon_mem_rdwr_if.to_slave host_mem_g1_if[NUM_PORTS_G1 > 0 ? NUM_PORTS_G1 : 1],
`endif

    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_master mmio64_if,

    // pClk is used to compute the frequency of the AFU's clk, since pClk
    // is a known frequency.
    input  logic pClk,

    // AFU Power State
    input  t_ofs_plat_power_state pwrState
    );

    localparam NUM_ENGINES = NUM_PORTS_G0 + NUM_PORTS_G1;

    engine_csr_if eng_csr_glob();
    engine_csr_if eng_csr[NUM_ENGINES]();


    // ====================================================================
    //
    //  Global CSRs (mostly to tell SW about the AFU configuration)
    //
    // ====================================================================

    // Test UUID. Multiple tests may share an AFU UUID and are differentiated
    // with test IDs.
`ifdef TEST_PARAM_IFC_CCIP
    logic [127:0] test_id = 128'hc5ebd585_4b1e_4e3e_a53f_fda6b7b340da;
`endif
`ifdef TEST_PARAM_IFC_AVALON
    logic [127:0] test_id = 128'h04babb2e_4498_48bf_8d94_59dce56eb1d4;
`endif

    always_comb
    begin
        eng_csr_glob.rd_data[0] = test_id[63:0];
        eng_csr_glob.rd_data[1] = test_id[127:64];
        eng_csr_glob.rd_data[2] = { 48'd0, 8'(NUM_PORTS_G1), 8'(NUM_PORTS_G0) };

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

    genvar p;
    generate
        // Group 0 engines, one per port
        for (p = 0; p < NUM_PORTS_G0; p = p + 1)
        begin : g0
`ifdef TEST_PARAM_IFC_CCIP
            host_mem_rdwr_engine_ccip
`else
            host_mem_rdwr_engine_avalon
`endif
              #(
                .ENGINE_NUMBER(p)
                )
              eng
               (
                .host_mem_if(host_mem_if[p]),
                .csrs(eng_csr[p])
                );
        end

        // Group 1 engines follow group 0
        for (p = 0; p < NUM_PORTS_G1; p = p + 1)
        begin : g1
`ifdef TEST_PARAM_IFC_CCIP
            host_mem_rdwr_engine_ccip
`else
            host_mem_rdwr_engine_avalon
`endif
              #(
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AVALON
                // Simple Avalon ports don't support write fences
                .WRITE_FENCE_SUPPORTED(0),
`endif
                .ENGINE_NUMBER(NUM_PORTS_G0 + p)
                )
              eng
               (
                .host_mem_if(host_mem_g1_if[p]),
                .csrs(eng_csr[NUM_PORTS_G0 + p])
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
        .reset_n(mmio64_if.reset_n),
        .pClk,

        .wr_write(mmio64_if.write),
        .wr_address(mmio64_if.address),
        .wr_writedata(mmio64_if.writedata),

        .rd_read(mmio64_if.read),
        .rd_address(mmio64_if.address),
        .rd_tid_in('x),
        .rd_readdatavalid(mmio64_if.readdatavalid),
        .rd_readdata(mmio64_if.readdata),
        .rd_tid_out(),

        .eng_csr_glob,
        .eng_csr
        );

    assign mmio64_if.response = 2'b0;
    assign mmio64_if.waitrequest = 1'b0;

endmodule // afu
