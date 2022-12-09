// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Definition of the HSSI interface between the platform (blue bits)
// and the AFU (green bits). This is the fixed interface that crosses the
// PR boundary.
//
// The default parameter state must define a configuration that matches
// the hardware.
//=
//= _@group@ is replaced with the group number by the gen_ofs_plat_if script
//= as it generates a platform-specific build/platform/ofs_plat_if tree.
//
interface ofs_plat_hssi_@group@_fiu_if
  #(
    parameter ENABLE_LOG = 0,
    parameter NUM_CHANNELS = `OFS_PLAT_PARAM_HSSI_@GROUP@_NUM_CHANNELS
    );

    // A hack to work around compilers complaining of circular dependence
    // incorrectly when trying to make a new ofs_plat_hssi_if from an
    // existing one's parameters.
    localparam NUM_CHANNELS_ = $bits(logic [NUM_CHANNELS:0]) - 1;

    // Wrap Rx and Tx streams between an Ethernet MAC in the FIM
    // and a traffic manager in the AFU.
    ofs_plat_hssi_@group@_channel_if
      #(
        .LOG_CLASS(ENABLE_LOG ? ofs_plat_log_pkg::HSSI : ofs_plat_log_pkg::NONE)
        )
        channels[NUM_CHANNELS]();

endinterface // ofs_plat_hssi_@group@_fiu_if
