//
// Copyright (c) 2020, Intel Corporation
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

//
// Instantiate local memory models with an AXI interface.
//
// The memory emulation primitive used by ASE has an Avalon interface.
// This module generates an AXI local memory platform interface by
// transforming the Avalon memory emulator to AXI. This is, unfortunately,
// not trivial:
//
//  - AXI responses have flow control.
//  - AXI requests have independently controlled read and write channels.
//

`include "platform_if.vh"

module ase_sim_local_mem_ofs_axi
  #(
    parameter NUM_BANKS = 2,
    parameter ADDR_WIDTH = 27,
    parameter DATA_WIDTH = 512,
    parameter BURST_CNT_WIDTH = 7,
    parameter USER_WIDTH = 8,
    parameter RID_WIDTH = 8,
    parameter WID_WIDTH = 8,
    parameter MASKED_SYMBOL_WIDTH = 8
    )
   (
    // Local memory as AXI interface
    ofs_plat_axi_mem_if.to_source local_mem[NUM_BANKS],

    // Memory clocks, one for each bank
    output logic clks[NUM_BANKS]
    );

    localparam ID_WIDTH = (WID_WIDTH > RID_WIDTH) ? WID_WIDTH : RID_WIDTH;
    localparam META_WIDTH = ID_WIDTH + USER_WIDTH;

    //
    // The underlying ASE functional memory model uses an Avalon interface.
    // Begin by instantiating the model wrapped in a PIM avalon interface,
    // which will be transformed below to AXI.
    //
    ofs_plat_avalon_mem_if
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH + 1),
        .MASKED_SYMBOL_WIDTH(MASKED_SYMBOL_WIDTH),
        .USER_WIDTH(META_WIDTH)
        )
      avmm_mem[NUM_BANKS]();

    generate
        for (genvar b = 0; b < NUM_BANKS; b = b + 1)
        begin : b_avmm
            assign avmm_mem[b].clk = local_mem[b].clk;
            assign avmm_mem[b].reset_n = local_mem[b].reset_n;
            assign avmm_mem[b].instance_number = local_mem[b].instance_number;
        end
    endgenerate

    ase_sim_local_mem_ofs_avmm
      #(
        .NUM_BANKS(NUM_BANKS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH + 1),
        .MASKED_SYMBOL_WIDTH(MASKED_SYMBOL_WIDTH)
        )
      emul
       (
        .local_mem(avmm_mem),
        .clks
        );

    //
    // Transform the AXI memory expected by the platform interface into the
    // hardware emulation interface, which is Avalon.
    //
    generate
        for (genvar b = 0; b < NUM_BANKS; b = b + 1)
        begin : b_axi
            //
            // AXI has flow control on responses and AVMM does not.
            // We need to enforce a credit limit and put some FIFOs between
            // the generated AXI interface and the underlying Avalon
            // memory emulator.
            //
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(local_mem[b])
                )
              axi_credit_if();

            assign axi_credit_if.clk = local_mem[b].clk;
            assign axi_credit_if.reset_n = local_mem[b].reset_n;
            assign axi_credit_if.instance_number = local_mem[b].instance_number;

            ofs_plat_axi_mem_if_rsp_credits
              #(
                // Unnecessarily large number of credits. This is only a simulation
                // and only part of the emulation stack, so allocate enough slots
                // to stay out of the way.
                .NUM_READ_CREDITS(512),
                .NUM_WRITE_CREDITS(512)
                )
              axi_credit
               (
                .mem_source(local_mem[b]),
                .mem_sink(axi_credit_if)
                );

            //
            // Use the clock crossing shim for its response buffering. We don't
            // need a clock crossing here, but we do need buffering for the
            // response credits managed above.
            //
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(local_mem[b])
                )
              axi_buf_if();

            assign axi_buf_if.clk = local_mem[b].clk;
            assign axi_buf_if.reset_n = local_mem[b].reset_n;
            assign axi_buf_if.instance_number = local_mem[b].instance_number;

            ofs_plat_axi_mem_if_async_shim
              #(
                // These must match the credit manager above
                .NUM_READ_CREDITS(512),
                .NUM_WRITE_CREDITS(512)
                )
              axi_buf
               (
                .mem_source(axi_credit_if),
                .mem_sink(axi_buf_if)
                );


            //
            // Map AXI to split read/write Avalon.
            //
            ofs_plat_avalon_mem_rdwr_if
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .BURST_CNT_WIDTH(BURST_CNT_WIDTH + 1),
                .MASKED_SYMBOL_WIDTH(MASKED_SYMBOL_WIDTH),
                .USER_WIDTH(META_WIDTH)
                )
              avmm_rdwr_if();

            assign avmm_rdwr_if.clk = local_mem[b].clk;
            assign avmm_rdwr_if.reset_n = local_mem[b].reset_n;
            assign avmm_rdwr_if.instance_number = local_mem[b].instance_number;

            ofs_plat_axi_mem_if_to_avalon_rdwr_if
              #(
                .GEN_RD_RESPONSE_METADATA(1),
                .PRESERVE_RESPONSE_USER(0)
                )
              map_to_avmm_rdwr
               (
                .axi_source(axi_buf_if),
                .avmm_sink(avmm_rdwr_if)
                );

            //
            // Map split read/write Avalon to shared bus Avalon, where the
            // memory is emulated.
            //
            ofs_plat_avalon_mem_rdwr_if_to_mem_if
              #(
                .LOCAL_WR_RESPONSE(1)
                )
              map_to_avmm
               (
                .mem_source(avmm_rdwr_if),
                .mem_sink(avmm_mem[b])
                );
        end
    endgenerate

endmodule // ase_sim_local_mem_ofs_axi
