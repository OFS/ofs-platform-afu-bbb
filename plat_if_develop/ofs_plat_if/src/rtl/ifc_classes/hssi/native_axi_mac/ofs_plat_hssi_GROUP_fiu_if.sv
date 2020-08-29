//
// Copyright (c) 2020, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

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

    // All channels and streams share a common clock.
    wire clk;
    logic reset_n;

    // There may be other clocks defined, too.
    ofs_fim_eth_if_pkg::t_axis_eth_clocks eth_clocks;

    // Wrap Rx and Tx streams between an Ethernet MAC in the FIM
    // and a traffic manager in the AFU.
    ofs_plat_hssi_@group@_channel_if
      #(
        .LOG_CLASS(ENABLE_LOG ? ofs_plat_log_pkg::HSSI : ofs_plat_log_pkg::NONE)
        )
        channels[NUM_CHANNELS]();

endinterface // ofs_plat_hssi_@group@_fiu_if
