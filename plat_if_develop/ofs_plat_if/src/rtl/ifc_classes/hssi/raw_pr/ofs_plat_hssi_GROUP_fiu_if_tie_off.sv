// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Tie off a single hssi_if port.
//

`include "ofs_plat_if.vh"

module ofs_plat_hssi_@group@_fiu_if_tie_off
   (
    pr_hssi_@group@_if.to_fiu port
    );

    always_comb
    begin
        //
        // *** Platform-specific tie-off assignments go here ***
        //
    end

endmodule // ofs_plat_hssi_@group@_fiu_if_tie_off
