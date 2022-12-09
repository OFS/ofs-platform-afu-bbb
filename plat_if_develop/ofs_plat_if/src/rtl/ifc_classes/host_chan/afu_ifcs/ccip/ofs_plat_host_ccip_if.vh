// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
