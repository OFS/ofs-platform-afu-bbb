//
// Copyright (c) 2019, Intel Corporation
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

//
// Wrapper module to import and configure the CCI-P interface.
//

`ifndef __CCIP_IF_VH__
`define __CCIP_IF_VH__

//
// These macros indicate the presence of additions to features that changed
// after the initial release, allowing RTL to work with multiple versions.
//

// The fields required to encode speculative loads are available when
// CCIP_ENCODING_HAS_RDLSPEC is defined.
//
// Speculative loads may be useful for emitting a load prefetch with virtual
// addresses when it is possible that the virtual address is invalid (has no
// translation). Speculative reads return a flag indicating failure and
// don't trigger a hard failure. The MPF BBB can be configured to honor
// eREQ_RDLSPEC. FIM's that take only physical addresses do not support
// speculative reads.
`define CCIP_ENCODING_HAS_RDLSPEC 1
// CCIP_RDLSPEC_AVAIL is maintained for legacy code support. In new code
// use the new name, CCIP_ENCODING_HAS_RDLSPEC. They are equivalent.
`define CCIP_RDLSPEC_AVAIL 1

// The fields required to encode partial-line writes are present when
// CCIP_ENCODING_HAS_BYTE_WR is defined.
//
// Be careful! This flag only indicates whether the CCI-P data structures
// can encode byte enable. The flag does not indicate whether the platform
// actually honors the encoding. For that, AFUs must check the value of
// ccip_cfg_pkg::BYTE_EN_SUPPORTED.
`define CCIP_ENCODING_HAS_BYTE_WR 1


import ccip_if_pkg::*;

`endif // __CCIP_IF_VH__
