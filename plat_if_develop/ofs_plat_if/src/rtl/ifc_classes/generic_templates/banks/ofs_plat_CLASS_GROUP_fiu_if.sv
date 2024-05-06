// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Definition of the @CLASS@ interface between the platform (blue bits)
// and the AFU (green bits). This is the fixed interface that crosses the
// PR boundary.
//
// The default parameter state must define a configuration that matches
// the hardware.
//=
//= _@group@ is replaced with the group number by the gen_ofs_plat_if script
//= as it generates a platform-specific build/platform/ofs_plat_if tree.
//
interface ofs_plat_@class@_@group@_fiu_if
  #(
    parameter ENABLE_LOG = 0,
    parameter NUM_BANKS = `OFS_PLAT_PARAM_@CLASS@_@GROUP@_NUM_BANKS
    );

`ifdef OFS_PLAT_PARAM_@CLASS@_TYPE
    // @class@ in .ini file specified a type
    `OFS_PLAT_PARAM_@CLASS@_TYPE banks[NUM_BANKS]();
`else
    // No type specified for @class@ in .ini. Use a standard naming scheme.
    @class@_@group@_if banks[NUM_BANKS]();
`endif

endinterface // ofs_plat_@class@_@group@_fiu_if
