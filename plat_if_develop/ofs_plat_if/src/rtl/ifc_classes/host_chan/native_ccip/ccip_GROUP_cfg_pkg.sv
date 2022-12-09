// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if_top_config.vh"

//
// Platform-specific CCI-P configuration.  From this class an AFU can learn
// which channels are available, what size requests are supported, etc.
// Some tuning parameters, such as suggested buffer depth are also here.
//
// It is assumed that this package will NOT be wildcard imported.  The
// package name serves as a prefix instead of making all symbols inside
// the package long.
//

package ccip_@group@_cfg_pkg;

    parameter VERSION_NUMBER = 1;

    // All available request types on c0 and c1.  Platforms capability
    // databases will construct a set to indicate which request types are
    // supported.
    typedef enum
    {
        C0_REQ_RDLINE_S = 1,
        C0_REQ_RDLINE_I = 2,
        C0_REQ_RDLSPEC_S = 4,
        C0_REQ_RDLSPEC_I = 8
    }
    e_c0_req;

    typedef enum
    {
        C1_REQ_WRLINE_S = 1,
        C1_REQ_WRLINE_I = 2,
        C1_REQ_WRPUSH_I = 4,
        C1_REQ_WRFENCE = 8,
        C1_REQ_INTR = 16
    }
    e_c1_req;

    //
    // Configuration parameters are set in the OFS platform header files.
    //

    // Is a given VC supported, indexed by t_ccip_vc?  (0 or 1)
    parameter int VC_SUPPORTED[4] = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_VC_SUPPORTED;
    parameter ccip_if_pkg::t_ccip_vc VC_DEFAULT = ccip_if_pkg::t_ccip_vc'(`OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_VC_DEFAULT);
    parameter int NUM_PHYS_CHANNELS = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_NUM_PHYS_CHANNELS;

    // Is a given request length supported, indexed by t_ccip_clLen?  (0 or 1)
    parameter int CL_LEN_SUPPORTED[4] = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_CL_LEN_SUPPORTED;

    // Does the platform honor byte enable to update a sub-region of a line?
    parameter int BYTE_EN_SUPPORTED = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_BYTE_EN_SUPPORTED;

    // Recommended number of edge register stages for CCI-P request/response
    // signals.  This is expected to be one on all platforms, reflecting the
    // requirement in the specification that all CCI-P Tx and Rx signals be
    // registered by the AFU.
    parameter int SUGGESTED_TIMING_REG_STAGES =
        `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_SUGGESTED_TIMING_REG_STAGES;

    // Mask of request types (e_c0_req and e_c1_req) supported by the platform.
    parameter C0_SUPPORTED_REQS = int'(`OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_C0_SUPPORTED_REQS);
    parameter C1_SUPPORTED_REQS = int'(`OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_C1_SUPPORTED_REQS);

    // Use this to set the buffer depth for incoming MMIO read requests
    parameter MAX_OUTSTANDING_MMIO_RD_REQS = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_OUTSTANDING_MMIO_RD_REQS;

    // Recommended numbers of lines in flight to achieve maximum bandwidth.
    // Maximum bandwidth tends to be a function of the number of lines in
    // flight and not the number of requests.  Each of these is indexed
    // by virtual channel (t_ccip_vc).
    parameter int C0_MAX_BW_ACTIVE_LINES[4] = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_LINES_C0;
    parameter int C1_MAX_BW_ACTIVE_LINES[4] = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_LINES_C1;

    // pClk frequency
    parameter int PCLK_FREQ = `OFS_PLAT_PARAM_CLOCKS_PCLK_FREQ;

endpackage // ccip_cfg_pkg
