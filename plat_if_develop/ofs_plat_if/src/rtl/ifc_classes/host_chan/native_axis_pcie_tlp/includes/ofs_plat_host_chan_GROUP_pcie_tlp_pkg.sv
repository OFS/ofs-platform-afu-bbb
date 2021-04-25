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
// PCIe TLP type abstraction for connecting to the FIM's data structures.
//
//   The PIM uses its own encoding of TLPs internally. The encoding is a simple
//   structure that holds all the fields required to construct a real PCIe
//   header but doesn't match the normal layout. The real PCIe layout spreads
//   fields around since it grew over time. Header encoding also varies by
//   FPGA family.
//
//   The PIM uses gaskets, found in the ../prims/gasket_* directories, to map
//   the PIM's TLP header structure to the encoding expected by the FIM. Only
//   one gasket will be instantiated, depending on the FIM. Gaskets are chosen
//   in the .ini file used to instantiate and configure the PIM.
//

`include "ofs_plat_if.vh"

package ofs_plat_host_chan_@group@_pcie_tlp_pkg;

    import ofs_plat_pcie_tlp_hdr_pkg::*;

    // ====================================================================
    //
    //  PCIe parameters
    //
    // ====================================================================

    // The PIM maintains a logical number of PCIe channels that is a
    // function of the channel payload width and the PIM's view of the
    // host channel data width. This makes it easier to deal with AFU
    // line sizes that are wider than a single PCIe channel. The PIM's
    // channel width is mapped to the FIU's width at the FIU edge.
    localparam NUM_PIM_PCIE_TLP_CH = 1;

    // Tag values must be less than the maximum number of tags permitted
    // by the FIM.
    localparam MAX_OUTSTANDING_DMA_RD_REQS =
        ofs_plat_host_chan_@group@_fim_gasket_pkg::MAX_OUTSTANDING_DMA_RD_REQS;
    localparam MAX_OUTSTANDING_MMIO_RD_REQS =
        ofs_plat_host_chan_@group@_fim_gasket_pkg::MAX_OUTSTANDING_MMIO_RD_REQS;
    // Number of tags to reserve for write fences. Tags 0 through
    // MAX_OUTSTANDING_DMA_WR_FENCES will never be used for normal reads.
    localparam MAX_OUTSTANDING_DMA_WR_FENCES = 4;

    localparam NUM_AFU_INTERRUPTS =
        ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_AFU_INTERRUPTS;
    typedef logic [$clog2(NUM_AFU_INTERRUPTS)-1 : 0] t_interrupt_idx;

    // Tags, reduced from the TLP's maximum size to the FIM-enforced maximum
    typedef logic [$clog2(MAX_OUTSTANDING_DMA_RD_REQS)-1 : 0] t_dma_rd_tag;
    typedef logic [$clog2(MAX_OUTSTANDING_MMIO_RD_REQS)-1 : 0] t_mmio_rd_tag;

    // Maximum packet size (bits)
    localparam MAX_PAYLOAD_SIZE = 2048;
    localparam PAYLOAD_LINE_SIZE = ofs_plat_host_chan_@group@_pkg::DATA_WIDTH;
    // Maximum number of lines in a packet
    localparam MAX_PAYLOAD_LINES = MAX_PAYLOAD_SIZE / PAYLOAD_LINE_SIZE;
    // Line count -- number of lines -- must represent 0 .. MAX_PAYLOAD_LINES
    typedef logic [$clog2(MAX_PAYLOAD_LINES+1)-1 : 0] t_tlp_payload_line_count;
    // Line index -- line offset from 0 -- must represent 0 .. MAX_PAYLOAD_LINES-1
    typedef logic [$clog2(MAX_PAYLOAD_LINES)-1 : 0] t_tlp_payload_line_idx;

    localparam PAYLOAD_LINE_BYTES = PAYLOAD_LINE_SIZE / 8;
    typedef logic [$clog2(PAYLOAD_LINE_BYTES)-1 : 0] t_tlp_payload_line_byte_idx;

    localparam int MAX_BW_ACTIVE_RD_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_RD /
                      ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_FIM_PCIE_TLP_CH;
    localparam int MAX_BW_ACTIVE_WR_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_WR /
                      ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_FIM_PCIE_TLP_CH;


    // Isolate just the line index portion of a byte-level address
    function automatic t_tlp_payload_line_idx byteAddrToPayloadLineIdx(logic [63:0] addr);
        return addr[$clog2(PAYLOAD_LINE_SIZE) +: $bits(t_tlp_payload_line_idx)];
    endfunction

    function automatic logic [9:0] lineCountToDwordLen(t_tlp_payload_line_count cnt);
        return (10'(cnt) << $clog2(PAYLOAD_LINE_SIZE / 32));
    endfunction

    function automatic t_tlp_payload_line_count dwordLenToLineCount(logic [9:0] dwords);
        return t_tlp_payload_line_count'(dwords >> $clog2(PAYLOAD_LINE_SIZE / 32));
    endfunction


    // ====================================================================
    //
    //  PIM-internal PCIe data and header types
    //
    // ====================================================================

    // TLP payload is just raw data. Headers are stored in tuser. By storing headers
    // out of band, the PIM can easily manage data equal to the width of the
    // internal PCIe data bus. Moving the TLP header in-band, if needed by the
    // FIM, is the job of a FIM-specific gasket.
    typedef logic [(PAYLOAD_LINE_SIZE / NUM_PIM_PCIE_TLP_CH) - 1 : 0] t_ofs_plat_axis_pcie_tdata;

    typedef t_ofs_plat_axis_pcie_tdata [NUM_PIM_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_tdata_vec;

    // Header and metadata
    typedef struct packed
    {
        t_ofs_plat_pcie_hdr hdr;
        logic eop;
        logic sop;

        // Poison bit may be used to allow a message to flow through part
        // of the pipeline but squash it before reaching either the AFU or FIM.
        // E.g., memory fences requested when there has been no previous write.
        logic poison;
    }
    t_ofs_plat_axis_pcie_tuser;

    typedef t_ofs_plat_axis_pcie_tuser [NUM_PIM_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_tuser_vec;


    // Is EOP set in the vector?
    function automatic logic ofs_plat_pcie_func_is_eop(t_ofs_plat_axis_pcie_tuser_vec user);
        logic is_eop = user[0].eop;

        for (int i = 1; i < NUM_PIM_PCIE_TLP_CH; i = i + 1)
        begin
            is_eop = is_eop || user[i].eop;
        end

        return is_eop;
    endfunction // ofs_plat_pcie_func_eop_is_set


    // ====================================================================
    //
    //  Debugging
    //
    // ====================================================================

    // synthesis translate_off

    function automatic string ofs_plat_pcie_payload_to_string(
        input t_ofs_plat_axis_pcie_tuser tuser,
        input t_ofs_plat_axis_pcie_tdata tdata
        );
        if (tuser.sop && !ofs_plat_pcie_func_has_data(tuser.hdr.fmttype)) return "";

        return $sformatf(" data 0x%x", tdata);
    endfunction

    // Standard formatting of the contents of a channel
    function automatic string ofs_plat_pcie_func_fmt_hdr(
        input t_ofs_plat_axis_pcie_tuser tuser
        );

        string s;

        if (tuser.sop)
        begin
            s = $sformatf("sop %s %s",
                          (tuser.eop ? "eop" : "   "),
                          ofs_plat_pcie_func_hdr_to_string(tuser.hdr));
        end
        else
        begin
            s = $sformatf("    %s        ", (tuser.eop ? "eop" : "   "));
        end

        return s;
    endfunction

    task ofs_plat_pcie_log_tlp(
        input int log_fd,
        input string log_class_name,
        input string ctx_name,
        input int unsigned instance_number,
        t_ofs_plat_axis_pcie_tdata_vec tdata,
        t_ofs_plat_axis_pcie_tuser_vec tuser
        );

        for (int i = 0; i < NUM_PIM_PCIE_TLP_CH; i = i + 1)
        begin
            $fwrite(log_fd, "%s: %t %s %0d ch%0d %s%s%s\n",
                    ctx_name, $time,
                    log_class_name,
                    instance_number, i,
                    ofs_plat_pcie_func_fmt_hdr(tuser[i]),
                    (tuser[i].poison ? " POISON " : ""),
                    ofs_plat_pcie_payload_to_string(tuser[i], tdata[i]));
            $fflush(log_fd);
        end
    endtask // ofs_plat_pcie_log_tlp

    // synthesis translate_on

endpackage // ofs_plat_host_chan_@group@_pcie_tlp_pkg
