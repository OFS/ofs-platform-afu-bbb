//
// Copyright (c) 2021, Intel Corporation
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
// This gasket maps the PIM's internal PCIe TLP representation to the PCIe
// subsystem in the FIM. Each supported flavor of FIM has a gasket.
//
// Each gasket implementation provides some common parameters and types
// that will be consumed by the platform-independent PIM TLP mapping code.
// The gasket often sets these parameters by importing values from the
// FIM.
//

`include "ofs_plat_if.vh"

package ofs_plat_host_chan_@group@_fim_gasket_pkg;

    // Largest tag value allowed for AFU->host requests
    localparam MAX_OUTSTANDING_DMA_RD_REQS = ofs_pcie_ss_cfg_pkg::PCIE_EP_MAX_TAGS;
    // Largest tag value permitted in the FIM configuration for host->AFU MMIO reads
    localparam MAX_OUTSTANDING_MMIO_RD_REQS = ofs_pcie_ss_cfg_pkg::PCIE_RP_MAX_TAGS;

    // Number of interrupt vectors supported
    localparam NUM_AFU_INTERRUPTS = 4; // XXX ofs_pcie_ss_cfg_pkg::NUM_AFU_INTERRUPTS;

    localparam NUM_FIM_PCIE_TLP_CH = ofs_pcie_ss_cfg_pkg::NUM_OF_STREAMS;

    //
    // Data types in the FIM's AXI streams
    //

    // The PCIe SS breaks the data vector into segments of equal size.
    // Segments are legal header starting points within the data vector.
    localparam FIM_PCIE_SEG_WIDTH = ofs_pcie_ss_cfg_pkg::TDATA_WIDTH /
                                    ofs_pcie_ss_cfg_pkg::NUM_OF_SEG;
    // Segment width in bytes (useful for indexing tkeep as valid bits)
    localparam FIM_PCIE_SEG_BYTES = FIM_PCIE_SEG_WIDTH / 8;
    typedef logic [FIM_PCIE_SEG_WIDTH-1:0] t_ofs_fim_axis_pcie_seg;

    // Represent the data vector as a union of two options: "payload" is the
    // full width and "segs" breaks payload into NUM_OF_SEG segments.
    typedef union packed {
        logic [ofs_pcie_ss_cfg_pkg::TDATA_WIDTH-1:0] payload;
        t_ofs_fim_axis_pcie_seg [ofs_pcie_ss_cfg_pkg::NUM_OF_SEG-1:0] segs;
    } t_ofs_fim_axis_pcie_tdata;

    localparam FIM_PCIE_TKEEP_WIDTH = (ofs_pcie_ss_cfg_pkg::TDATA_WIDTH / 8);
    typedef logic [FIM_PCIE_TKEEP_WIDTH-1:0] t_ofs_fim_axis_pcie_tkeep;

    // The PIM's representation of PCIe SS user bits adds sop and eop flags
    // to each segment in order to avoid having to recalculate sop at every
    // point that monitors the stream.
    typedef struct packed {
        logic dm_mode;	// Power user (0) or data mover (1) packet encoding
        logic sop;
        logic eop;
    } t_ofs_fim_axis_pcie_seg_tuser;

    typedef t_ofs_fim_axis_pcie_seg_tuser [ofs_pcie_ss_cfg_pkg::NUM_OF_SEG-1:0]
        t_ofs_fim_axis_pcie_tuser;


    // Treat a "line" as the width of the PCIe stream's data bus, called a "flit"
    // in the PIM .ini file.
    localparam int MAX_BW_ACTIVE_RD_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_RD;
    localparam int MAX_BW_ACTIVE_WR_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_WR;


    // Pick out a TLP header from the data vector, given a starting segment index.
    function automatic pcie_ss_hdr_pkg::PCIe_PUReqHdr_t ofs_fim_gasket_pcie_hdr_from_seg(
        input int s,
        input t_ofs_fim_axis_pcie_tdata data
        );

        return data.payload[s*FIM_PCIE_SEG_WIDTH +: $bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t)];

    endfunction // ofs_fim_gasket_pcie_hdr_from_seg


    // synthesis translate_off

    //
    // Debugging functions
    //

    task ofs_fim_gasket_log_pcie_st(
        input int log_fd,
        input string log_class_name,
        input string ctx_name,
        input int unsigned instance_number,
        input t_ofs_fim_axis_pcie_tdata data,
        input t_ofs_fim_axis_pcie_tkeep keep,
        input t_ofs_fim_axis_pcie_tuser user
        );

        int printed_msg = 0;
        for (int s = 0; s < ofs_pcie_ss_cfg_pkg::NUM_OF_SEG; s = s + 1)
        begin
            if (keep[s * FIM_PCIE_SEG_BYTES])
            begin
                if (user[s].sop)
                begin
                    // Segment is SOP. Print header.
                    $fwrite(log_fd, "%s: %t %s %0d seg%0d sop %s %s keep 0x%x data 0x%x\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, s,
                            (user[s].eop ? "eop" : "   "),
                            pcie_ss_hdr_pkg::func_hdr_to_string(
                                !user[s].dm_mode,
                                ofs_fim_gasket_pcie_hdr_from_seg(s, data)),
                            keep[s * FIM_PCIE_SEG_BYTES +: FIM_PCIE_SEG_BYTES],
                            data);

                    printed_msg = 1;
                end
                else
                begin
                    // Segment is just data
                    $fwrite(log_fd, "%s: %t %s %0d seg%0d     %s keep 0x%x data 0x%x\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, s,
                            (user[s].eop ? "eop" : "   "),
                            keep[s * FIM_PCIE_SEG_BYTES +: FIM_PCIE_SEG_BYTES],
                            data);

                    printed_msg = 1;
                end
            end
        end

        // If no message printed yet then the data has no sop or eop. Print the data.
        if (printed_msg == 0)
        begin
            $fwrite(log_fd, "%s: %t %s %0d seg0         data 0x%x\n",
                    ctx_name, $time,
                    log_class_name,
                    instance_number,
                    data);
        end

        $fflush(log_fd);

    endtask // ofs_fim_gasket_log_pcie_st

    // synthesis translate_on

endpackage // ofs_plat_host_chan_@group@_fim_gasket_pkg
