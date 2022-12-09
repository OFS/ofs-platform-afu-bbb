// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Split a CCI-P interface into separate host memory and MMIO interfaces.
// The result is a pair of CCI-P interfaces, with all MMIO traffic
// directed to one and all non-MMIO traffic to the host memory interface.
//

`include "ofs_plat_if.vh"

module ofs_plat_shim_ccip_split_mmio
   (
    // Connection toward the FIU (both host memory and MMIO)
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Host memory traffic
    ofs_plat_host_ccip_if.to_afu host_mem,

    // MMIO traffic
    ofs_plat_host_ccip_if.to_afu mmio
    );

    assign host_mem.clk = to_fiu.clk;
    assign mmio.clk = to_fiu.clk;

    assign host_mem.reset_n = to_fiu.reset_n;
    assign mmio.reset_n = to_fiu.reset_n;

    assign host_mem.error = to_fiu.error;
    assign mmio.error = to_fiu.error;

    assign host_mem.instance_number = to_fiu.instance_number;
    assign mmio.instance_number = to_fiu.instance_number;


    //
    // Host memory connections
    //
    assign to_fiu.sTx.c0 = host_mem.sTx.c0;
    assign to_fiu.sTx.c1 = host_mem.sTx.c1;

    assign host_mem.sRx.c0TxAlmFull = to_fiu.sRx.c0TxAlmFull;
    assign host_mem.sRx.c1TxAlmFull = to_fiu.sRx.c1TxAlmFull;
    assign host_mem.sRx.c1 = to_fiu.sRx.c1;

    always_comb
    begin
        host_mem.sRx.c0 = to_fiu.sRx.c0;
        host_mem.sRx.c0.mmioRdValid = 1'b0;
        host_mem.sRx.c0.mmioWrValid = 1'b0;
    end


    //
    // MMIO connections
    //
    assign to_fiu.sTx.c2 = mmio.sTx.c2;

    assign mmio.sRx.c0TxAlmFull = 1'b1;
    assign mmio.sRx.c1TxAlmFull = 1'b1;
    assign mmio.sRx.c1 = t_if_ccip_c1_Rx'(0);

    always_comb
    begin
        mmio.sRx.c0 = to_fiu.sRx.c0;
        mmio.sRx.c0.rspValid = 1'b0;
    end

endmodule // ofs_plat_shim_ccip_split_mmio
