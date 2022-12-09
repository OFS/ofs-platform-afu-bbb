// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

module afu
  #(
    parameter NUM_INTR_IDS = 4
    )
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

    // Start on write to global CSR 0
    logic start_cmd;
    assign start_cmd = eng_csr_glob.wr_req && (eng_csr_glob.wr_idx == 0);

    always_ff @(posedge clk)
    begin
        if (state_active && host_mem_if.awready && host_mem_if.wready)
        begin
            // Done?
            state_active <= (cur_intr_id != t_intr_id'(0));
            cur_intr_id <= cur_intr_id - 1;
        end

        if (start_cmd)
        begin
            state_active <= 1'b1;
            cur_intr_id <= t_intr_id'(eng_csr_glob.wr_data);
        end

        if (!reset_n)
        begin
            state_active <= 1'b0;
        end
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
            cur_intr_id;

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
        if (host_mem_if.bvalid &&
            host_mem_if.b.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_INTERRUPT])
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


    // synthesis translate_off

    //
    // Fail in simulation if the user response field is incorrect.
    //
    logic wr_user_error;

    always_ff @(posedge clk)
    begin
        if (reset_n)
        begin
            if (wr_user_error) $fatal(2, "Aborting due to error");

            if (host_mem_if.bvalid &&
                !host_mem_if.b.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_INTERRUPT])
            begin
                $display("** ERROR ** %m: b.user INTERRUPT flag not set!");
                wr_user_error <= 1'b1;
            end

            // Ensure that the FENCE flag is not set
            if (host_mem_if.bvalid &&
                host_mem_if.b.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_FENCE])
            begin
                $display("** ERROR ** %m: b.user FENCE flag is set unexpectedly!");
                wr_user_error <= 1'b1;
            end
        end
        else
        begin
            wr_user_error <= 1'b0;
        end
    end

    // synthesis translate_on


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
