// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Map PCIe TLPs to CCI-P.
//

`include "ofs_plat_if.vh"


// The TLP mapper has multiple request/response AXI streams. Define a macro
// that instantiates a stream "instance_name" of "data_type" and assigns
// standard clock, reset and debug info.
`define AXI_STREAM_INSTANCE(instance_name, data_type) \
    ofs_plat_axi_stream_if \
      #( \
        .TDATA_TYPE(data_type), \
        .TUSER_TYPE(logic) /* Unused */ \
        ) \
      instance_name(); \
    assign instance_name.clk = clk; \
    assign instance_name.reset_n = reset_n; \
    assign instance_name.instance_number = to_fiu_tlp.instance_number


module ofs_plat_host_chan_@group@_map_as_ccip
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu_tlp,
    ofs_plat_host_ccip_if.to_afu to_afu_ccip
    );

    import ofs_plat_host_chan_@group@_pcie_tlp_pkg::*;
    import ofs_plat_host_chan_@group@_gen_tlps_pkg::*;

    logic clk;
    assign clk = to_fiu_tlp.clk;
    logic reset_n;
    assign reset_n = to_fiu_tlp.reset_n;

    assign to_afu_ccip.clk = to_fiu_tlp.clk;
    assign to_afu_ccip.reset_n = to_fiu_tlp.reset_n;
    assign to_afu_ccip.instance_number = to_fiu_tlp.instance_number;

    assign to_afu_ccip.error = 1'b0;

    // synthesis translate_off
    initial
    begin
        if (PAYLOAD_LINE_SIZE != 512)
            $fatal(2, "** ERROR ** %m: CCI-P only supports a 512 bit data bus, not %0d", PAYLOAD_LINE_SIZE);
    end
    // synthesis translate_on

    // ====================================================================
    //
    //  Buffer CCI-P TX request traffic in order to convert the almost
    //  full protocol to ready/enable.
    //
    // ====================================================================

    t_if_ccip_c0_Tx afu_c0Tx;
    logic afu_c0Tx_valid, afu_c0Tx_ready;

    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_if_ccip_c0_Tx)),
        .N_ENTRIES(CCIP_TX_ALMOST_FULL_THRESHOLD + 4),
        .THRESHOLD(CCIP_TX_ALMOST_FULL_THRESHOLD),
        .REGISTER_OUTPUT(1)
        )
      c0Tx_in
       (
        .clk,
        .reset_n,
        .enq_data(to_afu_ccip.sTx.c0),
        .enq_en(to_afu_ccip.sTx.c0.valid),
        .notFull(),
        .almostFull(to_afu_ccip.sRx.c0TxAlmFull),
        .first(afu_c0Tx),
        .deq_en(afu_c0Tx_valid && afu_c0Tx_ready),
        .notEmpty(afu_c0Tx_valid)
        );


    t_if_ccip_c1_Tx afu_c1Tx;
    logic afu_c1Tx_valid, afu_c1Tx_ready;

    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_if_ccip_c1_Tx)),
        .N_ENTRIES(CCIP_TX_ALMOST_FULL_THRESHOLD + 4),
        .THRESHOLD(CCIP_TX_ALMOST_FULL_THRESHOLD),
        .REGISTER_OUTPUT(1)
        )
      c1Tx_in
       (
        .clk,
        .reset_n,
        .enq_data(to_afu_ccip.sTx.c1),
        .enq_en(to_afu_ccip.sTx.c1.valid),
        .notFull(),
        .almostFull(to_afu_ccip.sRx.c1TxAlmFull),
        .first(afu_c1Tx),
        .deq_en(afu_c1Tx_valid && afu_c1Tx_ready),
        .notEmpty(afu_c1Tx_valid)
        );


    t_if_ccip_c2_Tx afu_c2Tx;
    logic afu_c2Tx_valid, afu_c2Tx_ready;

    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_if_ccip_c2_Tx)),
        // There is no flow control on c2 MMIO read responses. The buffer must
        // hold all possible pending responses.
        .N_ENTRIES(MAX_OUTSTANDING_MMIO_RD_REQS),
        .REGISTER_OUTPUT(1)
        )
      c2Tx_in
       (
        .clk,
        .reset_n,
        .enq_data(to_afu_ccip.sTx.c2),
        .enq_en(to_afu_ccip.sTx.c2.mmioRdValid),
        .notFull(),
        .almostFull(),
        .first(afu_c2Tx),
        .deq_en(afu_c2Tx_valid && afu_c2Tx_ready),
        .notEmpty(afu_c2Tx_valid)
        );


    // ====================================================================
    //
    //  MMIO requests from host
    //
    // ====================================================================

    // MMIO requests from host to AFU (t_gen_tx_mmio_afu_req)
    `AXI_STREAM_INSTANCE(host_mmio_req, t_gen_tx_mmio_afu_req);

    // The AFU is always prepared to accept an MMIO request. There is no flow
    // control on the CCI-P sRx.c0 stream and MMIO is given priority over
    // read responses in the code below.
    assign host_mmio_req.tready = 1'b1;

    logic c0Rx_mmio_req_valid;
    t_gen_tx_mmio_afu_req c0Rx_mmio_req;
    always_ff @(posedge clk)
    begin
        c0Rx_mmio_req_valid <= host_mmio_req.tvalid;
        c0Rx_mmio_req <= host_mmio_req.t.data;
    end

    // Generate an MMIO header, used only when the actual command is a read or write
    t_ccip_c0_ReqMmioHdr c0Rx_mmio_hdr;
    always_ff @(posedge clk)
    begin
        c0Rx_mmio_hdr <= '0;
        c0Rx_mmio_hdr.tid <= t_ccip_tid'(host_mmio_req.t.data.tag);
        c0Rx_mmio_hdr.address <= t_ccip_mmioAddr'(host_mmio_req.t.data.addr >> 2);

        if (host_mmio_req.t.data.byte_count >= 64)
        begin
            c0Rx_mmio_hdr.length <= 2'b10;
        end
        else if (host_mmio_req.t.data.byte_count >= 8)
        begin
            c0Rx_mmio_hdr.length <= 2'b01;
        end
    end

    // AFU responses (t_gen_tx_mmio_afu_rsp)
    `AXI_STREAM_INSTANCE(host_mmio_rsp, t_gen_tx_mmio_afu_rsp);

    assign host_mmio_rsp.tvalid = afu_c2Tx_valid;
    assign afu_c2Tx_ready = host_mmio_rsp.tready;
    assign host_mmio_rsp.t.data.tag = t_mmio_rd_tag'(afu_c2Tx.hdr.tid);
    assign host_mmio_rsp.t.data.payload = { '0, afu_c2Tx.data };


    // ====================================================================
    //
    //  Manage AFU read requests and host completion responses
    //
    // ====================================================================

    function automatic t_tlp_payload_line_count count_from_cl_len(t_ccip_clLen cl_len);
        t_tlp_payload_line_count len;

        case (cl_len)
            eCL_LEN_1: len = 1;
            eCL_LEN_2: len = 2;
            eCL_LEN_4: len = 4;
            default:   len = 1;
        endcase

        return len;
    endfunction

    // Track read requests from AFU (t_gen_tx_afu_rd_req)
    `AXI_STREAM_INSTANCE(afu_rd_req, t_gen_tx_afu_rd_req);
    assign afu_rd_req.tvalid = afu_c0Tx_valid;
    assign afu_c0Tx_ready = afu_rd_req.tready;
    assign afu_rd_req.t.data.tag = afu_c0Tx.hdr.mdata;
    assign afu_rd_req.t.data.line_count = count_from_cl_len(afu_c0Tx.hdr.cl_len);
    assign afu_rd_req.t.data.addr = { '0, afu_c0Tx.hdr.address, 6'b0 };
    // Atomics not supported in CCI-P
    assign afu_rd_req.t.data.is_atomic = 1'b0;

    // Read responses to AFU (t_gen_tx_afu_rd_rsp)
    `AXI_STREAM_INSTANCE(afu_rd_rsp, t_gen_tx_afu_rd_rsp);

    //
    // MMIO requests and read responses to the AFU share the same sRx channel 0.
    // Merge them here, favoring MMIO requests over read responses.
    //
    assign afu_rd_rsp.tready = !c0Rx_mmio_req_valid;

    always_ff @(posedge clk)
    begin
        if (c0Rx_mmio_req_valid)
        begin
            // MMIO request from host to AFU
            to_afu_ccip.sRx.c0.hdr <= c0Rx_mmio_hdr;
            to_afu_ccip.sRx.c0.data <= c0Rx_mmio_req.payload;
            to_afu_ccip.sRx.c0.rspValid <= 1'b0;
            to_afu_ccip.sRx.c0.mmioRdValid <= !c0Rx_mmio_req.is_write;
            to_afu_ccip.sRx.c0.mmioWrValid <= c0Rx_mmio_req.is_write;
        end
        else
        begin
            // Read completion to AFU
            to_afu_ccip.sRx.c0.rspValid <= afu_rd_rsp.tvalid && afu_rd_rsp.tready;
            to_afu_ccip.sRx.c0.mmioRdValid <= 1'b0;
            to_afu_ccip.sRx.c0.mmioWrValid <= 1'b0;

            to_afu_ccip.sRx.c0.hdr <= '0;
            to_afu_ccip.sRx.c0.hdr.vc_used <= eVC_VH0;
            to_afu_ccip.sRx.c0.hdr.cl_num <= t_ccip_clNum'(afu_rd_rsp.t.data.line_idx);
            to_afu_ccip.sRx.c0.hdr.mdata <= afu_rd_rsp.t.data.tag;

            to_afu_ccip.sRx.c0.data <= afu_rd_rsp.t.data.payload;
        end

        if (!reset_n)
        begin
            to_afu_ccip.sRx.c0.mmioRdValid <= 1'b0;
            to_afu_ccip.sRx.c0.mmioWrValid <= 1'b0;
            to_afu_ccip.sRx.c0.rspValid <= 1'b0;
        end
    end


    // ====================================================================
    //
    //  Manage AFU write requests
    //
    // ====================================================================

    // Track packet length of multi-beat packets
    logic [1:0] afu_c1Tx_pkt_len;
    always_ff @(posedge clk)
    begin
        if (afu_c1Tx_valid && afu_c1Tx.hdr.sop)
        begin
            afu_c1Tx_pkt_len <= 2'(afu_c1Tx.hdr.cl_len);
        end
    end

    // Write requests from AFU (t_gen_tx_afu_wr_req)
    `AXI_STREAM_INSTANCE(afu_wr_req, t_gen_tx_afu_wr_req);
    assign afu_wr_req.tvalid = afu_c1Tx_valid;
    assign afu_c1Tx_ready = afu_wr_req.tready;

    logic afu_c1Tx_not_normal_write;
    assign afu_c1Tx_not_normal_write = (afu_c1Tx.hdr.req_type == eREQ_WRFENCE) ||
                                       (afu_c1Tx.hdr.req_type == eREQ_INTR);

    assign afu_wr_req.t.data.sop = (afu_c1Tx.hdr.sop || afu_c1Tx_not_normal_write);

    // End of packet if:
    //  - Single line write
    //  - Two line write and not SOP (afu_c1Tx_pkt_len[1] == 0 means two line write)
    //  - Four line write and low address is also 2'b11. Addresses are naturally aligned.
    assign afu_wr_req.t.data.eop =
        afu_c1Tx_not_normal_write ||
        (afu_c1Tx.hdr.sop ? (afu_c1Tx.hdr.cl_len == 0) :
                            ((afu_c1Tx_pkt_len[1] == 1'b0) ||
                             (afu_c1Tx.hdr.address[1:0] == 2'b11)));

    // c1Tx cast as an interrupt header (when req_type is eREQ_INTR)
    t_ccip_c1_ReqIntrHdr c1Tx_intr_hdr;
    assign c1Tx_intr_hdr = t_ccip_c1_ReqIntrHdr'(afu_c1Tx.hdr);

    // These have to be correct only on the first beat
    assign afu_wr_req.t.data.is_fence = (afu_c1Tx.hdr.req_type == eREQ_WRFENCE);
    assign afu_wr_req.t.data.is_interrupt = (afu_c1Tx.hdr.req_type == eREQ_INTR);
    assign afu_wr_req.t.data.tag =
        (afu_c1Tx.hdr.req_type != eREQ_INTR) ? afu_c1Tx.hdr.mdata :
                                               { '0, c1Tx_intr_hdr.id };
    assign afu_wr_req.t.data.line_count = count_from_cl_len(afu_c1Tx.hdr.cl_len);
    assign afu_wr_req.t.data.addr = { '0, afu_c1Tx.hdr.address, 6'b0 };

    // Atomics not supported in CCI-P
    assign afu_wr_req.t.data.is_atomic = 1'b0;
    assign afu_wr_req.t.data.atomic_op = TLP_NOT_ATOMIC;

    assign afu_wr_req.t.data.enable_byte_range = (afu_c1Tx.hdr.mode == eMOD_BYTE);
    assign afu_wr_req.t.data.byte_start_idx = afu_c1Tx.hdr.byte_start;
    assign afu_wr_req.t.data.byte_len = afu_c1Tx.hdr.byte_len;

    assign afu_wr_req.t.data.payload = afu_c1Tx.data;


    // Write responses to AFU once the packet is completely sent (t_gen_tx_afu_wr_rsp)
    `AXI_STREAM_INSTANCE(afu_wr_rsp, t_gen_tx_afu_wr_rsp);
    assign afu_wr_rsp.tready = 1'b1;

    always_ff @(posedge clk)
    begin
        // Write completion to AFU
        to_afu_ccip.sRx.c1.rspValid <= afu_wr_rsp.tvalid && afu_wr_rsp.tready;

        to_afu_ccip.sRx.c1.hdr <= '0;
        to_afu_ccip.sRx.c1.hdr.vc_used <= eVC_VH0;
        to_afu_ccip.sRx.c1.hdr.format <= 1'b1;
        to_afu_ccip.sRx.c1.hdr.cl_num <= t_ccip_clNum'(afu_wr_rsp.t.data.line_idx);
        to_afu_ccip.sRx.c1.hdr.mdata <= afu_wr_rsp.t.data.tag;
        if (afu_wr_rsp.t.data.is_fence)
        begin
            to_afu_ccip.sRx.c1.hdr.resp_type <= eRSP_WRFENCE;
        end
        else if (afu_wr_rsp.t.data.is_interrupt)
        begin
            // "mdata" and interrupt header "id" are in the same position,
            // so setting mdata from the tag already copies the ID properly.
            to_afu_ccip.sRx.c1.hdr.resp_type <= eRSP_INTR;
        end
        else
        begin
            to_afu_ccip.sRx.c1.hdr.resp_type <= eRSP_WRLINE;
        end

        if (!reset_n)
        begin
            to_afu_ccip.sRx.c1.rspValid <= 1'b0;
        end
    end


    // ====================================================================
    //
    //  Instantiate the TLP mapper.
    //
    // ====================================================================

    ofs_plat_host_chan_@group@_map_to_tlps tlp_mapper
       (
        .to_fiu_tlp,
        .allow_dm_enc(1'b1),

        .host_mmio_req,
        .host_mmio_rsp,

        .afu_rd_req,
        .afu_rd_rsp,

        .afu_wr_req,
        .afu_wr_rsp
        );


endmodule // ofs_plat_map_axis_pcie_tlp_as_ccip
