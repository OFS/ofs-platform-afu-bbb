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
// This gasket maps the PIM's internal PCIe TLP representation to the OFS EA
// FIM. Each supported flavor of FIM has a gasket.
//
// Each gasket implementation provides some common parameters and types
// that will be consumed by the platform-independent PIM TLP mapping code.
// The gasket often sets these parameters by importing values from the
// FIM.
//

`include "ofs_plat_if.vh"

package ofs_plat_host_chan_@group@_fim_gasket_pkg;

    // Largest tag value allowed for AFU->host requests
    localparam MAX_OUTSTANDING_DMA_RD_REQS = ofs_fim_pcie_pkg::PCIE_EP_MAX_TAGS;
    // Largest tag value permitted in the FIM configuration for host->AFU MMIO reads
    localparam MAX_OUTSTANDING_MMIO_RD_REQS = ofs_fim_cfg_pkg::PCIE_RP_MAX_TAGS;

    // Maximum read request bits (AFU reading host memory)
    localparam MAX_RD_REQ_SIZE = ofs_fim_cfg_pkg::MAX_RD_REQ_SIZE * 32;
    // Maximum write payload bits (AFU writing host memory)
    localparam MAX_WR_PAYLOAD_SIZE = ofs_fim_cfg_pkg::MAX_PAYLOAD_SIZE * 32;

    // Number of interrupt vectors supported
    localparam NUM_AFU_INTERRUPTS = ofs_fim_cfg_pkg::NUM_AFU_INTERRUPTS;

    // Number of channels in the FIM TLP interface
    localparam NUM_FIM_PCIE_TLP_CH = ofs_fim_if_pkg::FIM_PCIE_TLP_CH;

    // The EA FIM does not reorder completions
    localparam CPL_REORDER_EN = 0;

    typedef enum bit[0:0] {
        PCIE_CHAN_A,
        PCIE_CHAN_B
    } e_pcie_chan;

    // On which TLP channel are completions returned?
    localparam e_pcie_chan CPL_CHAN = PCIE_CHAN_A;
    // On which TLP channel are FIM-generated write commits returned?
    localparam e_pcie_chan WR_COMMIT_CHAN = PCIE_CHAN_B;

    // Data types in the FIM's AXI streams
    typedef ofs_fim_if_pkg::t_axis_pcie_tdata [NUM_FIM_PCIE_TLP_CH-1:0] t_ofs_fim_axis_pcie_tdata_vec;
    typedef ofs_fim_if_pkg::t_axis_pcie_tx_tuser [NUM_FIM_PCIE_TLP_CH-1:0] t_ofs_fim_axis_pcie_tx_tuser_vec;
    typedef ofs_fim_if_pkg::t_axis_pcie_rx_tuser [NUM_FIM_PCIE_TLP_CH-1:0] t_ofs_fim_axis_pcie_rx_tuser_vec;
    typedef ofs_fim_if_pkg::t_axis_irq_tdata t_ofs_fim_axis_pcie_irq_tdata;

    // The OFS EA interface breaks down the PCIe stream into multiple parallel
    // channels. (These became "segments" in the later PCIe subsystem naming.)
    // The PIM's OFS EA .ini gives the bandwidth hint in flits, where there
    // may be up to two flits per beat. The PIM calls a "line" the width of
    // the PCIe stream's data bus.
    localparam int MAX_BW_ACTIVE_RD_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_RD /
                      ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_FIM_PCIE_TLP_CH;
    localparam int MAX_BW_ACTIVE_WR_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_WR /
                      ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_FIM_PCIE_TLP_CH;

    // synthesis translate_off

    //
    // Debugging functions
    //

    function automatic string ofs_fim_gasket_pcie_payload_to_string(
        input ofs_fim_if_pkg::t_axis_pcie_tdata tdata
        );
        // Pick any header type to extract dw0 and the fmttype
        ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr hdr = tdata.hdr;

        if (!ofs_fim_pcie_hdr_def::func_has_data(hdr.dw0.fmttype)) return "";

        return $sformatf(" data 0x%x", tdata.payload);
    endfunction

    task ofs_fim_gasket_log_pcie_tx_st(
        input int log_fd,
        input string log_class_name,
        input string ctx_name,
        input int unsigned instance_number,
        t_ofs_fim_axis_pcie_tdata_vec data,
        t_ofs_fim_axis_pcie_tx_tuser_vec user
        );

        for (int i = 0; i < NUM_FIM_PCIE_TLP_CH; i = i + 1)
        begin
            if (data[i].valid)
            begin
                if (data[i].sop)
                begin
                    if (!user[i].afu_irq)
                    begin
                        $fwrite(log_fd, "%s: %t %s %0d ch%0d %s %s %s [%s]%s\n",
                                ctx_name, $time,
                                log_class_name,
                                instance_number, i,
                                (data[i].sop ? "sop" : "   "),
                                (data[i].eop ? "eop" : "   "),
                                ofs_fim_pcie_hdr_def::func_hdr_to_string(data[i].hdr),
                                ofs_fim_if_pkg::func_tx_user_to_string(user[i]),
                                ofs_fim_gasket_pcie_payload_to_string(data[i]));
                    end
                    else
                    begin
                        t_ofs_fim_axis_pcie_irq_tdata irq_hdr;
                        irq_hdr = t_ofs_fim_axis_pcie_irq_tdata'(data[i].hdr);
                        $fwrite(log_fd, "%s: %t %s %0d ch%0d %s %s irq_id %0d\n",
                                ctx_name, $time,
                                log_class_name,
                                instance_number, i,
                                (data[i].sop ? "sop" : "   "),
                                (data[i].eop ? "eop" : "   "),
                                irq_hdr.irq_id);
                    end
                end
                else
                begin
                    $fwrite(log_fd, "%s: %t %s %0d ch%0d     %s data 0x%x\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, i,
                            (data[i].eop ? "eop" : "   "),
                            data[i].payload);
                end
                $fflush(log_fd);
            end
        end

    endtask // ofs_fim_gasket_log_pcie_tx_st

    task ofs_fim_gasket_log_pcie_rx_st(
        input int log_fd,
        input string log_class_name,
        input string ctx_name,
        input int unsigned instance_number,
        t_ofs_fim_axis_pcie_tdata_vec data,
        t_ofs_fim_axis_pcie_rx_tuser_vec user
        );

        for (int i = 0; i < NUM_FIM_PCIE_TLP_CH; i = i + 1)
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
                            ofs_fim_gasket_pcie_payload_to_string(data[i]));
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

    endtask // ofs_fim_gasket_log_pcie_rx_st

    // synthesis translate_on

endpackage // ofs_plat_host_chan_@group@_fim_gasket_pkg
