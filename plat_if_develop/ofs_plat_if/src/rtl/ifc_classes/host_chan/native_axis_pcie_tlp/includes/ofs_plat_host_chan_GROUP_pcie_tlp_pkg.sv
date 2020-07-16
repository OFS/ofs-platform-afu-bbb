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

`include "ofs_plat_if.vh"

package ofs_plat_host_chan_@group@_pcie_tlp_pkg;

    // Number of parallel TLP channels in the interface
    localparam NUM_FIU_PCIE_TLP_CH = ofs_fim_if_pkg::FIM_PCIE_TLP_CH;

    // Payload width of a single FIM channel
    localparam FIU_PCIE_TLP_CH_PW = ofs_fim_if_pkg::AXIS_PCIE_PW;

    // Tag values must be less than the maximum number of tags
    localparam MAX_OUTSTANDING_DMA_RD_REQS = ofs_fim_pcie_pkg::PCIE_EP_MAX_TAGS;
    localparam MAX_OUTSTANDING_MMIO_RD_REQS = ofs_fim_cfg_pkg::PCIE_RP_MAX_TAGS;
    // Number of tags to reserve for write fences. Tags 0 through
    // MAX_OUTSTANDING_DMA_WR_FENCES will never be used for normal reads.
    localparam MAX_OUTSTANDING_DMA_WR_FENCES = 4;

    localparam NUM_AFU_INTERRUPTS = ofs_fim_cfg_pkg::NUM_AFU_INTERRUPTS;

    // Tags, reduced from the TLP's 8 bits to the FIM-enforced maximum
    typedef logic [$clog2(MAX_OUTSTANDING_DMA_RD_REQS)-1 : 0] t_dma_rd_tag;
    typedef logic [$clog2(MAX_OUTSTANDING_MMIO_RD_REQS)-1 : 0] t_mmio_rd_tag;

    // TLP header and payload (both TX and RX)
    typedef ofs_fim_if_pkg::t_axis_pcie_tdata t_ofs_plat_axis_pcie_tdata;
    typedef t_ofs_plat_axis_pcie_tdata [NUM_FIU_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_tdata_vec;

    // User meta-data for TX stream (AFU -> FIU)
    typedef ofs_fim_if_pkg::t_axis_pcie_tx_tuser t_ofs_plat_axis_pcie_tx_tuser;
    typedef t_ofs_plat_axis_pcie_tx_tuser [NUM_FIU_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_tx_tuser_vec;

    // User meta-data for RX stream (FIU -> AFU)
    typedef ofs_fim_if_pkg::t_axis_pcie_rx_tuser t_ofs_plat_axis_pcie_rx_tuser;
    typedef t_ofs_plat_axis_pcie_rx_tuser [NUM_FIU_PCIE_TLP_CH-1:0]
        t_ofs_plat_axis_pcie_rx_tuser_vec;

    // Interrupt request response stream (FIU -> AFU)
    typedef ofs_fim_if_pkg::t_axis_irq_tdata
        t_ofs_plat_axis_pcie_irq_data;

    // Maximum packet size (bits)
    localparam MAX_PAYLOAD_SIZE = 2048;
    // Maximum number of 512 bit lines in a packet
    localparam PAYLOAD_LINE_SIZE = 512;
    localparam MAX_PAYLOAD_LINES = MAX_PAYLOAD_SIZE / PAYLOAD_LINE_SIZE;
    // Line count -- number of lines -- must represent 0 .. MAX_PAYLOAD_LINES
    typedef logic [$clog2(MAX_PAYLOAD_LINES+1)-1 : 0] t_tlp_payload_line_count;
    // Line index -- line offset from 0 -- must represent 0 .. MAX_PAYLOAD_LINES-1
    typedef logic [$clog2(MAX_PAYLOAD_LINES)-1 : 0] t_tlp_payload_line_idx;

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


    // synthesis translate_off

    function automatic string pcie_payload_to_string(
        input t_ofs_plat_axis_pcie_tdata tdata
        );
        // Pick any header type to extract dw0 and the fmttype
        ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr hdr = tdata.hdr;

        if (!ofs_fim_pcie_hdr_def::func_has_data(hdr.dw0.fmttype)) return "";

        return $sformatf(" data 0x%x", tdata.payload);
    endfunction

    task log_afu_tx_st(
        input int log_fd,
        input string log_class_name,
        input string ctx_name,
        input int unsigned instance_number,
        t_ofs_plat_axis_pcie_tdata_vec data,
        t_ofs_plat_axis_pcie_tx_tuser_vec user
        );

        for (int i = 0; i < NUM_FIU_PCIE_TLP_CH; i = i + 1)
        begin
            if (data[i].valid)
            begin
                if (data[i].sop)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d ch%0d %s%s%s [%s]%s\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, i,
                            (data[i].sop ? "sop " : ""),
                            (data[i].eop ? "eop " : ""),
                            ofs_fim_pcie_hdr_def::func_hdr_to_string(data[i].hdr),
                            ofs_fim_if_pkg::func_tx_user_to_string(user[i]),
                            pcie_payload_to_string(data[i]));
                end
                else
                begin
                    $fwrite(log_fd, "%s: %t %s %0d ch%0d %sdata 0x%x\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, i,
                            (data[i].eop ? "eop " : ""),
                            data[i].payload);
                end
                $fflush(log_fd);
            end
        end

    endtask // log_afu_tx_st

    task log_afu_rx_st(
        input int log_fd,
        input string log_class_name,
        input string ctx_name,
        input int unsigned instance_number,
        t_ofs_plat_axis_pcie_tdata_vec data,
        t_ofs_plat_axis_pcie_rx_tuser_vec user
        );

        for (int i = 0; i < NUM_FIU_PCIE_TLP_CH; i = i + 1)
        begin
            if (data[i].valid)
            begin
                if (data[i].sop)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d ch%0d %s%s%s [%s]%s\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, i,
                            (data[i].sop ? "sop " : ""),
                            (data[i].eop ? "eop " : ""),
                            ofs_fim_pcie_hdr_def::func_hdr_to_string(data[i].hdr),
                            ofs_fim_if_pkg::func_rx_user_to_string(user[i]),
                            pcie_payload_to_string(data[i]));
                end
                else
                begin
                    $fwrite(log_fd, "%s: %t %s %0d ch%0d %sdata 0x%x\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, i,
                            (data[i].eop ? "eop " : ""),
                            data[i].payload);
                end
                $fflush(log_fd);
            end
        end

    endtask // log_afu_rx_st

    // synthesis translate_on

endpackage // ofs_plat_host_chan_@group@_pcie_tlp_pkg
