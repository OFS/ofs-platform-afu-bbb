//==
//== Template file, parsed by gen_ofs_plat_if and ofs_template.py to generate
//== a platform-specific version.
//==
//== Template comments beginning with //== will be removed by the parser.
//==
// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef __OFS_PLAT_IF_TOP_CONFIG_VH__
`define __OFS_PLAT_IF_TOP_CONFIG_VH__

//
// This is the primary parameterization of the platform.
//
// Preprocessor parameters allow AFUs to configure their connections
// based on platform-specific details. Some of the parameters must be
// defined in order for the platform definition to conform to the OFS
// top-level interface standard.
//

//==
//== This template pattern will be replaced by scripts/platlib/ofs_template.py
//== with preprocessor definitions of each interface parameter. Parameters
//== are defined from config/defaults.ini and the platform-specific .ini file.
//==
@OFS_PLAT_IF_TEMPLATE_ALL@
@CONFIG_DEFS@
@OFS_PLAT_IF_TEMPLATE_ALL@

// ========================================================================
//
//  Compatibility
//
// ========================================================================

`include "platform_afu_top_config.vh"

//
// Define preprocessor parameters expected by older code.
//

// Is local memory available? (Required by PIM v1 AFUs.)
`ifdef OFS_PLAT_PARAM_LOCAL_MEM_NUM_BANKS
  `ifdef AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM
    `define PLATFORM_PROVIDES_LOCAL_MEMORY 1
  `elsif AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM_LEGACY_WIRES_2BANK
    `define PLATFORM_PROVIDES_LOCAL_MEMORY 1
  `endif
`endif


// ========================================================================
//
//  ASE
//
// ========================================================================

// When OFS_PLAT_PROVIDES_ASE_TOP, the OFS platform provides an ASE top-level
// module that generates ofs_plat_if. With this mechanism, the platform can
// construct a platform-specific simulated top-level environment.
// The macro specifies the module name that ASE's root module should
// instantiate.
`ifdef AFU_TOP_REQUIRES_AFU_MAIN_IF
  // Platform-specific afu_main() top-level emulation
  `define OFS_PLAT_PROVIDES_ASE_TOP ase_top_afu_main
`elsif SHARED_AFU_MAIN_TO_PORT_AFU_INSTANCES
  // The afu_main() and PIM entry in this FIM uses a standard afu_main()
  // provided by the FIM. Use that path to instantiate a PIM-based AFU.
  // We could also use ase_top_ofs_plat(), but that is a generic
  // environment constructed for simulation. We may as well simulate
  // the real afu_main() path.
  `define OFS_PLAT_PROVIDES_ASE_TOP ase_top_afu_main
`else
  // PIM ofs_plat_afu() top-level emulation
  `define OFS_PLAT_PROVIDES_ASE_TOP ase_top_ofs_plat
`endif

`endif // __OFS_PLAT_IF_TOP_CONFIG_VH__
