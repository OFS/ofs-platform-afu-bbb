// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "afu_json_info.vh"

//
// Implement the same CSR space as afu_axi.sv but connect to a 512 bit
// read/write MMIO interface.
//
module afu
   (
    // FPGA MMIO master (AXI)
    ofs_plat_axi_mem_lite_if.to_master mmio512_if
    );

    logic clk;
    assign clk = mmio512_if.clk;
    logic reset_n;
    assign reset_n = mmio512_if.reset_n;

    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    typedef logic [7:0][63:0] t_mmio_value;
    typedef logic [11:0] t_csr_idx;


    // ====================================================================
    //
    //  Use interface instances as containers to register request state.
    //
    // ====================================================================

    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio512_if)
        )
        mmio512_reg();

    // No clock/holding reset disables the checker
    assign mmio512_reg.clk = 1'b0;
    assign mmio512_reg.reset_n = 1'b0;


    // ====================================================================
    //
    //  Register write requests in the mmio*_reg instances so that they
    //  can be read back to verify the success of the writes.
    //
    // ====================================================================

    // Generate write response when address and data arrive
    logic process_wr_512;
    assign process_wr_512 = mmio512_reg.awvalid && mmio512_reg.wvalid &&
                            mmio512_if.bready;

    // Write response (512 bit bus). This will be ignored by the MMIO bridge,
    // but it is technically the right thing to do on AXI.
    assign mmio512_if.bvalid = process_wr_512;
    always_comb
    begin
        mmio512_if.b = '0;
        mmio512_if.b.id = mmio512_reg.aw.id;
        mmio512_if.b.user = mmio512_reg.aw.user;
    end

    // Preserve write requests until they are processed by deasserting ready.
    assign mmio512_if.awready = !mmio512_reg.awvalid;
    assign mmio512_if.wready = !mmio512_reg.wvalid;

    always_ff @(posedge clk)
    begin
        // Consume new 512 bit write address
        if (mmio512_if.awvalid && mmio512_if.awready)
        begin
            mmio512_reg.awvalid <= 1'b1;
            mmio512_reg.aw <= mmio512_if.aw;
        end
        // Consume new 512 bit write data
        if (mmio512_if.wvalid && mmio512_if.wready)
        begin
            mmio512_reg.wvalid <= 1'b1;
            mmio512_reg.w.user <= mmio512_if.w.user;
            mmio512_reg.w.strb <= mmio512_if.w.strb;
            for (int i = 0; i < 64; i = i + 1)
            begin
                if (mmio512_if.w.strb[i])
                    mmio512_reg.w.data[i*8 +: 8] <= mmio512_if.w.data[i*8 +: 8];
            end
        end

        // Clear valid bits to indicate write complete and ready to
        // receive a new command.
        if (!reset_n || process_wr_512)
        begin
            mmio512_reg.awvalid <= 1'b0;
            mmio512_reg.wvalid <= 1'b0;
        end

        // These are cleared in order to put them in a guaranteed state
        // for the MMIO read test below.
        if (!reset_n)
        begin
            mmio512_reg.aw <= '0;
            mmio512_reg.w <= '0;
        end
    end


    // ====================================================================
    //
    //  Handle reads.
    //
    // ====================================================================

    //
    // Hold read requests in mmio512_reg until the response is generated.
    //
    assign mmio512_if.arready = !mmio512_reg.arvalid;

    logic read_req_q;
    t_csr_idx read_idx_q;

    always_ff @(posedge clk)
    begin
        if (mmio512_if.arvalid && mmio512_if.arready)
        begin
            mmio512_reg.arvalid <= 1'b1;
            mmio512_reg.ar <= mmio512_if.ar;
        end

        read_req_q <= mmio512_reg.arvalid;
        // ar.addr is the byte index -- convert to 64 bit CSR index
        read_idx_q <= mmio512_reg.ar.addr[3 +: $bits(t_csr_idx)];

        // Read response available the 2nd cycle after the request arrives
        mmio512_if.rvalid <= read_req_q;

        // Read request processing is complete when a response is generated
        if (!reset_n || (mmio512_if.rvalid && mmio512_if.rready))
        begin
            mmio512_reg.arvalid <= 1'b0;
            read_req_q <= 1'b0;
            mmio512_if.rvalid <= 1'b0;
        end
    end

    // AFU feature header, ID, etc. in a 512 bit vector.
    t_mmio_value dfh_afu_id_q;
    always_ff @(posedge clk)
    begin
        dfh_afu_id_q <= '0;

        // AFU DFH (device feature header)
        // Here we define a trivial feature list.  In this
        // example, our AFU is the only entry in this list.
        // Feature type is AFU
        dfh_afu_id_q[0][63:60] <= 4'h1;
        // End of list (last entry in list)
        dfh_afu_id_q[0][40] <= 1'b1;

        // AFU_ID_L
        dfh_afu_id_q[1] <= afu_id[63:0];
        // AFU_ID_H
        dfh_afu_id_q[2] <= afu_id[127:64];
        // Full address of the request, including byte, replicated twice
        // so it can be read in either half as a 32 bit read.
        dfh_afu_id_q[7] <= { 32'(mmio512_reg.ar.addr), 32'(mmio512_reg.ar.addr) };
    end

    logic [63:0] afu_status_reg;
    assign afu_status_reg =
        { 32'h0,  // reserved
          16'(`OFS_PLAT_PARAM_CLOCKS_PCLK_FREQ),
          2'h3,   // 512 bit read/write bus
          9'h0,  // reserved
          // Will the AFU consume a 512 bit MMIO write?
          1'(ofs_plat_host_chan_pkg::MMIO_512_WRITE_SUPPORTED),
          4'h1    // AXI MMIO interfaces
          };

    // Second cycle selects from among the already reduced groups
    always_ff @(posedge clk)
    begin
        mmio512_if.r <= '0;
        mmio512_if.r.id <= mmio512_reg.ar.id;
        mmio512_if.r.user <= mmio512_reg.ar.user;

        casez (read_idx_q)
            // AFU DFH (device feature header) and AFU ID
            12'h00?: mmio512_if.r.data <= dfh_afu_id_q;

            // Status register
            12'h010: mmio512_if.r.data <= 512'(afu_status_reg);

            // 64 bit write state. (Behave as though the interace is 64 bit data.)
            12'h020: mmio512_if.r.data <= mmio512_reg.w.data[64 * mmio512_reg.aw.addr[5:3] +: 64];
            12'h03?: mmio512_if.r.data <= { '0,
                                            64'(mmio512_reg.w.strb[8 * mmio512_reg.aw.addr[5:3] +: 8]),
                                            64'(mmio512_reg.aw.addr) };

            // 512 bit write state. The wide data is mapped to
            // 8 64 bit registers in 'h030-'h037.
            12'h04?: mmio512_if.r.data <= mmio512_reg.w.data;
            12'h05?: mmio512_if.r.data <= { '0,
                                            64'(mmio512_reg.w.strb),
                                            64'(mmio512_reg.aw.addr) };

            default: mmio512_if.r.data <= '0;
        endcase // casez (read_idx_q)
    end

endmodule // afu
