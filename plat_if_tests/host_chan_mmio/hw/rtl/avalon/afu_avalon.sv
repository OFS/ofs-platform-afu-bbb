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
// Test Avalon interfaces for MMIO FPGA-side masters. Two sizes are instantiated
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
//         [ 3: 0] Interface type (0 for Avalon)
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
    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_master mmio64_if,
    ofs_plat_avalon_mem_if.to_master mmio512_if
    );

    logic clk;
    assign clk = mmio64_if.clk;
    logic reset_n;
    assign reset_n = mmio64_if.reset_n;

    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    typedef logic [63:0] t_mmio_value;
    typedef logic [11:0] t_csr_idx;

    // Our Avalon encoding of MMIO addresses is an index space into the
    // word size of the bus. Address 1 in a 64 bit MMIO instance is byte
    // 8. Address 1 in a 512 bit MMIO instances is byte 64. References
    // to smaller regions in MMIO space use byteenable. This mask_to_idx
    // function returns the index of the first 1 in mask, which is
    // equivalent to the byte offset from the address.
    function automatic int mask_to_idx(int mask_bits, logic [63:0] mask);
        int idx = mask_bits;

        for (int i = 0; i < mask_bits; i = i + 1)
        begin
            if (mask[i] != 1'b0)
            begin
                idx = i;
                break;
            end
        end

        return idx;
    endfunction


    // ====================================================================
    //
    //  Assert waitrequest often just to torture the slave code.
    //
    // ====================================================================

    logic [15:0] waitrequest_vec;
    assign mmio64_if.waitrequest = waitrequest_vec[0];
    assign mmio512_if.waitrequest = waitrequest_vec[8];

    always_ff @(posedge clk)
    begin
        waitrequest_vec <= { waitrequest_vec[14:0], waitrequest_vec[15] };

        if (!reset_n)
        begin
            waitrequest_vec <= { ~15'b0, 1'b0 };
        end
    end


    // ====================================================================
    //
    //  Store write requests in a register that can be read back to
    //  verify the success of the writes.
    //
    // ====================================================================

    t_mmio_value [7:0] wr_data_512;
    logic [63:0] wr_mask_512;
    logic [$bits(mmio512_if.address)-1 : 0] wr_addr_512;
    // Byte offset within the 512 bit entry
    logic [5:0] wr_byte_idx_512;

    t_mmio_value wr_data_64;
    logic [7:0] wr_mask_64;
    logic [$bits(mmio64_if.address)-1 : 0] wr_addr_64;
    // Byte offset within the 64 bit entry
    logic [2:0] wr_byte_idx_64;

    always_ff @(posedge clk)
    begin
        if (mmio512_if.write && ! mmio512_if.waitrequest)
        begin
            wr_data_512 <= mmio512_if.writedata;
            wr_mask_512 <= mmio512_if.byteenable;
            wr_addr_512 <= mmio512_if.address;
            wr_byte_idx_512 <= mask_to_idx(64, mmio512_if.byteenable);
        end

        if (mmio64_if.write && ! mmio64_if.waitrequest)
        begin
            wr_data_64 <= mmio64_if.writedata;
            wr_mask_64 <= mmio64_if.byteenable;
            wr_addr_64 <= mmio64_if.address;
            wr_byte_idx_64 <= mask_to_idx(8, mmio64_if.byteenable);
        end

        if (!reset_n)
        begin
            wr_data_512 <= ~'0;
            wr_mask_512 <= ~'0;
            wr_addr_512 <= ~'0;
            wr_byte_idx_512 <= ~'0;
            wr_data_64 <= '0;
            wr_mask_64 <= '0;
            wr_addr_64 <= '0;
            wr_byte_idx_64 <= '0;
        end
    end


    // ====================================================================
    //
    //  Handle reads.
    //
    // ====================================================================

    //
    // Register read requests for use in the second cycle of reads.
    //
    logic read_req_q;
    t_csr_idx read_idx_q;

    always_ff @(posedge clk)
    begin : r_addr
        read_req_q <= mmio64_if.read && ! mmio64_if.waitrequest;
        read_idx_q <= t_csr_idx'(mmio64_if.address);

        if (!reset_n)
        begin
            read_req_q <= 1'b0;
        end
    end

    // Reduce the mandatory feature header CSRs (read address 'h?)
    t_mmio_value dfh_afu_id_q;

    logic [31:0] req_byte_addr_64;
    assign req_byte_addr_64 = 32'({ mmio64_if.address,
                                    3'(mask_to_idx(8, mmio64_if.byteenable)) });

    always_ff @(posedge clk)
    begin
        case (mmio64_if.address[3:0])
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
            4'h8: dfh_afu_id_q <= { req_byte_addr_64, req_byte_addr_64 };
            default: dfh_afu_id_q <= 64'b0;
        endcase
    end

    //
    // Reduce 512 bit write data vector to indexed 64 bit register.
    //
    t_mmio_value wr_data_512_q;
    always_ff @(posedge clk)
    begin
        wr_data_512_q <= wr_data_512[mmio64_if.address[2:0]];
    end

    logic [63:0] afu_status_reg;
    assign afu_status_reg =
        { 32'h0,  // reserved
          16'(`OFS_PLAT_PARAM_CLOCKS_PCLK_FREQ),
          12'h0,  // reserved
          4'h0    // Avalon MMIO interfaces
          };

    // Second cycle selects from among the already reduced groups
    always_ff @(posedge clk)
    begin
        mmio64_if.readdatavalid <= read_req_q;

        casez (read_idx_q)
            // AFU DFH (device feature header) and AFU ID
            12'h00?: mmio64_if.readdata <= dfh_afu_id_q;

            // Status register
            12'h010: mmio64_if.readdata <= afu_status_reg;

            // 64 bit write state
            12'h020: mmio64_if.readdata <= wr_data_64;
            12'h030: mmio64_if.readdata <= 64'({ wr_addr_64, wr_byte_idx_64 });
            12'h031: mmio64_if.readdata <= wr_mask_64;

            // 512 bit write state. The wide data is mapped to
            // 8 64 bit registers in 'h030-'h037.
            12'h04?: mmio64_if.readdata <= wr_data_512_q;
            12'h050: mmio64_if.readdata <= 64'({ wr_addr_512, wr_byte_idx_512 });
            12'h051: mmio64_if.readdata <= wr_mask_512;

            default: mmio64_if.readdata <= 64'h0;
        endcase // casez (read_idx_q)
    end

    assign mmio64_if.response = '0;

    // Tie off dummy 512 MMIO read wires. The wide MMIO is write only.
    assign mmio512_if.readdata = '0;
    assign mmio512_if.readdatavalid = '0;
    assign mmio512_if.response = '0;

endmodule // afu
