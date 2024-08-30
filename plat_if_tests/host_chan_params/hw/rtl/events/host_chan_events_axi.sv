// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
    input  logic [ofs_plat_host_chan_fim_gasket_pkg::TDATA_WIDTH-1 : 0] tx_data,
    input  logic tx_tlast,

    input  logic en_tx_b,
    input  logic [ofs_plat_host_chan_fim_gasket_pkg::TDATA_WIDTH-1 : 0] tx_b_data,
    input  logic tx_b_tlast,

    input  logic en_rx,
    input  logic [ofs_plat_host_chan_fim_gasket_pkg::TDATA_WIDTH-1 : 0] rx_data,
    input  logic rx_tlast,

    // Send counted events to a specific traffic generator engine
    host_chan_events_if.monitor events
    );

    //
    // Track new requests and responses
    //
    typedef logic [13:0] t_dword_count;
    t_dword_count rd_n_dwords_req, b_pipe_rd_n_dwords_req, rd_n_dwords_req_q;
    t_dword_count rd_n_dwords_rsp, rd_n_dwords_rsp_q;

    // Map segments within the TLP data vector as request and completion headers.
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t tx_hdr;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t tx_b_hdr;
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t rx_hdr;
    always_comb
    begin
        tx_hdr = pcie_ss_hdr_pkg::PCIe_PUReqHdr_t'(tx_data);
        tx_b_hdr = pcie_ss_hdr_pkg::PCIe_PUReqHdr_t'(tx_b_data);
        rx_hdr = pcie_ss_hdr_pkg::PCIe_PUCplHdr_t'(rx_data);
    end

    logic tx_sop, tx_b_sop, rx_sop;
    always_ff @(posedge clk)
    begin
        if (en_tx)
            tx_sop <= tx_tlast;
        if (en_tx_b)
            tx_b_sop <= tx_b_tlast;
        if (en_rx)
            rx_sop <= rx_tlast;

        if (!reset_n)
        begin
            tx_sop <= 1'b1;
            tx_b_sop <= 1'b1;
            rx_sop <= 1'b1;
        end
    end

    // Count requested reads, allowing a read request at the start of any segment.
    always_comb
    begin
        rd_n_dwords_req = '0;
        if (en_tx)
        begin
            if (tx_sop && pcie_ss_hdr_pkg::func_is_mrd_req(tx_hdr.fmt_type))
                rd_n_dwords_req = tx_hdr.length;
        end

        b_pipe_rd_n_dwords_req = '0;
        if (en_tx_b)
        begin
            if (tx_b_sop && pcie_ss_hdr_pkg::func_is_mrd_req(tx_b_hdr.fmt_type))
                b_pipe_rd_n_dwords_req = tx_b_hdr.length;
        end
    end

    // Count read completions, allowing a completion at the start of any segment.
    always_comb
    begin
        rd_n_dwords_rsp = '0;
        if (en_rx)
        begin
            if (rx_sop &&
                pcie_ss_hdr_pkg::func_is_completion(rx_hdr.fmt_type) &&
                pcie_ss_hdr_pkg::func_has_data(rx_hdr.fmt_type))
            begin
                rd_n_dwords_rsp = rx_hdr.length;
            end
        end
    end

    always_ff @(posedge clk)
    begin
        rd_n_dwords_req_q <= rd_n_dwords_req + b_pipe_rd_n_dwords_req;
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

        .rdClk(clk),
        .rdReqCnt(rd_n_dwords_req_q),
        .rdRespCnt(rd_n_dwords_rsp_q),

        .events
        );

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
    typedef logic [13:0] t_dword_count;
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

        .rdClk(clk),
        .rdReqCnt(rd_n_dwords_req_q),
        .rdRespCnt(rd_n_dwords_rsp_q),

        .events
        );

endmodule // host_chan_events_axi

`endif //  `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_EA_OFS_FIM

`endif //  `ifdef OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_AXIS_PCIE_TLP
