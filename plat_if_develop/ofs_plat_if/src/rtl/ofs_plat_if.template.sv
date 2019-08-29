//==
//== Template file, parsed by gen_ofs_plat_if and ofs_template.py to generate
//== a platform-specific version.
//==
//== Template comments beginning with //== will be removed by the parser.
//==
//
// Copyright (c) 2018, Intel Corporation
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
// ofs_plat_if is the top-level wrapper around all interfaces coming into the
// AFU PR region.
//
// Note that ofs_plat_if and the sub-interfaces it contains instantiate
// properly configured types with their default parameters. This behavior
// is crucial in order to enable platform-independent AFUs.
//

interface ofs_plat_if
  #(
    parameter ENABLE_LOG = 0
    );

    // Required: Platform top-level clocks
    wire t_ofs_plat_clocks clocks;

    // Required: ACTIVE HIGH Soft Reset (clocked by pClk)
    logic softReset;
    // Required: AFU Power State (clocked by pClk)
    t_ofs_plat_power_state pwrState;

    // Each sub-interface is a wrapper around a single vector of ports or banks.
    // Each port or bank in a vector must be the same configuration. Namely,
    // multiple banks within a local memory interface must all have the same
    // width and depth. If a platform has more than one configuration of a
    // class, e.g. both DDR and static RAM, those should be instantiated here
    // as separate interfaces.
    //==
    //== Top-level interface classes will be emitted here, using the template
    //== between instances of @OFS_PLAT_IF_TEMPLATE@ for each class and group
    //== number.
    //==
    @OFS_PLAT_IF_TEMPLATE@

    ofs_plat_@class@@group@_if
      #(
        .ENABLE_LOG(ENABLE_LOG)
        )
        @class@@group@();
    @OFS_PLAT_IF_TEMPLATE@

endinterface // ofs_plat_if
