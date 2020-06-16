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
    // Host memory (AXI)
    ofs_plat_axi_mem_if.to_slave host_mem_if,

    // FPGA MMIO master (AXI)
    ofs_plat_axi_mem_lite_if.to_master mmio64_if,

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

    localparam NUM_INTR_IDS = 4;
    typedef logic [$clog2(NUM_INTR_IDS)-1 : 0] t_intr_id;


    // ====================================================================
    //
    //  Global CSRs (mostly to tell SW about the AFU configuration)
    //
    // ====================================================================

    // Test UUID. Multiple tests may share an AFU UUID and are differentiated
    // with test IDs.
    logic [127:0] test_id = 128'h85d2a7e8_afd3_4307_bbc0_10592f1e1366;

    logic [$clog2(NUM_INTR_IDS) : 0] num_intr_responses;
    logic [NUM_INTR_IDS-1 : 0] intr_response_mask;

    always_comb
    begin
        eng_csr_glob.rd_data[0] = test_id[63:0];
        eng_csr_glob.rd_data[1] = test_id[127:64];
        eng_csr_glob.rd_data[2] = { 48'd0,
                                    8'(NUM_INTR_IDS),
                                    8'd1 };
        eng_csr_glob.rd_data[3] = { 40'd0,
                                    16'(intr_response_mask),
                                    8'(num_intr_responses) };

        for (int e = 4; e < eng_csr_glob.NUM_CSRS; e = e + 1)
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

    //
    // Just a simple global engine that generates one interrupt per
    // channel when an MMIO write to global CSR 0 is observed.
    //

    assign host_mem_if.arvalid = 1'b0;
    assign host_mem_if.rready = 1'b1;

    logic state_active;
    t_intr_id cur_intr_id;
    t_intr_id max_intr_id;

    // Start on write to global CSR 0
    logic start_cmd;
    assign start_cmd = eng_csr_glob.wr_req && (eng_csr_glob.wr_idx == 0);

    always_ff @(posedge clk)
    begin
        if (state_active && host_mem_if.awready && host_mem_if.wready)
        begin
            // Done?
            state_active <= (cur_intr_id != max_intr_id);

            cur_intr_id <= cur_intr_id + 1;
        end

        if (start_cmd)
        begin
            state_active <= 1'b1;
            cur_intr_id <= '0;
            max_intr_id <= t_intr_id'(eng_csr_glob.wr_data);
        end

        if (!reset_n)
        begin
            state_active <= 1'b0;
        end
    end

    // Generate an interrupt request
    t_ccip_c1_ReqIntrHdr c1_req_intr_hdr;
    always_comb
    begin
        c1_req_intr_hdr = '0;
        c1_req_intr_hdr.req_type = eREQ_INTR;
        c1_req_intr_hdr.id = cur_intr_id;
    end

    always_comb
    begin
        host_mem_if.awvalid = state_active && host_mem_if.awready && host_mem_if.wready;
        host_mem_if.aw = '0;
        // Interrupt vector index is passed in the low bits of addr.
        host_mem_if.aw.addr = { '0, cur_intr_id };

        // Signal an interrupt
        host_mem_if.aw.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_INTERRUPT] = 1'b1;
        // Store the index in user. This is used below to match responses in
        // case they are returned out of order. (Note that OFS PIM shims currently
        // all return AXI responses in order, so this is not strictly necessary.)
        host_mem_if.aw.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_MAX+1 +: $clog2(NUM_INTR_IDS)] =
            { '0, cur_intr_id };

        // Generate a corresponding write data packet
        host_mem_if.wvalid = state_active && host_mem_if.awready && host_mem_if.wready;
        host_mem_if.w = '0;
        host_mem_if.w.last = 1'b1;
        host_mem_if.w.strb = ~'0;

        if (!reset_n)
        begin
            host_mem_if.awvalid = 1'b0;
            host_mem_if.wvalid = 1'b0;
        end
    end

    // Count interrupt responses
    assign host_mem_if.bready = 1'b1;

    // Interrupt index is stored in b.user
    t_intr_id rsp_intr_id;
    assign rsp_intr_id = host_mem_if.b.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_MAX+1 +: $clog2(NUM_INTR_IDS)];

    always_ff @(posedge clk)
    begin
        if (host_mem_if.bvalid)
        begin
            num_intr_responses <= num_intr_responses + 1;
            intr_response_mask[rsp_intr_id] <= 1'b1;
        end

        if (!reset_n || start_cmd)
        begin
            num_intr_responses <= '0;
            intr_response_mask <= '0;
        end
    end


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
