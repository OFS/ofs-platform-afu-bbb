// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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

    // AFU's tag for a request, returned with responses. PCIe tags are a
    // separate space, assigned internally in the modules here. The AFU tag width
    // just has to be large enough to return whatever tags might reach this code.
    // The maximum tag size reaching here is typically governed by other code inside
    // the PIM, such as reorder buffers, clock crossings, etc.
    localparam AFU_TAG_WIDTH = 16;
    typedef logic [AFU_TAG_WIDTH-1:0] t_dma_afu_tag;

    localparam NUM_AFU_INTERRUPTS =
        ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_AFU_INTERRUPTS;
    typedef logic [$clog2(NUM_AFU_INTERRUPTS)-1 : 0] t_interrupt_idx;

    // Does the platform support PCIe atomics? The way this is computed isn't
    // ideal and should be improved. For now, we know that atomics don't work
    // on S10 and assume the PCIe SS supports them everywhere else.
    localparam ATOMICS_SUPPORTED =
`ifdef PLATFORM_FPGA_FAMILY_S10
        0;
`else
        1;
`endif

    // Tags, reduced from the TLP's maximum size to the FIM-enforced maximum
    typedef logic [$clog2(MAX_OUTSTANDING_DMA_RD_REQS)-1 : 0] t_dma_rd_tag;
    typedef logic [$clog2(MAX_OUTSTANDING_MMIO_RD_REQS)-1 : 0] t_mmio_rd_tag;

    // Maximum packet size (bits). Read and write requests are forced to the same
    // maximum to simplify fairness during arbitration.
    localparam MAX_PAYLOAD_SIZE =
        ((ofs_plat_host_chan_@group@_fim_gasket_pkg::MAX_RD_REQ_SIZE <
          ofs_plat_host_chan_@group@_fim_gasket_pkg::MAX_WR_PAYLOAD_SIZE) ?
            ofs_plat_host_chan_@group@_fim_gasket_pkg::MAX_RD_REQ_SIZE :
            ofs_plat_host_chan_@group@_fim_gasket_pkg::MAX_WR_PAYLOAD_SIZE);

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
        ofs_plat_host_chan_@group@_fim_gasket_pkg::MAX_BW_ACTIVE_RD_LINES;
    localparam int MAX_BW_ACTIVE_WR_LINES =
        ofs_plat_host_chan_@group@_fim_gasket_pkg::MAX_BW_ACTIVE_WR_LINES;


    // Isolate just the line index portion of a byte-level address
    function automatic t_tlp_payload_line_idx byteAddrToPayloadLineIdx(logic [63:0] addr);
        return addr[$clog2(PAYLOAD_LINE_SIZE) +: $bits(t_tlp_payload_line_idx)];
    endfunction

    function automatic logic [9:0] lineCountToDwordLen(t_tlp_payload_line_count cnt);
        return (10'(cnt) << $clog2(PAYLOAD_LINE_SIZE / 32));
    endfunction

    function automatic t_tlp_payload_line_count dwordLenToLineCount(logic [9:0] dwords);
        // Round up to multiples of lines
        logic [10:0] d = { 1'b0, dwords };
        d = d + ((PAYLOAD_LINE_SIZE / 32) - 1);
        return t_tlp_payload_line_count'(d >> $clog2(PAYLOAD_LINE_SIZE / 32));
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
    typedef logic [(PAYLOAD_LINE_SIZE / NUM_PIM_PCIE_TLP_CH)/8 - 1 : 0] t_ofs_plat_axis_pcie_tkeep;

    typedef t_ofs_plat_axis_pcie_tdata [NUM_PIM_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_tdata_vec;

    typedef t_ofs_plat_axis_pcie_tkeep [NUM_PIM_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_tkeep_vec;

    // Header and metadata
    typedef struct packed
    {
        t_ofs_plat_pcie_hdr hdr;
        logic eop;
        logic sop;

        // Some TLP headers need the full AFU tag to be passed. The AFU tag
        // is too large for the TLP header, but may be used for some local action.
        // On the PCIe SS, it may be used for recording the commit points of
        // DMA writes inside the FIM.
        t_dma_afu_tag afu_tag;

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
        input t_ofs_plat_axis_pcie_tdata tdata,
        input t_ofs_plat_axis_pcie_tkeep tkeep
        );
        if (tuser.sop && !ofs_plat_pcie_func_has_data(tuser.hdr.fmttype)) return "";

        return $sformatf(" keep 0x%x data 0x%x", tkeep, tdata);
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
        t_ofs_plat_axis_pcie_tuser_vec tuser,
        t_ofs_plat_axis_pcie_tkeep_vec tkeep
        );

        for (int i = 0; i < NUM_PIM_PCIE_TLP_CH; i = i + 1)
        begin
            $fwrite(log_fd, "%s: %t %s %0d ch%0d %s%s%s\n",
                    ctx_name, $time,
                    log_class_name,
                    instance_number, i,
                    ofs_plat_pcie_func_fmt_hdr(tuser[i]),
                    (tuser[i].poison ? " POISON " : ""),
                    ofs_plat_pcie_payload_to_string(tuser[i], tdata[i], tkeep[i]));
            $fflush(log_fd);
        end
    endtask // ofs_plat_pcie_log_tlp

    // synthesis translate_on

endpackage // ofs_plat_host_chan_@group@_pcie_tlp_pkg
