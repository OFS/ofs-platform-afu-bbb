// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Map PCIe TLPs to an AXI memory interface.
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


module ofs_plat_host_chan_@group@_map_as_axi_mem_if
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu_tlp,
    ofs_plat_axi_mem_if.to_source mem_source,
    ofs_plat_axi_mem_lite_if.to_sink mmio_sink,

    // A second, write-only MMIO sink. If used, an AFU will likely use
    // this interface to receive wide MMIO writes without also having to
    // build wide MMIO read channels.
    ofs_plat_axi_mem_lite_if.to_sink mmio_wo_sink,

    // Allow Data Mover TLP encoding? This must be in the to_fiu_tlp
    // clock domain.
    input  logic allow_dm_enc
    );

    import ofs_plat_host_chan_@group@_pcie_tlp_pkg::*;
    import ofs_plat_host_chan_@group@_gen_tlps_pkg::*;
    import ofs_plat_host_chan_axi_mem_pkg::*;

    logic clk;
    assign clk = to_fiu_tlp.clk;
    logic reset_n;
    assign reset_n = to_fiu_tlp.reset_n;


    // ====================================================================
    //
    //  Forward all memory and MMIO channels through skid buffers for
    //  channel synchronization and timing.
    //
    // ====================================================================

    //
    // Host memory
    //

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_source)
        )
      mem_if();

    assign mem_if.clk = clk;
    assign mem_if.reset_n = reset_n;
    assign mem_if.instance_number = to_fiu_tlp.instance_number;

    ofs_plat_axi_mem_if_skid mem_skid
       (
        .mem_source,
        .mem_sink(mem_if)
        );

    //
    // MMIO
    //

    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_sink)
        )
      mmio_if();

    assign mmio_if.clk = clk;
    assign mmio_if.reset_n = reset_n;
    assign mmio_if.instance_number = to_fiu_tlp.instance_number;

    ofs_plat_axi_mem_lite_if_skid mmio_skid
       (
        .mem_sink(mmio_sink),
        .mem_source(mmio_if)
        );

    // Second (write-only) MMIO interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_wo_sink)
        )
      mmio_wo_if();

    assign mmio_wo_if.clk = clk;
    assign mmio_wo_if.reset_n = reset_n;
    assign mmio_wo_if.instance_number = to_fiu_tlp.instance_number;

    ofs_plat_axi_mem_lite_if_skid
      #(
        .SKID_B(0),
        .SKID_AR(0),
        .SKID_R(0)
        )
      mmio_wo_skid
       (
        .mem_sink(mmio_wo_sink),
        .mem_source(mmio_wo_if)
        );

    assign mmio_wo_if.arvalid = 1'b0;
    assign mmio_wo_if.rready = 1'b1;

    // MMIO write response is ignored
    assign mmio_if.bready = 1'b1;
    assign mmio_wo_if.bready = 1'b1;


    // ====================================================================
    //
    //  MMIO requests from host
    //
    // ====================================================================

    // MMIO requests from host to AFU (t_gen_tx_mmio_afu_req)
    `AXI_STREAM_INSTANCE(host_mmio_req, t_gen_tx_mmio_afu_req);

    localparam MMIO_ADDR_WIDTH = mmio_sink.ADDR_WIDTH;
    typedef logic [MMIO_ADDR_WIDTH-1 : 0] t_mmio_addr;
    localparam MMIO_DATA_WIDTH = mmio_sink.DATA_WIDTH;
    typedef logic [MMIO_DATA_WIDTH-1 : 0] t_mmio_data;

    localparam MMIO_WO_ADDR_WIDTH = mmio_wo_sink.ADDR_WIDTH;
    typedef logic [MMIO_WO_ADDR_WIDTH-1 : 0] t_mmio_wo_addr;
    localparam MMIO_WO_DATA_WIDTH = mmio_wo_sink.DATA_WIDTH;
    typedef logic [MMIO_WO_DATA_WIDTH-1 : 0] t_mmio_wo_data;

    // Index of the minimum addressable size (32 bit DWORD)
    localparam MMIO_DWORDS = MMIO_DATA_WIDTH / 32;
    localparam MMIO_DWORD_IDX_BITS = $clog2(MMIO_DWORDS);
    typedef logic [MMIO_DWORD_IDX_BITS-1 : 0] t_mmio_dword_idx;

    localparam MMIO_DATA_WIDTH_LEGAL =
        (MMIO_DATA_WIDTH >= 64) && (MMIO_DATA_WIDTH <= 512) &&
        (MMIO_DATA_WIDTH == (2 ** $clog2(MMIO_DATA_WIDTH)));
    localparam MMIO_WO_DATA_WIDTH_LEGAL =
        (MMIO_WO_DATA_WIDTH >= 64) && (MMIO_WO_DATA_WIDTH <= 512) &&
        (MMIO_WO_DATA_WIDTH == (2 ** $clog2(MMIO_WO_DATA_WIDTH)));

    // synthesis translate_off
    initial
    begin
        if (! MMIO_DATA_WIDTH_LEGAL)
            $fatal(2, "** ERROR ** %m: MMIO data width (%0d) must be a power of 2 between 64 and 512.", MMIO_DATA_WIDTH);
        if (! MMIO_WO_DATA_WIDTH_LEGAL)
            $fatal(2, "** ERROR ** %m: MMIO write-only data width (%0d) must be a power of 2 between 64 and 512.", MMIO_WO_DATA_WIDTH);
    end
    // synthesis translate_on

    // We must be ready to accept either an MMIO write or read, without knowing which.
    assign host_mmio_req.tready = MMIO_DATA_WIDTH_LEGAL &&
                                  mmio_if.awready &&
                                  mmio_if.wready &&
                                  mmio_if.arready &&
                                  mmio_wo_if.awready &&
                                  mmio_wo_if.wready;

    // Convert a number of bytes to log2 for AXI size
    function automatic ofs_plat_axi_mem_pkg::t_axi_log2_beat_size mmio_log2_size(
        logic [11:0] n_bytes
        );
        ofs_plat_axi_mem_pkg::t_axi_log2_beat_size s;

        for (int i = 0; 2**i < n_bytes; i = i + 1)
        begin
            s = i + 1;
        end

        return s;
    endfunction

    // MMIO read request
    assign mmio_if.arvalid = host_mmio_req.tready && host_mmio_req.tvalid &&
                             !host_mmio_req.t.data.is_write;

    t_hc_axi_mmio_user_flags_with_vchan mmio_ar_flags;

    always_comb
    begin
        mmio_if.ar = '0;
        mmio_if.ar.id = { host_mmio_req.t.data.addr[2 +: MMIO_DWORD_IDX_BITS],
                          host_mmio_req.t.data.tag };
        mmio_if.ar.addr = t_mmio_addr'(host_mmio_req.t.data.addr);
        mmio_if.ar.size = mmio_log2_size(host_mmio_req.t.data.byte_count);

        mmio_ar_flags = '0;
        mmio_ar_flags.vchan = host_mmio_req.t.data.vchan;
`ifdef OFS_PLAT_HOST_CHAN_MULTIPLEXED
        mmio_if.ar.user = { '0, mmio_ar_flags };
`endif
    end

    // MMIO write request
    assign mmio_if.awvalid = host_mmio_req.tready && host_mmio_req.tvalid &&
                             host_mmio_req.t.data.is_write &&
                             (host_mmio_req.t.data.byte_count <= (MMIO_DATA_WIDTH / 8));
    assign mmio_if.wvalid = mmio_if.awvalid;

    t_mmio_data mmio_if_wdata;
    logic [MMIO_DATA_WIDTH/8-1 : 0] mmio_if_wstrb;
    t_hc_axi_mmio_user_flags_with_vchan mmio_aw_flags;

    always_comb
    begin
        mmio_if.aw = '0;
        mmio_if.aw.addr = t_mmio_addr'(host_mmio_req.t.data.addr);
        mmio_if.aw.size = mmio_log2_size(host_mmio_req.t.data.byte_count);

        mmio_if.w = '0;
        mmio_if.w.data = mmio_if_wdata;
        mmio_if.w.strb = mmio_if_wstrb;

        mmio_aw_flags = '0;
        mmio_aw_flags.vchan = host_mmio_req.t.data.vchan;
`ifdef OFS_PLAT_HOST_CHAN_MULTIPLEXED
        mmio_if.aw.user = { '0, mmio_aw_flags };
        mmio_if.w.user = { '0, mmio_aw_flags };
`endif
    end

    // Reformat MMIO write data and mask for AXI
    ofs_plat_host_chan_mmio_wr_data_comb
      #(
        .DATA_WIDTH(MMIO_DATA_WIDTH)
        )
      mmio_data
       (
        .byte_addr(host_mmio_req.t.data.addr),
        .byte_count(host_mmio_req.t.data.byte_count),
        .payload_in(MMIO_DATA_WIDTH'(host_mmio_req.t.data.payload)),

        .payload_out(mmio_if_wdata),
        .byte_mask(mmio_if_wstrb)
        );

    assign mmio_wo_if.awvalid = host_mmio_req.tready && host_mmio_req.tvalid &&
                                host_mmio_req.t.data.is_write &&
                                (host_mmio_req.t.data.byte_count <= (MMIO_WO_DATA_WIDTH / 8));
    assign mmio_wo_if.wvalid = mmio_wo_if.awvalid;

    t_mmio_wo_data mmio_wo_if_wdata;
    logic [MMIO_WO_DATA_WIDTH/8-1 : 0] mmio_wo_if_wstrb;

    always_comb
    begin
        mmio_wo_if.aw = '0;
        mmio_wo_if.aw.addr = t_mmio_wo_addr'(host_mmio_req.t.data.addr);
        mmio_wo_if.aw.size = mmio_log2_size(host_mmio_req.t.data.byte_count);

        mmio_wo_if.w = '0;
        mmio_wo_if.w.data = mmio_wo_if_wdata;
        mmio_wo_if.w.strb = mmio_wo_if_wstrb;

`ifdef OFS_PLAT_HOST_CHAN_MULTIPLEXED
        mmio_wo_if.aw.user = { '0, mmio_aw_flags };
        mmio_wo_if.w.user = { '0, mmio_aw_flags };
`endif
    end

    // Reformat MMIO write data and mask for AXI on the write-only channel
    ofs_plat_host_chan_mmio_wr_data_comb
      #(
        .DATA_WIDTH(MMIO_WO_DATA_WIDTH)
        )
      mmio_wo_data
       (
        .byte_addr(host_mmio_req.t.data.addr),
        .byte_count(host_mmio_req.t.data.byte_count),
        .payload_in(MMIO_WO_DATA_WIDTH'(host_mmio_req.t.data.payload)),

        .payload_out(mmio_wo_if_wdata),
        .byte_mask(mmio_wo_if_wstrb)
        );

    // AFU responses (t_gen_tx_mmio_afu_rsp)
    `AXI_STREAM_INSTANCE(host_mmio_rsp, t_gen_tx_mmio_afu_rsp);

    assign mmio_if.rready = !host_mmio_rsp.tvalid || host_mmio_rsp.tready;

    // Split RID into dword index and tag
    t_mmio_rd_tag mmio_rid;
    t_mmio_dword_idx mmio_r_dword_idx;
    assign { mmio_r_dword_idx, mmio_rid } = mmio_if.r.id;

    // Shift MMIO read responses that are smaller than the bus width into the
    // proper position.
    t_mmio_data mmio_r_data;

    ofs_plat_prim_rshift_words_comb
      #(
        .DATA_WIDTH(MMIO_DATA_WIDTH),
        .WORD_WIDTH(32)
        )
      mmio_r_data_shift
       (
        .d_in(mmio_if.r.data),
        .rshift_cnt(mmio_r_dword_idx),
        .d_out(mmio_r_data)
        );

    always_ff @(posedge clk)
    begin
        if (mmio_if.rready)
        begin
            host_mmio_rsp.tvalid <= mmio_if.rvalid;
            host_mmio_rsp.t.data.tag <= mmio_rid;
            host_mmio_rsp.t.data.payload <= { '0, mmio_r_data };
            // No need to return the PF/VF vchan here. The TLP mapper records
            // it, indexed by the tag.
        end

        if (!reset_n)
        begin
            host_mmio_rsp.tvalid <= 1'b0;
        end
    end


    // ====================================================================
    //
    //  Manage AFU read requests and host completion responses
    //
    // ====================================================================

    // Read requests from AFU (t_gen_tx_afu_rd_req)
    `AXI_STREAM_INSTANCE(afu_rd_req, t_gen_tx_afu_rd_req);

    wire t_hc_axi_user_flags_with_vchan mem_if_ar_user =
        t_hc_axi_user_flags_with_vchan'(mem_if.ar.user);

    assign afu_rd_req.tvalid = mem_if.arvalid;
    assign mem_if.arready = afu_rd_req.tready;
    assign afu_rd_req.t.data.tag = { '0, mem_if.ar.id };
    assign afu_rd_req.t.data.line_count = t_tlp_payload_line_count'(mem_if.ar.len) + 1;
    assign afu_rd_req.t.data.addr = { '0, mem_if.ar.addr };
    // Atomic reads are generated inside the PIM to match an atomic write.
    // They allocate IDs in the read pipeline so that the response appears
    // to target a normal read request.
    assign afu_rd_req.t.data.is_atomic = mem_if_ar_user.base.atomic;
`ifdef OFS_PLAT_HOST_CHAN_MULTIPLEXED
    assign afu_rd_req.t.data.vchan = mem_if_ar_user.vchan;
`else
    assign afu_rd_req.t.data.vchan = '0;
`endif

    // Read responses to AFU (t_gen_tx_afu_rd_rsp)
    `AXI_STREAM_INSTANCE(afu_rd_rsp, t_gen_tx_afu_rd_rsp);
    assign afu_rd_rsp.tready = mem_if.rready;
    assign mem_if.rvalid = afu_rd_rsp.tvalid;
    always_comb
    begin
        mem_if.r = '0;

        // Index of the ROB entry. Inside the PIM we violate the AXI-MM standard
        // by adding the line index to the tag in order to form a unique ROB
        // index. By the time a response gets to the AFU, the RID will be valid
        // and conform to AXI-MM.
        mem_if.r.id = afu_rd_rsp.t.data.tag + afu_rd_rsp.t.data.line_idx;
        mem_if.r.last = afu_rd_rsp.t.data.last;

        // The initial block below will trigger a fatal error if not 1 or 2
        if (NUM_PAYLOAD_RCB_SEGS == 1)
        begin
            // Simple case: bus width is <= read completion boundary
            mem_if.r.data = afu_rd_rsp.t.data.payload;
        end
        else if (NUM_PAYLOAD_RCB_SEGS == 2)
        begin
            // RCB is 2x bus width -- typically a 1024 bit bus

            // If the start address of the completion is in the middle of
            // the bus then swap the high and low payload halves. The
            // swap realigns the data to match the expected position on
            // the payload bus.
            mem_if.r.data =
                ~afu_rd_rsp.t.data.rcb_idx[0] ?
                    afu_rd_rsp.t.data.payload :
                    { afu_rd_rsp.t.data.payload[0 +: PAYLOAD_LINE_SIZE/2],
                      afu_rd_rsp.t.data.payload[PAYLOAD_LINE_SIZE/2 +: PAYLOAD_LINE_SIZE/2] };

            // User bits on the "r" bus here are unused. They will be
            // overwritten in the PIM with the user bits from "ar".
            // Inside the PIM, use the low user bits to mark valid RCB
            // segments.

            // Bit 0: low half of payload is valid
            mem_if.r.user[0] =
                ~afu_rd_rsp.t.data.num_rcb_seg_valid[0] || ~afu_rd_rsp.t.data.rcb_idx[0];
            // Bit 1: high half of payload is valid
            mem_if.r.user[1] =
                ~afu_rd_rsp.t.data.num_rcb_seg_valid[0] || afu_rd_rsp.t.data.rcb_idx[0];
            // Bit 2: payload begins in the high half. If the low half
            // is valid, its ROB index is mem_if.r.id + 1.
            mem_if.r.user[2] = afu_rd_rsp.t.data.rcb_idx[0];
        end
    end

    // synthesis translate_off
    initial
    begin
        // The code above only works either when the read completion boundary
        // is larger than the bus width or when there are exactly two RCB
        // segments in the bus. Normally this means that either the bus
        // width is <= 512 bits or is exactly 1024 bits.
        if (NUM_PAYLOAD_RCB_SEGS > 2)
            $fatal(2, "** ERROR ** %m: At most 2 RCB segments are allowed (%0d)", NUM_PAYLOAD_RCB_SEGS);

        if ($bits(mem_if.r.user) < NUM_PAYLOAD_RCB_SEGS*2-1) begin
            $fatal(2, "** ERROR ** %m: mem_if.r.user field is too small (%0d) for RCB info (%0d)",
                   $bits(mem_if.r.user), NUM_PAYLOAD_RCB_SEGS);
        end
    end
    // synthesis translate_on

    // ====================================================================
    //
    //  Manage AFU write requests
    //
    // ====================================================================

    localparam ADDR_WIDTH = mem_source.ADDR_WIDTH;
    typedef logic [ADDR_WIDTH-1 : 0] t_addr;
    localparam DATA_WIDTH = mem_source.DATA_WIDTH;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    // Mapping byte masks to start and length needs to be broken apart
    // for timing. This first stage uses a FIFO in parallel with the
    // mem_if.w skid buffer to store start and end indices.
    t_tlp_payload_line_byte_idx w_byte_start_in_A, w_byte_end_in_A;
    logic w_byte_start_in_A_valid, w_byte_end_in_A_valid;
    t_tlp_payload_line_byte_idx w_byte_start_in_B, w_byte_end_in_B;
    t_tlp_payload_line_byte_idx w_byte_start, w_byte_end;

    // Reduce the depth of the search circuit by searching half the strb
    // bits in group A and half in B, then pick the first with a valid bit.
    always_comb
    begin
        w_byte_start_in_A = '0;
        w_byte_start_in_A_valid = 1'b0;
        for (int i = 0; i < DATA_WIDTH/16; i = i + 1)
        begin
            if (mem_source.w.strb[i])
            begin
                w_byte_start_in_A = i;
                w_byte_start_in_A_valid = 1'b1;
                break;
            end
        end

        w_byte_start_in_B = '0;
        for (int i = DATA_WIDTH/16; i < DATA_WIDTH/8; i = i + 1)
        begin
            if (mem_source.w.strb[i])
            begin
                w_byte_start_in_B = i;
                break;
            end
        end

        w_byte_end_in_A = ~'0;
        w_byte_end_in_A_valid = 1'b0;
        for (int i = DATA_WIDTH/8 - 1; i >= DATA_WIDTH/16; i = i - 1)
        begin
            if (mem_source.w.strb[i])
            begin
                w_byte_end_in_A = i;
                w_byte_end_in_A_valid = 1'b1;
                break;
            end
        end

        w_byte_end_in_B = ~'0;
        for (int i = DATA_WIDTH/16 - 1; i >= 0; i = i - 1)
        begin
            if (mem_source.w.strb[i])
            begin
                w_byte_end_in_B = i;
                break;
            end
        end
    end

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(2 * $bits(t_tlp_payload_line_byte_idx))
        )
      byte_range_idx
       (
        .clk,
        .reset_n,

        .enq_data({ w_byte_start_in_A_valid ? w_byte_start_in_A : w_byte_start_in_B,
                    w_byte_end_in_A_valid ? w_byte_end_in_A : w_byte_end_in_B }),
        .enq_en(mem_source.wvalid && mem_source.wready),
        // Space is the same as the mem_if.w skid buffer
        .notFull(),

        .first({ w_byte_start, w_byte_end }),
        .deq_en(mem_if.wvalid && mem_if.wready),
        .notEmpty()
        );

    // Write requests from AFU (t_gen_tx_afu_wr_req)
    `AXI_STREAM_INSTANCE(afu_wr_req, t_gen_tx_afu_wr_req);

    logic wr_is_sop;

    always_ff @(posedge clk)
    begin
        if (afu_wr_req.tready && afu_wr_req.tvalid)
        begin
            wr_is_sop <= afu_wr_req.t.data.eop;
        end

        if (!reset_n)
        begin
            wr_is_sop <= 1'b1;
        end
    end

    // The write data channel is needed for every message. The write address
    // channel is needed only on SOP.
    assign mem_if.awready = wr_is_sop && mem_if.wvalid && afu_wr_req.tready;
    assign mem_if.wready = (!wr_is_sop || mem_if.awvalid) && afu_wr_req.tready;
    assign afu_wr_req.tvalid = (!wr_is_sop || mem_if.awvalid) && mem_if.wvalid;

    wire t_hc_axi_user_flags_with_vchan mem_if_aw_user =
        t_hc_axi_user_flags_with_vchan'(mem_if.aw.user);

    always_comb
    begin
        afu_wr_req.t.data = '0;

        afu_wr_req.t.data.sop = wr_is_sop;
        afu_wr_req.t.data.eop = mem_if.w.last;

        if (wr_is_sop)
        begin
`ifdef OFS_PLAT_HOST_CHAN_MULTIPLEXED
            afu_wr_req.t.data.vchan = mem_if_aw_user.vchan;
`endif

            afu_wr_req.t.data.is_fence = mem_if_aw_user.base.fence;
            afu_wr_req.t.data.is_interrupt = mem_if_aw_user.base.interrupt;

            afu_wr_req.t.data.is_atomic = mem_if_aw_user.base.atomic;
            if (mem_if.aw.atop == ofs_plat_axi_mem_pkg::ATOMIC_ADD)
                afu_wr_req.t.data.atomic_op = TLP_ATOMIC_FADD;
            else if (mem_if.aw.atop == ofs_plat_axi_mem_pkg::ATOMIC_SWAP)
                afu_wr_req.t.data.atomic_op = TLP_ATOMIC_SWAP;
            else if (mem_if.aw.atop == ofs_plat_axi_mem_pkg::ATOMIC_CAS)
                afu_wr_req.t.data.atomic_op = TLP_ATOMIC_CAS;
            else
                afu_wr_req.t.data.atomic_op = TLP_NOT_ATOMIC;

            // If either the first or the last mask bit is 0 then write only
            // a portion of the line. This is supported only for simple line requests.
            if ((!mem_if.w.strb[0] || !mem_if.w.strb[DATA_WIDTH/8-1]) &&
                (mem_if.aw.len == 0) &&
                !afu_wr_req.t.data.is_fence &&
                !afu_wr_req.t.data.is_interrupt)
            begin
                afu_wr_req.t.data.enable_byte_range = 1'b1;
                afu_wr_req.t.data.byte_start_idx = w_byte_start;
                afu_wr_req.t.data.byte_len = w_byte_end - w_byte_start + 1;
            end

            afu_wr_req.t.data.line_count = t_tlp_payload_line_count'(mem_if.aw.len) + 1;
            afu_wr_req.t.data.addr = { '0, mem_if.aw.addr };
            afu_wr_req.t.data.tag = { '0, mem_if.aw.id };

            if (afu_wr_req.t.data.is_interrupt)
            begin
                // Our AXI-MM protocol stores the interrupt ID in the low bits
                // of aw.addr.
                afu_wr_req.t.data.tag = { '0, t_interrupt_idx'(mem_if.aw.addr) };
            end
        end

        afu_wr_req.t.data.payload = mem_if.w.data;
    end

    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n && afu_wr_req.tvalid && afu_wr_req.tready && afu_wr_req.t.data.is_atomic)
        begin
`ifndef OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_ATOMICS
            $fatal(2, "** ERROR ** %m: Platform does not support atomic requests!");
`endif
            assert (afu_wr_req.t.data.atomic_op != TLP_NOT_ATOMIC) else
              $fatal(2, "** ERROR ** %m: Atomic op 0x%h not supported!", mem_if.aw.atop);

            if (afu_wr_req.t.data.atomic_op == TLP_ATOMIC_CAS)
            begin
                assert ((afu_wr_req.t.data.byte_len == 8) || (afu_wr_req.t.data.byte_len == 16)) else
                  $fatal(2, "** ERROR ** %m: Atomic CAS must be either 8 or 16 bytes, not %0d!", afu_wr_req.t.data.byte_len);
            end
            else
            begin
                assert ((afu_wr_req.t.data.byte_len == 4) || (afu_wr_req.t.data.byte_len == 8)) else
                  $fatal(2, "** ERROR ** %m: Atomic op must be either 4 or 8 bytes, not %0d!", afu_wr_req.t.data.byte_len);
            end
        end
    end
    // synthesis translate_on

    // Preserve AWID from interrupt requests so responses can be tagged properly
    // on return to the AFU. (Interrupts use the same AWID space is normal writes
    // in our encoding.)
    logic [mem_if.WID_WIDTH-1:0] intrWID[NUM_AFU_INTERRUPTS];

    always_ff @(posedge clk)
    begin
        if (afu_wr_req.tready && afu_wr_req.tvalid && afu_wr_req.t.data.is_interrupt)
        begin
            intrWID[t_interrupt_idx'(mem_if.aw.addr)] <= mem_if.aw.id;
        end
    end

    // Write responses to AFU once the packet is completely sent (t_gen_tx_afu_wr_rsp)
    `AXI_STREAM_INSTANCE(afu_wr_rsp, t_gen_tx_afu_wr_rsp);

    t_hc_axi_user_flags_with_vchan mem_if_b_user;

    assign afu_wr_rsp.tready = mem_if.bready;
    assign mem_if.bvalid = afu_wr_rsp.tvalid;

    always_comb
    begin
        mem_if.b = '0;
        mem_if.b.id = afu_wr_rsp.t.data.tag;

        mem_if_b_user = '0;
        mem_if_b_user.vchan = afu_wr_rsp.t.data.vchan;
`ifdef OFS_PLAT_HOST_CHAN_MULTIPLEXED
        mem_if.b.user = mem_if_b_user;
`endif

        // Restore transaction ID for interrupts. (The response tag is the
        // interrupt index, not the transaction ID.)
        if (afu_wr_rsp.t.data.is_interrupt)
        begin
            mem_if.b.id = intrWID[t_interrupt_idx'(afu_wr_rsp.t.data.tag)];
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
        .allow_dm_enc,

        .host_mmio_req,
        .host_mmio_rsp,

        .afu_rd_req,
        .afu_rd_rsp,

        .afu_wr_req,
        .afu_wr_rsp
        );

endmodule // ofs_plat_host_chan_@group@_map_as_axi_mem_if
