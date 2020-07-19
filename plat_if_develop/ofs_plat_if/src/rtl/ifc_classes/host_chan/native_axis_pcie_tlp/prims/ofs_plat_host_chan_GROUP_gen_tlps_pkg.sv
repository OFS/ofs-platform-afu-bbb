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

//
// Data types used in messages through the various TLP generation modules
// here.
//

`include "ofs_plat_if.vh"

package ofs_plat_host_chan_@group@_gen_tlps_pkg;

    import ofs_plat_host_chan_@group@_pcie_tlp_pkg::*;

    // The PIM maintains a logical number of PCIe channels that is a
    // function of the channel payload width and the PIM's view of the
    // host channel data width. This makes it easier to deal with AFU
    // line sizes that are wider than a single PCIe channel. The PIM's
    // channel width is mapped to the FIU's width at the FIU edge.
    localparam NUM_PIM_PCIE_TLP_CH = ofs_plat_host_chan_@group@_pkg::DATA_WIDTH /
                                     ofs_plat_host_chan_@group@_pcie_tlp_pkg::FIU_PCIE_TLP_CH_PW;

    typedef t_ofs_plat_axis_pcie_tdata [NUM_PIM_PCIE_TLP_CH-1 : 0] t_gen_tx_tlp_vec;
    typedef t_ofs_plat_axis_pcie_tx_tuser [NUM_PIM_PCIE_TLP_CH-1 : 0] t_gen_tx_tlp_user_vec;

    // AFU's tag for a request, returned with responses. PCIe tags are a
    // separate space, assigned internally in the modules here. The AFU tag width
    // just has to be large enough to return whatever tags might reach this code.
    // The maximum tag size reaching here is typically governed by other code inside
    // the PIM, such as reorder buffers, clock crossings, etc.
    localparam AFU_TAG_WIDTH = 16;


    //
    // MMIO
    //

    // Requests to AFU
    typedef struct packed {
        t_mmio_rd_tag tag;
        logic [63:0] addr;
        logic [11:0] byte_count;
        logic is_write;
        logic [511:0] payload;
    } t_gen_tx_mmio_afu_req;

    // AFU responses
    typedef struct packed {
        t_mmio_rd_tag tag;
        logic [511:0] payload;
    } t_gen_tx_mmio_afu_rsp;

    // Host read requests, tracked internally (not for AFU)
    typedef struct packed {
        t_mmio_rd_tag tag;
        logic [6:0] lower_addr;
        logic [11:0] byte_count;
        logic [15:0] requester_id;
    } t_gen_tx_mmio_host_req;


    //
    // AFU reads
    //

    // AFU read requests
    typedef struct packed {
        logic [AFU_TAG_WIDTH-1 : 0] tag;
        // Number of lines to request
        t_tlp_payload_line_count line_count;
        logic [63:0] addr;
    } t_gen_tx_afu_rd_req;

    // Read response to AFU
    typedef struct packed {
        logic [PAYLOAD_LINE_SIZE-1 : 0] payload;
        logic [AFU_TAG_WIDTH-1 : 0] tag;
        // Line index in multi-line read
        t_tlp_payload_line_idx line_idx;
        // Done handling full request?
        logic last;
    } t_gen_tx_afu_rd_rsp;


    //
    // AFU writes
    //

    // AFU write requests
    typedef struct packed {
        logic sop;
        logic eop;

        // This group is expected only on the first beat
        logic is_fence;
        logic [AFU_TAG_WIDTH-1 : 0] tag;
        // Number of lines to request
        t_tlp_payload_line_count line_count;
        // Byte address, but the code assumes byte offset bits within a line are 0.
        logic [63:0] addr;

        // Write only a subset of the line? The write handler allows subsets
        // only when line_count is 1 since the payload length has to be known
        // in the header. Anything more flexible would require buffering entire
        // writes in order to track the mask. When enable_byte_range is set,
        // addr should still be line-aligned. The payload should remain aligned
        // to the line. The internal write processing logic will shift the
        // payload as needed.
        logic enable_byte_range;
        t_tlp_payload_line_byte_idx byte_start_idx;
        t_tlp_payload_line_byte_idx byte_len;

        logic [PAYLOAD_LINE_SIZE-1 : 0] payload;
    } t_gen_tx_afu_wr_req;

    // Write response to AFU
    typedef struct packed {
        logic [AFU_TAG_WIDTH-1 : 0] tag;
        // Line index of last line in multi-line write (zero based)
        t_tlp_payload_line_idx line_idx;
        logic is_fence;
    } t_gen_tx_afu_wr_rsp;

endpackage
