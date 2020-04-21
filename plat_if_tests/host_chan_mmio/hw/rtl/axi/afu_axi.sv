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
`include "afu_json_info.vh"

//
// Test AXI interfaces for MMIO FPGA-side masters. Two sizes are instantiated
// simultaneously: a 64 bit wide read/write master and a 512 bit write-only
// master. Both sizes receive all writes that are smaller than or equal to their
// data width. Namely, the 64 bit bus does not see writes larger than 64 bits.
// The byteenable mask indicates the MMIO access size.
//
// Writes to the MMIO interfaces here are recorded to local registers and can
// be read back to verify success. Any address may be written. The AFU does not
// have any MMIO write registers that affect the AFU's behavior.
//
// MMIO read space is implemented as 64 bit registers. Addresses listed here
// are the index of 64 bit words in the MMIO space.
//
//    0x0: AFU DFH
//    0x1: AFU ID Low
//    0x2: AFU ID High
//
//   0x10: Status register
//         [31:16] pClk frequence (MHz)
//         [ 3: 0] Interface type (1 for AXI)
//
//   0x20: Value of last 64 bit MMIO write
//   0x30: Address of last 64 bit MMIO write
//   0x31: Byteenable mask of last 64 bit MMIO write
//
//   0x40-0x47: Value of last 512 bit MMIO write (bit 0 in 0x40)
//   0x50: Address of last 512 bit MMIO write
//   0x51: Byteenable mask of last 512 bit MMIO write
//
module afu
   (
    // FPGA MMIO master (AXI)
    ofs_plat_axi_mem_lite_if.to_master mmio64_if,
    ofs_plat_axi_mem_lite_if.to_master mmio512_if
    );

    logic clk;
    assign clk = mmio64_if.clk;
    logic reset_n;
    assign reset_n = mmio64_if.reset_n;

    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    typedef logic [63:0] t_mmio_value;
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

    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio64_if)
        )
        mmio64_reg();

    // No clock/holding reset disables the checker
    assign mmio512_reg.clk = 1'b0;
    assign mmio512_reg.reset_n = 1'b0;
    assign mmio64_reg.clk = 1'b0;
    assign mmio64_reg.reset_n = 1'b0;


    // ====================================================================
    //
    //  Register write requests in the mmio*_reg instances so that they
    //  can be read back to verify the success of the writes.
    //
    // ====================================================================

    // Generate write response when address and data arrive
    logic process_wr_512, process_wr_64;
    assign process_wr_512 = mmio512_reg.awvalid && mmio512_reg.wvalid &&
                            mmio512_if.bready;
    assign process_wr_64 = mmio64_reg.awvalid && mmio64_reg.wvalid &&
                           mmio64_if.bready;

    // Write response (512 bit bus). This will be ignored by the MMIO bridge,
    // but it is technically the right thing to do on AXI.
    assign mmio512_if.bvalid = process_wr_512;
    always_comb
    begin
        mmio512_if.b = '0;
        mmio512_if.b.id = mmio512_reg.aw.id;
        mmio512_if.b.user = mmio512_reg.aw.user;
    end

    // Write response (64 bit bus)
    assign mmio64_if.bvalid = process_wr_64;
    always_comb
    begin
        mmio64_if.b = '0;
        mmio64_if.b.id = mmio64_reg.aw.id;
        mmio64_if.b.user = mmio64_reg.aw.user;
    end

    // Preserve write requests until they are processed by deasserting ready.
    assign mmio512_if.awready = !mmio512_reg.awvalid;
    assign mmio512_if.wready = !mmio512_reg.wvalid;
    assign mmio64_if.awready = !mmio64_reg.awvalid;
    assign mmio64_if.wready = !mmio64_reg.wvalid;

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
            mmio512_reg.w <= mmio512_if.w;
        end

        // Consume new 64 bit write address
        if (mmio64_if.awvalid && mmio64_if.awready)
        begin
            mmio64_reg.awvalid <= 1'b1;
            mmio64_reg.aw <= mmio64_if.aw;
        end
        // Consume new 64 bit write data
        if (mmio64_if.wvalid && mmio64_if.wready)
        begin
            mmio64_reg.wvalid <= 1'b1;
            mmio64_reg.w <= mmio64_if.w;
        end

        // Clear valid bits to indicate write complete and ready to
        // receive a new command.
        if (!reset_n || process_wr_512)
        begin
            mmio512_reg.awvalid <= 1'b0;
            mmio512_reg.wvalid <= 1'b0;
        end
        if (!reset_n || process_wr_64)
        begin
            mmio64_reg.awvalid <= 1'b0;
            mmio64_reg.wvalid <= 1'b0;
        end

        // These are cleared in order to put them in a guaranteed state
        // for the MMIO read test below.
        if (!reset_n)
        begin
            mmio512_reg.aw <= '0;
            mmio512_reg.w <= '0;
            mmio64_reg.aw <= '0;
            mmio64_reg.w <= '0;
        end
    end


    // ====================================================================
    //
    //  Handle reads.
    //
    // ====================================================================

    //
    // Hold read requests in mmio64_reg until the response is generated.
    //
    assign mmio64_if.arready = !mmio64_reg.arvalid;

    logic read_req_q;
    t_csr_idx read_idx_q;

    always_ff @(posedge clk)
    begin
        if (mmio64_if.arvalid && mmio64_if.arready)
        begin
            mmio64_reg.arvalid <= 1'b1;
            mmio64_reg.ar <= mmio64_if.ar;
        end

        read_req_q <= mmio64_reg.arvalid;
        // ar.addr is the byte index -- convert to 64 bit CSR index
        read_idx_q <= mmio64_reg.ar.addr[3 +: $bits(t_csr_idx)];

        // Read response available the 2nd cycle after the request arrives
        mmio64_if.rvalid <= read_req_q;

        // Read request processing is complete when a response is generated
        if (!reset_n || (mmio64_if.rvalid && mmio64_if.rready))
        begin
            mmio64_reg.arvalid <= 1'b0;
            read_req_q <= 1'b0;
            mmio64_if.rvalid <= 1'b0;
        end
    end

    // Reduce the mandatory feature header CSRs (read address 'h?)
    t_mmio_value dfh_afu_id_q;
    always_ff @(posedge clk)
    begin
        case (mmio64_reg.ar.addr[6:3])
            4'h0: // AFU DFH (device feature header)
                begin
                    // Here we define a trivial feature list.  In this
                    // example, our AFU is the only entry in this list.
                    dfh_afu_id_q <= 64'b0;
                    // Feature type is AFU
                    dfh_afu_id_q[63:60] <= 4'h1;
                    // End of list (last entry in list)
                    dfh_afu_id_q[40] <= 1'b1;
                end

            // AFU_ID_L
            4'h1: dfh_afu_id_q <= afu_id[63:0];
            // AFU_ID_H
            4'h2: dfh_afu_id_q <= afu_id[127:64];
            // Full address of the request, including byte, replicated twice
            // so it can be read in either half as a 32 bit read.
            4'h7: dfh_afu_id_q <= { 32'(mmio64_reg.ar.addr), 32'(mmio64_reg.ar.addr) };
            default: dfh_afu_id_q <= 64'b0;
        endcase
    end

    //
    // Reduce 512 bit write data vector to indexed 64 bit register.
    //
    t_mmio_value [7:0] wr_data_512;
    assign wr_data_512 = mmio512_reg.w.data;
    t_mmio_value wr_data_512_q;

    always_ff @(posedge clk)
    begin
        wr_data_512_q <= wr_data_512[mmio64_reg.ar.addr[5:3]];
    end

    logic [63:0] afu_status_reg;
    assign afu_status_reg =
        { 32'h0,  // reserved
          16'(`OFS_PLAT_PARAM_CLOCKS_PCLK_FREQ),
          2'h0,	  // 64 bit read/write bus
          10'h0,  // reserved
          4'h1    // AXI MMIO interfaces
          };

    // Second cycle selects from among the already reduced groups
    always_ff @(posedge clk)
    begin
        mmio64_if.r <= '0;
        mmio64_if.r.id <= mmio64_reg.ar.id;
        mmio64_if.r.user <= mmio64_reg.ar.user;

        casez (read_idx_q)
            // AFU DFH (device feature header) and AFU ID
            12'h00?: mmio64_if.r.data <= dfh_afu_id_q;

            // Status register
            12'h010: mmio64_if.r.data <= afu_status_reg;

            // 64 bit write state
            12'h020: mmio64_if.r.data <= mmio64_reg.w.data;
            12'h030: mmio64_if.r.data <= 64'(mmio64_reg.aw.addr);
            12'h031: mmio64_if.r.data <= 64'(mmio64_reg.w.strb);

            // 512 bit write state. The wide data is mapped to
            // 8 64 bit registers in 'h030-'h037.
            12'h04?: mmio64_if.r.data <= wr_data_512_q;
            12'h050: mmio64_if.r.data <= 64'(mmio512_reg.aw.addr);
            12'h051: mmio64_if.r.data <= 64'(mmio512_reg.w.strb);

            default: mmio64_if.r.data <= 64'h0;
        endcase // casez (read_idx_q)
    end

    // Tie off dummy 512 MMIO read wires. The wide MMIO is write only.
    assign mmio512_if.arready = 1'b0;
    assign mmio512_if.rvalid = 1'b0;
    assign mmio512_if.r = '0;

endmodule // afu
