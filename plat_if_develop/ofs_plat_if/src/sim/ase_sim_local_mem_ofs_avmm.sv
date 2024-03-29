// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Instantiate Avalon local memory models.
//

`include "platform_if.vh"

module ase_sim_local_mem_ofs_avmm
  #(
    parameter NUM_BANKS = 2,
    parameter ADDR_WIDTH = 27,
    parameter DATA_WIDTH = 512,
    parameter BURST_CNT_WIDTH = 7,
    parameter MASKED_SYMBOL_WIDTH = 8
    )
   (
    // Local memory as Avalon source
    ofs_plat_avalon_mem_if.to_source local_mem[NUM_BANKS],

    // Memory clocks, one for each bank
    output logic clks[NUM_BANKS]
    );

    logic ddr_reset_n;
    logic [NUM_BANKS-1:0] ddr_pll_ref_clk;
    real delay = 1875; // 266.666 MHz

    initial begin
      #0     ddr_reset_n = 0;
             ddr_pll_ref_clk = {NUM_BANKS{1'b0}};
      #10000 ddr_reset_n = 1;
    end

    // Number of bytes in a data line
    localparam DATA_N_BYTES = (DATA_WIDTH + 7) / MASKED_SYMBOL_WIDTH;

    // Older ASE versions have fixed-size burst emulation. We will map
    // to the simulated platform's width below
    localparam EMUL_BURST_CNT_WIDTH = 7;

    logic emul_waitrequest[NUM_BANKS];
    logic [DATA_WIDTH-1:0] emul_readdata[NUM_BANKS];
    logic emul_readdatavalid[NUM_BANKS];

    logic [EMUL_BURST_CNT_WIDTH-1:0] emul_burstcount[NUM_BANKS];
    logic [DATA_WIDTH-1:0] emul_writedata[NUM_BANKS];
    logic [ADDR_WIDTH-1:0] emul_address[NUM_BANKS];
    logic emul_write[NUM_BANKS];
    logic emul_read[NUM_BANKS];
    logic [DATA_N_BYTES-1:0] emul_byteenable[NUM_BANKS];

    // emif model
    generate
        for (genvar b = 0; b < NUM_BANKS; b = b + 1)
        begin : b_emul
            // Slightly different clock on each bank
            always #(delay+b) ddr_pll_ref_clk[b] = ~ddr_pll_ref_clk[b];

            emif_ddr4
              #(
                .DDR_ADDR_WIDTH(local_mem[b].ADDR_WIDTH),
                .DDR_DATA_WIDTH(local_mem[b].DATA_WIDTH)
                )
              emif_ddr4
               (
                .ddr_avmm_waitrequest                (emul_waitrequest[b]),
                .ddr_avmm_readdata                   (emul_readdata[b]),
                .ddr_avmm_readdatavalid              (emul_readdatavalid[b]),
                .ddr_avmm_burstcount                 (emul_burstcount[b]),
                .ddr_avmm_writedata                  (emul_writedata[b]),
                .ddr_avmm_address                    (emul_address[b]),
                .ddr_avmm_write                      (emul_write[b]),
                .ddr_avmm_read                       (emul_read[b]),
                .ddr_avmm_byteenable                 (emul_byteenable[b]),
                .ddr_avmm_clk_clk                    (clks[b]),

                .ddr_global_reset_reset_sink_reset_n (ddr_reset_n),
                .ddr_pll_ref_clk_clock_sink_clk      (ddr_pll_ref_clk[b])
                );
        end
    endgenerate

    //
    // Older ASE implementations of emif_ddr4 don't support a parameter
    // to set BURST_CNT_WIDTH. To maintain backwards compatibility, we
    // map from local_mem burst counts to fixed emif_ddr4.
    //
    ofs_plat_avalon_mem_if
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_CNT_WIDTH(EMUL_BURST_CNT_WIDTH),
        .MASKED_SYMBOL_WIDTH(MASKED_SYMBOL_WIDTH)
        )
      mem_burst[NUM_BANKS]();

    generate
        for (genvar b = 0; b < NUM_BANKS; b = b + 1)
        begin : b_bridge
            //
            // Map local_mem to the ASE emulator's burst size. This will be
            // invisible to the simulated AFU.
            //
            ofs_plat_avalon_mem_if_map_bursts bmap
               (
                .mem_source(local_mem[b]),
                .mem_sink(mem_burst[b])
                );

            assign mem_burst[b].clk = local_mem[b].clk;
            assign mem_burst[b].reset_n = local_mem[b].reset_n;
            assign mem_burst[b].instance_number = local_mem[b].instance_number;

            //
            // Add a bridge between the emulator and the DUT in order to eliminate
            // timing glitches induces by the DDR model. Some model signals aren't
            // quite aligned to the clock, leading to random failures in some RTL
            // emulators.
            //
            ase_sim_local_mem_avmm_bridge
              #(
                .DATA_WIDTH(DATA_WIDTH),
                .HDL_ADDR_WIDTH(ADDR_WIDTH),
                .BURSTCOUNT_WIDTH(mem_burst[b].BURST_CNT_WIDTH)
                )
              bridge
               (
                .clk(mem_burst[b].clk),
                .reset(!mem_burst[b].reset_n),

                .s0_waitrequest(mem_burst[b].waitrequest),
                .s0_readdata(mem_burst[b].readdata),
                .s0_readdatavalid(mem_burst[b].readdatavalid),
                .s0_response(),
                .s0_burstcount(mem_burst[b].burstcount),
                .s0_writedata(mem_burst[b].writedata),
                .s0_address(mem_burst[b].address),
                .s0_write(mem_burst[b].write),
                .s0_read(mem_burst[b].read),
                .s0_byteenable(mem_burst[b].byteenable),
                .s0_debugaccess(1'b0),

                .m0_waitrequest(emul_waitrequest[b]),
                .m0_readdata(emul_readdata[b]),
                .m0_readdatavalid(emul_readdatavalid[b]),
                .m0_response('x),
                .m0_burstcount(emul_burstcount[b]),
                .m0_writedata(emul_writedata[b]),
                .m0_address(emul_address[b]),
                .m0_write(emul_write[b]),
                .m0_read(emul_read[b]),
                .m0_byteenable(emul_byteenable[b]),
                .m0_debugaccess()
                );

            assign mem_burst[b].response = '0;

            // Write response not implemented
            assign mem_burst[b].writeresponsevalid = 1'b0;
            assign mem_burst[b].writeresponse = '0;
        end
    endgenerate

endmodule // ase_sim_local_mem_ofs_avmm
