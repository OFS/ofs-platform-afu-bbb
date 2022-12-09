// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export the host channel as Avalon interfaces.
//

`include "ofs_plat_if.vh"

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    // ====================================================================
    //
    //  Get an Avalon host channel connection from the platform.
    //
    // ====================================================================

    // Host memory AFU master
    ofs_plat_avalon_mem_rdwr_if
      #(
        `HOST_CHAN_AVALON_MEM_RDWR_PARAMS,
        .BURST_CNT_WIDTH(4),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_to_afu();

    // 64 bit read/write MMIO AFU slave
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu();

    // 512 bit write-only MMIO AFU slave
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(512),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio512_wr_to_afu();

    // Map FIU interface to Avalon host memory and both MMIO ports
    ofs_plat_host_chan_as_avalon_mem_rdwr_with_dual_mmio
      #(
        .ADD_CLOCK_CROSSING(1),
        .ADD_TIMING_REG_STAGES(2)
        )
      primary_avalon
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu,
        .mmio_to_afu(mmio64_to_afu),
        .mmio_wr_to_afu(mmio512_wr_to_afu),

        // Use user clock
        .afu_clk(plat_ifc.clocks.uClk_usr.clk),
        .afu_reset_n(plat_ifc.clocks.uClk_usr.reset_n)
        );


    // ====================================================================
    //
    //  Tie off unused ports.
    //
    // ====================================================================

    ofs_plat_if_tie_off_unused
      #(
        // Masks are bit masks, with bit 0 corresponding to port/bank zero.
        // Set a bit in the mask when a port is IN USE by the design.
        // This way, the AFU does not need to know about every available
        // device. By default, devices are tied off.
        .HOST_CHAN_IN_USE_MASK(1)
        )
        tie_off(plat_ifc);


    // ====================================================================
    //
    //  Pass the constructed interfaces to the AFU.
    //
    // ====================================================================

    afu afu
      (
       .mmio64_if(mmio64_to_afu),
       .mmio512_if(mmio512_wr_to_afu)
       );

    // Tie off host memory -- not used by this test
    assign host_mem_to_afu.rd_address = '0;
    assign host_mem_to_afu.rd_read = '0;
    assign host_mem_to_afu.rd_burstcount = '0;
    assign host_mem_to_afu.rd_byteenable = '0;
    assign host_mem_to_afu.rd_user = '0;
    assign host_mem_to_afu.wr_address = '0;
    assign host_mem_to_afu.wr_write = '0;
    assign host_mem_to_afu.wr_burstcount = '0;
    assign host_mem_to_afu.wr_writedata = '0;
    assign host_mem_to_afu.wr_byteenable = '0;
    assign host_mem_to_afu.wr_user = '0;

endmodule // ofs_plat_afu
