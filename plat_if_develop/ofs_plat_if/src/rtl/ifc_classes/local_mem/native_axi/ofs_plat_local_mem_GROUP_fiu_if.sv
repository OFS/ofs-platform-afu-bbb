// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Definition of the local memory interface between the platform (blue bits)
// and the AFU (green bits). This is the fixed interface that crosses the
// PR boundary.
//
// The default parameter state must define a configuration that matches
// the hardware.
//=
//= _@group@ is replaced with the group number by the gen_ofs_plat_if script
//= as it generates a platform-specific build/platform/ofs_plat_if tree.
//
interface ofs_plat_local_mem_@group@_fiu_if
  #(
    parameter ENABLE_LOG = 0,
    parameter NUM_BANKS = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_NUM_BANKS,
    parameter WAIT_REQUEST_ALLOWANCE = 0
    );

    // A hack to work around compilers complaining of circular dependence
    // incorrectly when trying to make a new ofs_plat_local_mem_if from an
    // existing one's parameters.
    localparam NUM_BANKS_ = $bits(logic [NUM_BANKS:0]) - 1;

    ofs_plat_axi_mem_if
      #(
        .LOG_CLASS(ENABLE_LOG ? ofs_plat_log_pkg::LOCAL_MEM : ofs_plat_log_pkg::NONE),

        .WAIT_REQUEST_ALLOWANCE(WAIT_REQUEST_ALLOWANCE),
        `LOCAL_MEM_@GROUP@_AXI_MEM_PARAMS_FULL_BUS_DEFAULT
        )
        banks[NUM_BANKS]();

endinterface // ofs_plat_local_mem_@group@_fiu_if
