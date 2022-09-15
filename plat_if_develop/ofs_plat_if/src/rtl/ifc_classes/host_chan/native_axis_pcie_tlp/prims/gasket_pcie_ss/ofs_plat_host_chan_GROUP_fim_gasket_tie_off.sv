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
// Tie off an OFS EA FIM PCIe interface.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fim_gasket_tie_off
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if port
    );

    //
    // Pick the appropriate tie off, either MMIO on AXI-Lite or on the TLP stream.
    //
    generate
        if (ofs_plat_host_chan_@group@_pcie_tlp_pkg::MMIO_ON_AXI_L_FROM_FIM)
        begin : mmio_axi
            ofs_plat_host_chan_@group@_fim_gasket_tie_off_axi tieoff
               (
                .port
                );
        end
        else
        begin : mmio_tlp
            ofs_plat_host_chan_@group@_fim_gasket_tie_off_tlp tieoff
               (
                .port
                );
        end
    endgenerate

endmodule // ofs_plat_host_chan_@group@_fim_gasket_tie_off


//
// Tie off implementation when CSRs are on AXI-Lite. This version is trivial.
//
module ofs_plat_host_chan_@group@_fim_gasket_tie_off_axi
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if port
    );

    wire csr_clk = port.afu_csr_if.clk;
    wire csr_reset_n = port.afu_csr_if.reset_n;


    // Generate read response.
    logic arvalid;
    logic [6:0] araddr_low;

    assign port.afu_csr_if.arready = !arvalid;
    assign port.afu_csr_if.rvalid = arvalid;

    always_ff @(posedge csr_clk)
    begin
        if (port.afu_csr_if.rvalid && port.afu_csr_if.rready)
        begin
            arvalid <= 1'b0;
        end

        if (port.afu_csr_if.arvalid && port.afu_csr_if.arready)
        begin
            arvalid <= 1'b1;
            araddr_low <= port.afu_csr_if.ar.addr[6:0];
        end

        if (!csr_reset_n)
        begin
            arvalid <= 1'b0;
        end
    end

    // Read response data
    always_comb
    begin
        port.afu_csr_if.r = '0;

        case (araddr_low[6:3])
            // AFU DFH
            4'h0:
                begin
                    port.afu_csr_if.r.data[63:0] = '0;
                    // Feature type is AFU
                    port.afu_csr_if.r.data[63:60] = 4'h1;
                    // End of list
                    port.afu_csr_if.r.data[40] = 1'b1;
                end

            // AFU_ID_L
            4'h1:
                begin
                    port.afu_csr_if.r.data[63:0] = '0;
                    port.afu_csr_if.r.data[63:56] = { '0, port.vf_num };
                    port.afu_csr_if.r.data[52] = port.vf_active;
                    port.afu_csr_if.r.data[51:48] = { '0, port.pf_num };
                end

            // AFU_ID_H
            4'h2: port.afu_csr_if.r.data[63:0] = 64'hd15ab1ed00000000;

            default: port.afu_csr_if.r.data[63:0] = '0;
        endcase
    end


    // Generate write response. Write data is dropped.
    logic awvalid, wvalid;
    assign port.afu_csr_if.awready = !awvalid;
    assign port.afu_csr_if.wready = !wvalid;

    assign port.afu_csr_if.bvalid = awvalid && wvalid;
    assign port.afu_csr_if.b = '0;

    always_ff @(posedge csr_clk)
    begin
        if (port.afu_csr_if.bvalid && port.afu_csr_if.bready)
        begin
            awvalid <= 1'b0;
            wvalid <= 1'b0;
        end

        if (port.afu_csr_if.awvalid && port.afu_csr_if.awready)
        begin
            awvalid <= 1'b1;
        end

        if (port.afu_csr_if.wvalid && port.afu_csr_if.wready)
        begin
            wvalid <= 1'b1;
        end

        if (!csr_reset_n)
        begin
            awvalid <= 1'b0;
            wvalid <= 1'b0;
        end
    end

    // Unused inerfaces
    assign port.afu_rx_a_st.tready = 1'b1;
    assign port.afu_rx_b_st.tready = 1'b1;
    assign port.afu_tx_a_st.tvalid = 1'b0;
    assign port.afu_tx_a_st.t = '0;
    assign port.afu_tx_b_st.tvalid = 1'b0;
    assign port.afu_tx_b_st.t = '0;

endmodule // ofs_plat_host_chan_@group@_fim_gasket_tie_off_tlp


//
// Tie off implementation when CSRs are on the PCIe TLP stream.
//
module ofs_plat_host_chan_@group@_fim_gasket_tie_off_tlp
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if port
    );

    import ofs_plat_host_chan_@group@_fim_gasket_pkg::*;

    //
    // Consume FIM -> AFU RX stream in a skid buffer for timing
    //
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(t_ofs_fim_axis_pcie_tuser)
        )
      rx_st();

    ofs_plat_axi_stream_if_skid_source_clk rx_skid
       (
        .stream_source(port.afu_rx_a_st),
        .stream_sink(rx_st)
        );

    assign port.afu_rx_b_st.tready = 1'b1;


    //
    // MMIO read responses (AFU -> FIM) also flow through a skid buffer
    //
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(t_ofs_fim_axis_pcie_tuser)
        )
      tx_st();

    ofs_plat_axi_stream_if_skid_sink_clk tx_skid
       (
        .stream_source(tx_st),
        .stream_sink(port.afu_tx_a_st)
        );


    logic clk;
    assign clk = rx_st.clk;
    logic reset_n;
    assign reset_n = rx_st.reset_n;

    //
    // Watch for MMIO read requests on the RX stream.
    //

    // synthesis translate_off
    initial
    begin
        // Check that NUM_OF_SOP is 1. The code below will fail if there are
        // multiple MMIO read requests in a cycle.
        assert(ofs_pcie_ss_cfg_pkg::NUM_OF_SOP == 1) else
            $fatal(2, "Only one SOP per cycle is supported in the decoder!");
    end
    // synthesis translate_on

    // Register requests from incoming RX stream
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t rx_hdr;
    logic rx_hdr_valid;

    assign rx_st.tready = !rx_hdr_valid;

    // Incoming MMIO read?
    always_ff @(posedge clk)
    begin
        if (rx_st.tready)
        begin
            rx_hdr_valid <= 1'b0;

            // Assume that there is at most one SOP (checked with assertion above).
            // It may be in any segment though.
            for (int s = 0; s < ofs_pcie_ss_cfg_pkg::NUM_OF_SEG; s = s + 1)
            begin
                // Only power user mode requests are detected
                if (rx_st.tvalid && !rx_st.t.user[s].dm_mode && rx_st.t.user[s].sop)
                begin
                    rx_hdr <= ofs_fim_gasket_pcie_hdr_from_seg(s, rx_st.t.data);
                    rx_hdr_valid <= 1'b1;
                    break;
                end
            end
        end
        else if (tx_st.tready)
        begin
            // If a request was present, it was consumed
            rx_hdr_valid <= 1'b0;
        end

        if (!reset_n)
        begin
            rx_hdr_valid <= 1'b0;
        end
    end

    // Construct MMIO completion in response to RX read request
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t tx_cpl_hdr;
    localparam TX_CPL_HDR_BYTES = $bits(pcie_ss_hdr_pkg::PCIe_PUCplHdr_t) / 8;

    always_comb
    begin
        // Build the header -- always the same for any address
        tx_cpl_hdr = '0;
        tx_cpl_hdr.fmt_type = pcie_ss_hdr_pkg::ReqHdr_FmtType_e'(pcie_ss_hdr_pkg::PCIE_FMTTYPE_CPLD);
        tx_cpl_hdr.length = rx_hdr.length;
        tx_cpl_hdr.req_id = rx_hdr.req_id;
        tx_cpl_hdr.tag_h = rx_hdr.tag_h;
        tx_cpl_hdr.tag_m = rx_hdr.tag_m;
        tx_cpl_hdr.tag_l = rx_hdr.tag_l;
        tx_cpl_hdr.TC = rx_hdr.TC;
        tx_cpl_hdr.byte_count = rx_hdr.length << 2;
        tx_cpl_hdr.low_addr[6:2] =
            pcie_ss_hdr_pkg::func_is_addr64(rx_hdr.fmt_type) ?
                rx_hdr.host_addr_l[4:0] : rx_hdr.host_addr_h[6:2];

        tx_cpl_hdr.comp_id = { port.vf_num, port.vf_active, port.pf_num };
        tx_cpl_hdr.pf_num = port.pf_num;
        tx_cpl_hdr.vf_num = port.vf_num;
        tx_cpl_hdr.vf_active = port.vf_active;
    end

    logic [63:0] cpl_data;

    // Completion data. There is minimal address decoding here to keep
    // it simple. Location 0 needs a device feature header and an AFU
    // ID is set.
    always_comb
    begin
        case (tx_cpl_hdr.low_addr[6:3])
            // AFU DFH
            4'h0:
                begin
                    cpl_data[63:0] = '0;
                    // Feature type is AFU
                    cpl_data[63:60] = 4'h1;
                    // End of list
                    cpl_data[40] = 1'b1;
                end

            // AFU_ID_L
            4'h1:
                begin
                    cpl_data[63:0] = '0;
                    cpl_data[63:56] = { '0, port.vf_num };
                    cpl_data[52] = port.vf_active;
                    cpl_data[51:48] = { '0, port.pf_num };
                end

            // AFU_ID_H
            4'h2: cpl_data[63:0] = 64'hd15ab1ed00000000;

            default: cpl_data[63:0] = '0;
        endcase

        // Was the request short, asking for the high 32 bits of the 64 bit register?
        if (tx_cpl_hdr.low_addr[2])
        begin
            cpl_data[31:0] = cpl_data[63:32];
        end
    end

    // Forward the completion to the AFU->host TX stream
    always_comb
    begin
        tx_st.tvalid = rx_hdr_valid &&
                       pcie_ss_hdr_pkg::func_is_mrd_req(rx_hdr.fmt_type);
        tx_st.t = '0;
        // TLP payload is the completion data and the header
        tx_st.t.data.payload = { '0, cpl_data, tx_cpl_hdr };
        tx_st.t.user[0].sop = tx_st.tvalid;
        tx_st.t.user[0].eop = tx_st.tvalid;
        // Keep matches the data: either 8 or 4 bytes of data and the header
        tx_st.t.keep = { '0, {4{(rx_hdr.length > 1)}}, {4{1'b1}}, {TX_CPL_HDR_BYTES{1'b1}} };
        tx_st.t.last = 1'b1;
    end

    assign port.afu_tx_b_st.tvalid = 1'b0;
    assign port.afu_tx_b_st.t = '0;
    assign port.afu_csr_if.awready = 1'b1;
    assign port.afu_csr_if.wready = 1'b1;
    assign port.afu_csr_if.bvalid = 1'b0;
    assign port.afu_csr_if.b = '0;
    assign port.afu_csr_if.arready = 1'b1;
    assign port.afu_csr_if.rvalid = 1'b0;
    assign port.afu_csr_if.r = '0;

endmodule // ofs_plat_host_chan_@group@_fim_gasket_tie_off_tlp
