// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Wire together two CCI-P instances.
//
module ofs_plat_ccip_if_connect
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,
    ofs_plat_host_ccip_if.to_afu to_afu
    );

    assign to_afu.clk = to_fiu.clk;
    assign to_afu.reset_n = to_fiu.reset_n;

    assign to_fiu.sTx = to_afu.sTx;
    assign to_afu.sRx = to_fiu.sRx;

    assign to_afu.error = to_fiu.error;
    assign to_afu.instance_number = to_fiu.instance_number;

endmodule // ofs_plat_ccip_if_connect
