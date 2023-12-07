// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Definition of the host channel interface between the platform (blue bits)
// and the AFU (green bits). This is the fixed interface that crosses the
// PR boundary.
//
// The default parameter state must define a configuration that matches
// the hardware.
//=
//= _@group@ is replaced with the group number by the gen_ofs_plat_if script
//= as it generates a platform-specific build/platform/ofs_plat_if tree.
//
interface ofs_plat_host_chan_@group@_fiu_if
  #(
    parameter ENABLE_LOG = 0,
    parameter NUM_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_NUM_PORTS
    );

    // A hack to work around compilers complaining of circular dependence
    // incorrectly when trying to make a new interface from an existing
    // interface's parameters.
    localparam NUM_PORTS_ = $bits(logic [NUM_PORTS:0]) - 1;

    ofs_plat_host_chan_@group@_axis_pcie_tlp_if
      #(
        .LOG_CLASS(ENABLE_LOG ? ofs_plat_log_pkg::HOST_CHAN : ofs_plat_log_pkg::NONE)
        )
        ports[(NUM_PORTS != 0) ? NUM_PORTS : 1]();

endinterface // ofs_plat_host_chan_@group@_fiu_if
