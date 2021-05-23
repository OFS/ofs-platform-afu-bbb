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
// Host channel event tracker for native PCIe TLP AXI stream. There are
// multiple implementations here, for different FIM variants, chosen by
// preprocessor macros.
//

`include "ofs_plat_if.vh"

`ifdef OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_AXIS_PCIE_TLP

// OFS PCIe subsystem interface
`ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS

module host_chan_events_axi
   (
    input  logic clk,
    input  logic reset_n,

    // Track TLP traffic (in domain clk)
    input  logic en_tx,
    input  ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata tx_data,
    input  ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser tx_user,
    input  logic en_rx,
    input  ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata rx_data,
    input  ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser rx_user,

    // Send counted events to a specific traffic generator engine
    host_chan_events_if.monitor events
    );

    import ofs_plat_host_chan_fim_gasket_pkg::*;

    // Not implemented yet
    assign events.notEmpty = 1'b0;
    assign events.eng_clk_cycle_count = '0;
    assign events.fim_clk_cycle_count = '0;
    assign events.num_rd_reqs = '0;
    assign events.active_rd_req_sum = '0;

endmodule // host_chan_events_axi

`endif //  `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS


// OFS Early Access FIM interface
`ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_EA_OFS_FIM

module host_chan_events_axi
   (
    input  logic clk,
    input  logic reset_n,

    // Track TLP traffic (in domain clk)
    input  logic en_tx,
    input  ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata_vec tx_data,
    input  ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tx_tuser_vec tx_user,
    input  logic en_rx,
    input  ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata_vec rx_data,
    input  ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_rx_tuser_vec rx_user,

    // Send counted events to a specific traffic generator engine
    host_chan_events_if.monitor events
    );

    import ofs_plat_host_chan_fim_gasket_pkg::*;

    //
    // Track new requests and responses
    //
    typedef logic [12:0] t_dword_count;
    t_dword_count rd_n_dwords_req, rd_n_dwords_req_q;
    t_dword_count rd_n_dwords_rsp, rd_n_dwords_rsp_q;

    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr tx_hdrs[NUM_FIM_PCIE_TLP_CH];
    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr rx_hdrs[NUM_FIM_PCIE_TLP_CH];
    always_comb
    begin
        for (int c = 0; c < NUM_FIM_PCIE_TLP_CH; c = c + 1)
        begin
            tx_hdrs[c] = tx_data[c].hdr;
            rx_hdrs[c] = rx_data[c].hdr;
        end
    end

    always_comb
    begin
        rd_n_dwords_req = '0;
        if (en_tx)
        begin
            for (int c = 0; c < NUM_FIM_PCIE_TLP_CH; c = c + 1)
            begin
                if (tx_data[c].valid && tx_data[c].sop && !tx_user[c].afu_irq &&
                    ofs_fim_pcie_hdr_def::func_is_mrd_req(tx_hdrs[c].dw0.fmttype))
                begin
                    rd_n_dwords_req = rd_n_dwords_req + tx_hdrs[c].dw0.length;
                end
            end
        end
    end

    always_comb
    begin
        rd_n_dwords_rsp = '0;
        if (en_rx)
        begin
            for (int c = 0; c < NUM_FIM_PCIE_TLP_CH; c = c + 1)
            begin
                if (rx_data[c].valid && rx_data[c].sop &&
                    ofs_fim_pcie_hdr_def::func_is_completion(rx_hdrs[c].dw0.fmttype) &&
                    ofs_fim_pcie_hdr_def::func_has_data(rx_hdrs[c].dw0.fmttype))
                begin
                    rd_n_dwords_rsp = rd_n_dwords_rsp + rx_hdrs[c].dw0.length;
                end
            end
        end
    end

    always_ff @(posedge clk)
    begin
        rd_n_dwords_req_q <= rd_n_dwords_req;
        rd_n_dwords_rsp_q <= rd_n_dwords_rsp;
    end


    //
    // Manage events
    //
    host_chan_events_common
      #(
        .READ_CNT_WIDTH($bits(t_dword_count)),
        .UNIT_IS_DWORDS(1)
        )
      hc_evt
       (
        .clk,
        .reset_n,

        .rdReqCnt(rd_n_dwords_req_q),
        .rdRespCnt(rd_n_dwords_rsp_q),

        .events
        );

endmodule // host_chan_events_axi

`endif //  `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_EA_OFS_FIM

`endif //  `ifdef OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_AXIS_PCIE_TLP
