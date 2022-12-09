// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

module afu
  #(
    parameter NUM_INTR_IDS = 4
    )
   (
    // Host memory (Avalon)
    ofs_plat_avalon_mem_rdwr_if.to_slave host_mem_if,

    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_master mmio64_if,

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
    logic [127:0] test_id = 128'hd544c0109_f160_4569_b726_e75cacb7a23b;

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

    assign host_mem_if.rd_read = 1'b0;

    logic state_active;
    t_intr_id cur_intr_id;
    t_intr_id max_intr_id;

    // Start on write to global CSR 0
    logic start_cmd;
    assign start_cmd = eng_csr_glob.wr_req && (eng_csr_glob.wr_idx == 0);

    always_ff @(posedge clk)
    begin
        if (state_active && !host_mem_if.wr_waitrequest)
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
        host_mem_if.wr_write = state_active;
        host_mem_if.wr_address = { '0, cur_intr_id };

        // Signal an interrupt
        host_mem_if.wr_user = '0;
        host_mem_if.wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_INTERRUPT] = 1'b1;
        // Store the index in user. This can be used below to match responses with
        // requests, though Avalon guarantees that responses are returned in order.
        host_mem_if.wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX+1 +: $clog2(NUM_INTR_IDS)] =
            cur_intr_id;

        host_mem_if.wr_burstcount = 1;
        host_mem_if.wr_writedata = '0;
        host_mem_if.wr_byteenable = ~'0;

        if (!reset_n)
        begin
            host_mem_if.wr_write = 1'b0;
        end
    end

    // Interrupt index is stored in wr_writeresponseuser
    t_intr_id rsp_intr_id;
    assign rsp_intr_id = host_mem_if.wr_writeresponseuser[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX+1 +: $clog2(NUM_INTR_IDS)];

    // Count interrupt responses
    always_ff @(posedge clk)
    begin
        // Confirm that the interrupt user flag is set properly
        if (host_mem_if.wr_writeresponsevalid &&
            host_mem_if.wr_writeresponseuser[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_INTERRUPT])
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

            if (host_mem_if.wr_writeresponsevalid &&
                !host_mem_if.wr_writeresponseuser[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_INTERRUPT])
            begin
                $display("** ERROR ** %m: wr_writeresponseuser INTERRUPT flag not set!");
                wr_user_error <= 1'b1;
            end

            // Ensure that the FENCE flag is not set
            if (host_mem_if.wr_writeresponsevalid &&
                host_mem_if.wr_writeresponseuser[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_FENCE])
            begin
                $display("** ERROR ** %m: wr_writeresponseuser FENCE flag is set unexpectedly!");
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
