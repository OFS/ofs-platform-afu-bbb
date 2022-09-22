//
// Copyright (c) 2022, Intel Corporation
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
// Emulate the PCIe SS mode in which MMIO (CSR) traffic is delivered on
// an AXI-Lite bus separate from the TLP stream. The logic here manages
// a FIM-side TLP stream with embedded MMIO. It filters out MMIO requests
// coming from the FIM and moves them to afu_csr_axi_lite_if. CSR read
// responses are merged back in to the FIM TLP stream.
//
// There is also a clock crossing, with the CSR AXI-Lite bus using a
// separate clock.
//

`include "ofs_plat_if.vh"

// Only compile when OFS_PCIE_SS_PLAT_AXI_L_MMIO is defined, since older
// platforms may not have ofs_fim_axi_lite_if defined.
`ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO

module ase_emul_pcie_ss_split_mmio
  #(
    // PCIe PF/VF details
    parameter pcie_ss_hdr_pkg::ReqHdr_pf_num_t PF_NUM,
    parameter pcie_ss_hdr_pkg::ReqHdr_vf_num_t VF_NUM,
    parameter VF_ACTIVE
   )
   (
    ofs_fim_axi_lite_if.source afu_csr_axi_lite_if,

    pcie_ss_axis_if.sink afu_tlp_tx_if,
    pcie_ss_axis_if.source fim_tlp_tx_if,
    pcie_ss_axis_if.source afu_tlp_rx_if,
    pcie_ss_axis_if.sink fim_tlp_rx_if
    );

    wire clk = afu_tlp_tx_if.clk;
    wire rst_n = afu_tlp_tx_if.rst_n;
    wire csr_clk = afu_csr_axi_lite_if.clk;
    logic csr_rst_n = 1'b0;

    // Apply soft reset to the CSR interface
    logic csr_flr_rst_n;
    ofs_plat_prim_clock_crossing_reset flr_to_csr
       (
        .clk_src(clk),
        .clk_dst(csr_clk),
        .reset_in(rst_n),
        .reset_out(csr_flr_rst_n)
        );

    always @(posedge csr_clk)
    begin
        csr_rst_n <= afu_csr_axi_lite_if.rst_n && csr_flr_rst_n;
    end


    localparam CSR_ADDR_WIDTH = afu_csr_axi_lite_if.AWADDR_WIDTH;
    localparam CSR_DATA_WIDTH = afu_csr_axi_lite_if.WDATA_WIDTH;

    // Byte address from TLP request header
    function automatic logic [CSR_ADDR_WIDTH-1 : 0] tlp_hdr_addr(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t hdr);
        if (pcie_ss_hdr_pkg::func_is_addr64(hdr.fmt_type))
            return CSR_ADDR_WIDTH'({ '0, hdr.host_addr_h, hdr.host_addr_l, 2'b0 });
        else
            return CSR_ADDR_WIDTH'({ '0, hdr.host_addr_h });
    endfunction // tlp_hdr_addr


    //
    // Track TLP SOP in each direction
    //
    logic is_tx_sop, is_rx_sop;

    always_ff @(posedge clk)
    begin
        if (afu_tlp_tx_if.tvalid && afu_tlp_tx_if.tready)
        begin
            is_tx_sop <= afu_tlp_tx_if.tlast;
        end

        if (fim_tlp_rx_if.tvalid && fim_tlp_rx_if.tready)
        begin
            is_rx_sop <= fim_tlp_rx_if.tlast;
        end

        if (!rst_n)
        begin
            is_tx_sop <= 1'b1;
            is_rx_sop <= 1'b1;
        end
    end


    //
    // CSR read request (PCIe -> AFU) buffer and clock crossing
    //
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t fim_tlp_rx_hdr;
    assign fim_tlp_rx_hdr = pcie_ss_hdr_pkg::PCIe_PUReqHdr_t'(fim_tlp_rx_if.tdata);
    wire fim_tlp_rx_is_csr_rd = pcie_ss_hdr_pkg::func_is_mrd_req(fim_tlp_rx_hdr.fmt_type) &&
                                is_rx_sop;

    always_ff @(negedge clk)
    begin
        if (rst_n && fim_tlp_rx_is_csr_rd && fim_tlp_rx_if.tvalid)
        begin
            assert(pcie_ss_hdr_pkg::func_hdr_is_pu_mode(fim_tlp_rx_if.tuser_vendor)) else
                $fatal(2, "** ERROR ** %m: MMIO read requests expected to be PU encoded!");
            assert(fim_tlp_rx_hdr.length <= 2) else
                $fatal(2, "** ERROR ** %m: MMIO read request packet too long!");
            assert(fim_tlp_rx_if.tlast) else
                $fatal(2, "** ERROR ** %m: MMIO read request packet not tlast!");
        end
    end

    logic csr_rd_req_notFull;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t csr_rd_req_hdr;
    logic csr_rd_req_deq;
    logic csr_rd_req_notEmpty;

    // Read state machine. The PCIe SS has no tags on CSR AXI-Lite reads,
    // so allows only one request to be outstanding on the bus. The logic here
    // uses csr_rd_req to hold TLP metadata for the outstanding request and
    // a state machine to track an active request.
    logic csr_rd_busy;
    always_ff @(posedge csr_clk)
    begin
        if (afu_csr_axi_lite_if.arvalid && afu_csr_axi_lite_if.arready)
            csr_rd_busy <= 1'b1;

        if (!csr_rst_n || csr_rd_req_deq)
            csr_rd_busy <= 1'b0;
    end

    ofs_plat_prim_fifo_dc
      #(
        .N_DATA_BITS($bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t)),
        .N_ENTRIES(64)
        )
      csr_rd_req_fifo
       (
        .enq_clk(clk),
        .enq_reset_n(csr_rst_n),
        // Push the entire header into the buffer. Some of the state will be
        // needed to generate the response.
        .enq_data(fim_tlp_rx_hdr),
        .enq_en(fim_tlp_rx_is_csr_rd && fim_tlp_rx_if.tvalid && fim_tlp_rx_if.tready),
        .notFull(csr_rd_req_notFull),
        .almostFull(),

        .deq_clk(csr_clk),
        .deq_reset_n(csr_rst_n),
        .first(csr_rd_req_hdr),
        .deq_en(csr_rd_req_deq),
        .notEmpty(csr_rd_req_notEmpty)
        );

    assign csr_rd_req_deq = afu_csr_axi_lite_if.rvalid && afu_csr_axi_lite_if.rready;
    assign afu_csr_axi_lite_if.arvalid = csr_rd_req_notEmpty && !csr_rd_busy;
    always_comb
    begin
        afu_csr_axi_lite_if.arprot = '0;

        afu_csr_axi_lite_if.araddr = tlp_hdr_addr(csr_rd_req_hdr);
        // The PCIe SS generates read addresses that are always aligned to the
        // bus.
        afu_csr_axi_lite_if.araddr[$clog2(CSR_DATA_WIDTH/8)-1 : 0] = '0;
    end


    //
    // CSR read response (AFU -> PCIe) buffer and clock crossing
    //
    logic [CSR_DATA_WIDTH-1 : 0] csr_rd_rsp_data_out;
    logic csr_rd_rsp_notEmpty;
    logic csr_rd_rsp_deq;

    // Generated CSR read TLP response. Build the header from the request header.
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t csr_rd_rsp_hdr, csr_rd_rsp_hdr_out;
    always_comb
    begin
        csr_rd_rsp_hdr = '0;
        csr_rd_rsp_hdr.fmt_type = pcie_ss_hdr_pkg::ReqHdr_FmtType_e'(pcie_ss_hdr_pkg::PCIE_FMTTYPE_CPLD);
        csr_rd_rsp_hdr.length = csr_rd_req_hdr.length;
        csr_rd_rsp_hdr.req_id = csr_rd_req_hdr.req_id;
        csr_rd_rsp_hdr.tag_l = csr_rd_req_hdr.tag_l;
        csr_rd_rsp_hdr.tag_m = csr_rd_req_hdr.tag_m;
        csr_rd_rsp_hdr.tag_h = csr_rd_req_hdr.tag_h;
        csr_rd_rsp_hdr.TC = csr_rd_req_hdr.TC;
        csr_rd_rsp_hdr.byte_count = csr_rd_req_hdr.length << 2;
        csr_rd_rsp_hdr.low_addr = 7'(tlp_hdr_addr(csr_rd_req_hdr));

        csr_rd_rsp_hdr.comp_id = { VF_NUM, 1'(VF_ACTIVE), PF_NUM };
        csr_rd_rsp_hdr.pf_num = PF_NUM;
        csr_rd_rsp_hdr.vf_num = VF_NUM;
        csr_rd_rsp_hdr.vf_active = VF_ACTIVE;
    end

    ofs_plat_prim_fifo_dc
      #(
        .N_DATA_BITS($bits(pcie_ss_hdr_pkg::PCIe_PUCplHdr_t) + CSR_DATA_WIDTH),
        .N_ENTRIES(64)
        )
      csr_rd_rsp_fifo
       (
        .enq_clk(csr_clk),
        .enq_reset_n(csr_rst_n),
        .enq_data({ csr_rd_rsp_hdr, afu_csr_axi_lite_if.rdata }),
        .enq_en(afu_csr_axi_lite_if.rvalid && afu_csr_axi_lite_if.rready),
        .notFull(afu_csr_axi_lite_if.rready),
        .almostFull(),

        .deq_clk(clk),
        .deq_reset_n(rst_n),
        .first({ csr_rd_rsp_hdr_out, csr_rd_rsp_data_out }),
        .deq_en(csr_rd_rsp_deq),
        .notEmpty(csr_rd_rsp_notEmpty)
        );


    // Response data. Complexity comes from moving 32 bit data to the right place.
    logic [CSR_DATA_WIDTH-1 : 0] csr_rd_rsp_data;
    logic [(CSR_DATA_WIDTH/8)-1 : 0] csr_rd_rsp_strb;

    always_comb
    begin
        // 32 or smaller access to upper half of a 64 bit space?
        csr_rd_rsp_data = csr_rd_rsp_data_out;
        if (csr_rd_rsp_hdr_out.low_addr[2])
            csr_rd_rsp_data[31:0] = csr_rd_rsp_data_out[63:32];

        if (csr_rd_rsp_hdr_out.length == 1)
            csr_rd_rsp_strb = 'hf;
        else
            csr_rd_rsp_strb = ~'0;
    end


    //
    // CSR write address request (PCIe -> AFU) buffer and clock crossing
    //
    wire fim_tlp_rx_is_csr_wr = pcie_ss_hdr_pkg::func_is_mwr_req(fim_tlp_rx_hdr.fmt_type) &&
                                is_rx_sop;
    wire [CSR_ADDR_WIDTH-1 : 0] fim_tlp_rx_addr = tlp_hdr_addr(fim_tlp_rx_hdr);

    always_ff @(negedge clk)
    begin
        if (rst_n && fim_tlp_rx_is_csr_wr && fim_tlp_rx_if.tvalid)
        begin
            assert(pcie_ss_hdr_pkg::func_hdr_is_pu_mode(fim_tlp_rx_if.tuser_vendor)) else
                $fatal(2, "** ERROR ** %m: MMIO write requests expected to be PU encoded!");
            assert(fim_tlp_rx_hdr.length <= 2) else
                $fatal(2, "** ERROR ** %m: MMIO write request packet too long! AXI-Lite CSR supports up to 64 bit writes.");
            assert(fim_tlp_rx_if.tlast) else
                $fatal(2, "** ERROR ** %m: MMIO write request packet not tlast!");
        end
    end

    logic csr_wr_req_notFull;
    logic [CSR_ADDR_WIDTH-1 : 0] csr_wr_req_addr;

    ofs_plat_prim_fifo_dc
      #(
        .N_DATA_BITS(CSR_ADDR_WIDTH),
        .N_ENTRIES(64)
        )
      csr_wr_req_fifo
       (
        .enq_clk(clk),
        .enq_reset_n(csr_rst_n),
        .enq_data(fim_tlp_rx_addr),
        .enq_en(fim_tlp_rx_is_csr_wr && fim_tlp_rx_if.tvalid && fim_tlp_rx_if.tready),
        .notFull(csr_wr_req_notFull),
        .almostFull(),

        .deq_clk(csr_clk),
        .deq_reset_n(csr_rst_n),
        .first(csr_wr_req_addr),
        .deq_en(afu_csr_axi_lite_if.awvalid && afu_csr_axi_lite_if.awready),
        .notEmpty(afu_csr_axi_lite_if.awvalid)
        );

    assign afu_csr_axi_lite_if.awaddr = csr_wr_req_addr;
    assign afu_csr_axi_lite_if.awprot = '0;

    // No PCIe response is expected for CSR writes. Consume and drop B.
    assign afu_csr_axi_lite_if.bready = 1'b1;


    //
    // CSR write data (PCIe -> AFU) buffer and clock crossing
    //
    logic csr_wr_data_notFull;
    logic [CSR_DATA_WIDTH-1 : 0] csr_wr_data;
    logic [(CSR_DATA_WIDTH/8)-1 : 0] csr_wr_strb;

    always_comb
    begin
        if (fim_tlp_rx_hdr.length > 1)
        begin
            // Write larger than 32 bits. Assume it is the full bus.
            csr_wr_data = fim_tlp_rx_if.tdata[$bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t) +: CSR_DATA_WIDTH];
            csr_wr_strb = ~0;
        end
        else
        begin
            // 32 bits or smaller. Use the low dword address bit to pick either
            // the first or second dword in the write data buffer.
            csr_wr_data = '0;
            csr_wr_data[(32 * fim_tlp_rx_addr[2]) +: 32] =
                fim_tlp_rx_if.tdata[$bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t) +: 32];

            // Apply the incoming byte mask to the appropriate dword.
            csr_wr_strb = 0;
            csr_wr_strb[(4 * fim_tlp_rx_addr[2]) +: 4] = fim_tlp_rx_hdr.first_dw_be;
        end
    end

    ofs_plat_prim_fifo_dc
      #(
        .N_DATA_BITS((CSR_DATA_WIDTH/8) + CSR_DATA_WIDTH),
        .N_ENTRIES(64)
        )
      csr_wr_data_fifo
       (
        .enq_clk(clk),
        .enq_reset_n(csr_rst_n),
        .enq_data({ csr_wr_strb, csr_wr_data }),
        .enq_en(fim_tlp_rx_is_csr_wr && fim_tlp_rx_if.tvalid && fim_tlp_rx_if.tready),
        .notFull(csr_wr_data_notFull),
        .almostFull(),

        .deq_clk(csr_clk),
        .deq_reset_n(csr_rst_n),
        .first({ afu_csr_axi_lite_if.wstrb, afu_csr_axi_lite_if.wdata }),
        .deq_en(afu_csr_axi_lite_if.wvalid && afu_csr_axi_lite_if.wready),
        .notEmpty(afu_csr_axi_lite_if.wvalid)
        );


    //
    // Control logic
    //

    // Ready for TLP from FIM?
    wire csr_req_ready = !is_rx_sop ||
                         (csr_rd_req_notFull && csr_wr_req_notFull && csr_wr_data_notFull);
    assign fim_tlp_rx_if.tready = afu_tlp_rx_if.tready && csr_req_ready;
    assign afu_tlp_rx_if.tvalid = fim_tlp_rx_if.tvalid && csr_req_ready &&
                                  !fim_tlp_rx_is_csr_rd && !fim_tlp_rx_is_csr_wr;

    // Ready for CSR read response as a TLP to the FIM? If not, forward normal TLP
    // TX traffic.
    wire pick_csr_rd_rsp = is_tx_sop && csr_rd_rsp_notEmpty;
    assign csr_rd_rsp_deq = pick_csr_rd_rsp && fim_tlp_tx_if.tready;
    assign fim_tlp_tx_if.tvalid = pick_csr_rd_rsp || afu_tlp_tx_if.tvalid;
    assign afu_tlp_tx_if.tready = fim_tlp_tx_if.tready && !pick_csr_rd_rsp;

    // Connect data. Only tready/tvalid will determine packet routing.
    always_comb
    begin
        afu_tlp_rx_if.tlast = fim_tlp_rx_if.tlast;
        afu_tlp_rx_if.tuser_vendor = fim_tlp_rx_if.tuser_vendor;
        afu_tlp_rx_if.tdata = fim_tlp_rx_if.tdata;
        afu_tlp_rx_if.tkeep = fim_tlp_rx_if.tkeep;

        if (pick_csr_rd_rsp)
        begin
            fim_tlp_tx_if.tlast = 1'b1;
            fim_tlp_tx_if.tuser_vendor = '0;
            fim_tlp_tx_if.tdata = { '0, csr_rd_rsp_data, csr_rd_rsp_hdr_out };
            fim_tlp_tx_if.tkeep = { '0, csr_rd_rsp_strb, 16'hffff };
        end
        else
        begin
            fim_tlp_tx_if.tlast = afu_tlp_tx_if.tlast;
            fim_tlp_tx_if.tuser_vendor = afu_tlp_tx_if.tuser_vendor;
            fim_tlp_tx_if.tdata = afu_tlp_tx_if.tdata;
            fim_tlp_tx_if.tkeep = afu_tlp_tx_if.tkeep;
        end
    end

endmodule // ase_emul_pcie_ss_split_mmio

`endif //  `ifdef OFS_PCIE_SS_PLAT_AXI_L_MMIO
