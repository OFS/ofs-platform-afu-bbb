// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Loaded only in OPAE SDK Platform Interface Manager compatibility mode.
//

`ifndef __PLATFORM_SHIM_CCIP_STD_AFU__
`define __PLATFORM_SHIM_CCIP_STD_AFU__

`include "platform_if.vh"

// Force the shim to be instantiated
`undef PLATFORM_SHIM_MODULE_NAME
`define PLATFORM_SHIM_MODULE_NAME platform_shim_ccip_std_afu

//
// Because CCI-P's clocks are passed as separate wires to ccip_std_afu
// we can't simply change the primary clock for CCI-P traffic.  Here
// we guarantee that the macro `PLATFORM_PARAM_CCI_P_CLOCK matches the
// CCI-P clock coming out of the Platform Interface Manager.  By
// default it is pClk.  It will only change when an AFU's JSON database
// requests CCI-P on a different clock.
//
`ifndef PLATFORM_PARAM_CCI_P_CLOCK
    `define PLATFORM_PARAM_CCI_P_CLOCK pClk
`elsif PLATFORM_PARAM_CCI_P_CLOCK_IS_DEFAULT
    `undef PLATFORM_PARAM_CCI_P_CLOCK
    `define PLATFORM_PARAM_CCI_P_CLOCK pClk
`endif

// The standard reset signal is moved to the `PLATFORM_PARAM_CCI_P_CLOCK
// domain.  Provide a macro for reset for symmetry.
`define PLATFORM_PARAM_CCI_P_RESET pck_cp2af_softReset


//
// The set of parameters passed to top-level modules may vary, depending on
// both the needs of an AFU and the interfaces offered by individual
// platforms. The problem with this variable number of parameters is
// syntactic. It is difficult to know when commas have to be inserted
// between parameters. These macros maintain state that properly inserts
// commas between parameters that may or may not be set, based on
// preprocessor macros.
//

// Begin a list of parameters with `PLATFORM_ARG_LIST_BEGIN
`define PLATFORM_ARG_LIST_BEGIN \
    `undef PLATFORM_ARG_LIST_SEPARATOR \
    `define PLATFORM_ARG_LIST_SEPARATOR

// Add a parameter with `PLATFORM_ARG_APPEND(parameter text)
`define PLATFORM_ARG_APPEND(arg) \
    `PLATFORM_ARG_LIST_SEPARATOR arg \
    `undef PLATFORM_ARG_LIST_SEPARATOR \
    `define PLATFORM_ARG_LIST_SEPARATOR ,

`endif // __PLATFORM_SHIM_CCIP_STD_AFU__
