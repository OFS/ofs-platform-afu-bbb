// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Platform-specific afu_main() top-level. OFS must provide a module that
// constructs emulated devices and passes them to afu_main() ports. These
// ports may vary from platform to platform.
//

`include "ofs_plat_if.vh"

module ase_top_afu_main
   (
    input  logic pClk,
    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2
    );


`ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS
    //
    // For platforms that use the PCIe SS, common code constructs a PCIe
    // emulator instead of forcing each platform to do it.
    //
    ase_afu_main_pcie_ss ase_afu_main_pcie_ss
       (
        .*
        );
`else
    //
    // Generic afu_main() wrapper, leaving it to the platform-specific instance
    // to construct the device emulators.
    //
    ase_afu_main_emul ase_afu_main_emul
       (
        .*
        );
`endif

endmodule // ase_top_afu_main
