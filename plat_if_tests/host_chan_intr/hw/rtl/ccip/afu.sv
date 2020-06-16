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
    // Host memory CCI-P
    ofs_plat_host_ccip_if.to_fiu host_mem_if,
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
    logic [127:0] test_id = 128'hda35fcf5_94ba_499d_8324_fe968729e34a;

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
    //  Engine
    //
    // ====================================================================

    //
    // Just a simple global engine that generates one interrupt per
    // channel when an MMIO write to global CSR 0 is observed.
    //

    assign host_mem_if.sTx.c0 = '0;

    logic state_active;
    t_intr_id cur_intr_id;
    t_intr_id max_intr_id;

    // Start on write to global CSR 0
    logic start_cmd;
    assign start_cmd = eng_csr_glob.wr_req && (eng_csr_glob.wr_idx == 0);

    always_ff @(posedge clk)
    begin
        if (state_active && !host_mem_if.sRx.c1TxAlmFull)
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

    always_ff @(posedge clk)
    begin
        host_mem_if.sTx.c1.valid <= state_active && !host_mem_if.sRx.c1TxAlmFull;
        host_mem_if.sTx.c1.hdr <= c1_req_intr_hdr;
        host_mem_if.sTx.c1.data <= '0;

        if (!reset_n)
        begin
            host_mem_if.sTx.c1.valid <= 1'b0;
        end
    end

    // Count interrupt responses
    t_ccip_c1_RspIntrHdr c1_rsp_intr_hdr;
    assign c1_rsp_intr_hdr = host_mem_if.sRx.c1.hdr;

    always_ff @(posedge clk)
    begin
        if (host_mem_if.sRx.c1.rspValid && (host_mem_if.sRx.c1.hdr.resp_type == eRSP_INTR))
        begin
            num_intr_responses <= num_intr_responses + 1;
            intr_response_mask[c1_rsp_intr_hdr.id] <= 1'b1;
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

    t_ccip_c0_ReqMmioHdr mmio_req_hdr;
    assign mmio_req_hdr = host_mem_if.sRx.c0.hdr;

    csr_mgr
      #(
        .NUM_ENGINES(NUM_ENGINES),
        .MMIO_ADDR_WIDTH(CCIP_MMIOADDR_WIDTH-1),
        .MMIO_TID_WIDTH(CCIP_TID_WIDTH)
        )
      csr_mgr
       (
        .clk(host_mem_if.clk),
        .reset_n(host_mem_if.reset_n),
        .pClk,

        .wr_write(host_mem_if.sRx.c0.mmioWrValid),
        .wr_address(mmio_req_hdr.address[CCIP_MMIOADDR_WIDTH-1 : 1]),
        .wr_writedata(host_mem_if.sRx.c0.data[63:0]),

        .rd_read(host_mem_if.sRx.c0.mmioRdValid),
        .rd_address(mmio_req_hdr.address[CCIP_MMIOADDR_WIDTH-1 : 1]),
        .rd_tid_in(mmio_req_hdr.tid),
        .rd_readdatavalid(host_mem_if.sTx.c2.mmioRdValid),
        .rd_readdata(host_mem_if.sTx.c2.data),
        .rd_tid_out(host_mem_if.sTx.c2.hdr.tid),

        .eng_csr_glob,
        .eng_csr
        );

endmodule // afu
