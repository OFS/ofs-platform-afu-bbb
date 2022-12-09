// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// NULL AFU, resulting in tie-off of all interfaces.
//

`include "ofs_plat_if.vh"

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    // ====================================================================
    //
    //  Tie off unused ports.
    //
    // ====================================================================

    ofs_plat_if_tie_off_unused tie_off(plat_ifc);

endmodule // ofs_plat_afu
