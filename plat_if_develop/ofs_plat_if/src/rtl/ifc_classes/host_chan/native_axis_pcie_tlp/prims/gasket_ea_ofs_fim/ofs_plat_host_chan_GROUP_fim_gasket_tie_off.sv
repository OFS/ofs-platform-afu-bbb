// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Tie off an OFS EA FIM PCIe interface.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fim_gasket_tie_off
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if port
    );

    import ofs_plat_host_chan_@group@_fim_gasket_pkg::*;

    //
    // Consume FIM -> AFU RX stream in a skid buffer for timing
    //
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata_vec),
        .TUSER_TYPE(t_ofs_fim_axis_pcie_rx_tuser_vec)
        )
      rx_st();

    ofs_plat_axi_stream_if_skid_source_clk rx_skid
       (
        .stream_source(port.afu_rx_st),
        .stream_sink(rx_st)
        );

    //
    // MMIO read responses (AFU -> FIM) also flow through a skid buffer
    //
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata_vec),
        .TUSER_TYPE(t_ofs_fim_axis_pcie_tx_tuser_vec)
        )
      tx_st();

    ofs_plat_axi_stream_if_skid_sink_clk tx_skid
       (
        .stream_source(tx_st),
        .stream_sink(port.afu_tx_st)
        );


    logic clk;
    assign clk = rx_st.clk;
    logic reset_n;
    assign reset_n = rx_st.reset_n;


    //
    // Watch for MMIO read requests on the RX stream.
    //

    // Register requests from incoming RX stream
    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr rx_mem_req_hdr;
    logic rx_mem_req_valid;

    assign rx_st.tready = !rx_mem_req_valid;

    // Incoming MMIO read?
    always_ff @(posedge clk)
    begin
        if (rx_st.tready)
        begin
            rx_mem_req_valid <= 1'b0;

            // An MMIO request may be present on any input channel. At most one channel
            // will have a request.
            for (int c = 0; c < NUM_FIM_PCIE_TLP_CH; c = c + 1)
            begin
                if (rx_st.tvalid && rx_st.t.data[c].valid &&
                    rx_st.t.data[c].sop && rx_st.t.data[c].eop)
                begin
                    rx_mem_req_hdr <= ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr'(rx_st.t.data[c].hdr);
                    rx_mem_req_valid <= 1'b1;
                    break;
                end
            end
        end
        else if (tx_st.tready)
        begin
            // If a request was present, it was consumed
            rx_mem_req_valid <= 1'b0;
        end

        if (!reset_n)
        begin
            rx_mem_req_valid <= 1'b0;
        end
    end

    // Construct MMIO completion in response to RX read request
    ofs_fim_pcie_hdr_def::t_tlp_cpl_hdr tx_cpl_hdr;

    always_comb
    begin
        // Build the header -- always the same for any address
        tx_cpl_hdr = '0;
        tx_cpl_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_CPLD;
        tx_cpl_hdr.dw0.length = rx_mem_req_hdr.dw0.length;
        tx_cpl_hdr.requester_id = rx_mem_req_hdr.requester_id;
        tx_cpl_hdr.tag = rx_mem_req_hdr.tag;
        tx_cpl_hdr.byte_count = rx_mem_req_hdr.dw0.length << 2;
        tx_cpl_hdr.lower_addr[6:2] =
            ofs_fim_pcie_hdr_def::func_is_addr64(rx_mem_req_hdr.dw0.fmttype) ?
                rx_mem_req_hdr.lsb_addr[6:2] : rx_mem_req_hdr.addr[6:2];
    end

    always_comb
    begin
        tx_st.tvalid = rx_mem_req_valid &&
                       ofs_fim_pcie_hdr_def::func_is_mrd_req(rx_mem_req_hdr.dw0.fmttype);
        tx_st.t = '0;
        tx_st.t.data[0].valid = tx_st.tvalid;
        tx_st.t.data[0].hdr = tx_cpl_hdr;
        tx_st.t.data[0].sop = tx_st.tvalid;
        tx_st.t.data[0].eop =
            tx_st.tvalid &&
            (rx_mem_req_hdr.dw0.length <= (ofs_fim_if_pkg::AXIS_PCIE_PW / 32));
        tx_st.t.data[1].eop =
            tx_st.tvalid &&
            (rx_mem_req_hdr.dw0.length > (ofs_fim_if_pkg::AXIS_PCIE_PW / 32));

        // Completion data. There is minimal address decoding here to keep
        // it simple. Location 0 needs a device feature header and an AFU
        // ID is set.
        case (tx_cpl_hdr.lower_addr[6:3])
            // AFU DFH
            4'h0:
                begin
                    tx_st.t.data[0].payload[63:0] = '0;
                    // Feature type is AFU
                    tx_st.t.data[0].payload[63:60] = 4'h1;
                    // End of list
                    tx_st.t.data[0].payload[40] = 1'b1;
                end

            // AFU_ID_H
            4'h2: tx_st.t.data[0].payload[63:0] = 64'hd15ab1ed00000000;

            default: tx_st.t.data[0].payload[63:0] = '0;
        endcase

        // Was the request short, asking for the high 32 bits of the 64 bit register?
        if (tx_cpl_hdr.lower_addr[2])
        begin
            tx_st.t.data[0].payload[31:0] = tx_st.t.data[0].payload[63:32];
        end
    end


    // Permit all interrupt responses (there will be none)
    assign port.afu_irq_rx_st.tready = 1'b1;

endmodule // ofs_plat_host_chan_@group@_fim_gasket_tie_off
