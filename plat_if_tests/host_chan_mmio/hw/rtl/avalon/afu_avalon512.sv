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
    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_master mmio512_if
    );

    logic clk;
    assign clk = mmio512_if.clk;
    logic reset_n;
    assign reset_n = mmio512_if.reset_n;

    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    typedef logic [7:0][63:0] t_mmio_value;
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

    logic [511:0] wr_data_bits_512;
    t_mmio_value wr_data_512;
    assign wr_data_512 = wr_data_bits_512;

    logic [63:0] wr_mask_512;
    logic [mmio512_if.ADDR_WIDTH-1 : 0] wr_addr_512;
    // Byte offset within the 512 bit entry
    logic [5:0] wr_byte_idx_512;

    always_ff @(posedge clk)
    begin
        if (mmio512_if.write && ! mmio512_if.waitrequest)
        begin
            for (int i = 0; i < 64; i = i + 1)
            begin
                if (mmio512_if.byteenable[i])
                    wr_data_bits_512[i*8 +: 8] <= mmio512_if.writedata[i*8 +: 8];
            end
            wr_mask_512 <= mmio512_if.byteenable;
            wr_addr_512 <= mmio512_if.address;
            wr_byte_idx_512 <= mask_to_idx(64, mmio512_if.byteenable);
        end

        if (!reset_n)
        begin
            wr_data_bits_512 <= ~'0;
            wr_mask_512 <= ~'0;
            wr_addr_512 <= ~'0;
            wr_byte_idx_512 <= ~'0;
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
        read_req_q <= mmio512_if.read && ! mmio512_if.waitrequest;
        read_idx_q <= t_csr_idx'(mmio512_if.address);

        if (!reset_n)
        begin
            read_req_q <= 1'b0;
        end
    end

    logic [31:0] req_byte_addr;
    assign req_byte_addr = 32'({ mmio512_if.address,
                                 6'(mask_to_idx(64, mmio512_if.byteenable)) });

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
        dfh_afu_id_q[7] <= { req_byte_addr, req_byte_addr };
    end

    logic [63:0] afu_status_reg;
    assign afu_status_reg =
        { 32'h0,  // reserved
          16'(`OFS_PLAT_PARAM_CLOCKS_PCLK_FREQ),
          2'h3,   // 512 bit read/write bus
          9'h0,  // reserved
          // Will the AFU consume a 512 bit MMIO write?
          1'(ofs_plat_host_chan_pkg::MMIO_512_WRITE_SUPPORTED),
          4'h0    // Avalon MMIO interfaces
          };

    // Second cycle selects from among the already reduced groups
    always_ff @(posedge clk)
    begin
        mmio512_if.readdatavalid <= read_req_q;

        casez (read_idx_q)
            // AFU DFH (device feature header) and AFU ID
            9'h000: mmio512_if.readdata <= dfh_afu_id_q;

            // Status register
            9'h002: mmio512_if.readdata <= 512'(afu_status_reg);

            // 64 bit write state. (Behave as though the interace is 64 bit data.)
            9'h004: mmio512_if.readdata <= wr_data_512[wr_byte_idx_512[5:3]];
            9'h006: mmio512_if.readdata <= { '0,
                                             64'(wr_mask_512[8 * wr_byte_idx_512[5:3] +: 8]),
                                             64'({ wr_addr_512, wr_byte_idx_512 }) };

            // 512 bit write state. The wide data is mapped to
            // 8 64 bit registers in 'h030-'h037.
            9'h008: mmio512_if.readdata <= wr_data_512;
            9'h00a: mmio512_if.readdata <= { '0,
                                             64'(wr_mask_512),
                                             64'({ wr_addr_512, wr_byte_idx_512 }) };

            default: mmio512_if.readdata <= 64'h0;
        endcase // casez (read_idx_q)
    end

    assign mmio512_if.response = '0;

endmodule // afu
