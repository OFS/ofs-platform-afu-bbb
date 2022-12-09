// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Tie off a single local_mem platform interface bank.
//

`include "ofs_plat_if.vh"

module ofs_plat_local_mem_@group@_fiu_if_tie_off
   (
    ofs_plat_axi_mem_if.to_sink bank
    );

    always_comb
    begin
        `OFS_PLAT_AXI_MEM_IF_INIT_SOURCE_COMB(bank);
    end

endmodule // ofs_plat_local_mem_@group@_fiu_if_tie_off
