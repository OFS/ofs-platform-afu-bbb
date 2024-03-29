// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export a platform host_chan interface to an AFU as CCI-P.
//
// The "as CCI-P" abstraction here allows an AFU to request the host connection
// using a particular interface. The platform may offer multiple interfaces
// to the same underlying PR wires, instantiating protocol conversion
// shims as needed.
//

//
// This version of ofs_plat_host_chan_as_ccip works only on platforms
// where the native interface is Avalon.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_as_ccip
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // These are present so the interface is consistent across native
    // interfaces. The Avalon native interface is already sorted, so
    // the parameters will be ignored.
    parameter SORT_READ_RESPONSES = 0,
    parameter SORT_WRITE_RESPONSES = 0
    )
   (
    ofs_plat_avalon_mem_if.to_sink to_fiu,
    ofs_plat_host_ccip_if.to_afu to_afu,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    // Apply clock crossing and burst mapping to the Avalon sink.
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_MEM_PARAMS(to_fiu),
        .BURST_CNT_WIDTH(3)
        )
      afu_avmm_if();

    ofs_plat_host_chan_@group@_as_avalon_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      avmm
       (
        .to_fiu,
        .host_mem_to_afu(afu_avmm_if),
        .afu_clk,
        .afu_reset_n
        );

    // Export the simple Avalon interface as a split-bus interface.
    // passing the clock.
    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(afu_avmm_if)
        )
      afu_avmm_rdwr_if();

    ofs_plat_avalon_mem_rdwr_if_to_mem_if gen_rdwr
       (
        .mem_sink(afu_avmm_if),
        .mem_source(afu_avmm_rdwr_if)
        );

    assign afu_avmm_rdwr_if.clk = afu_avmm_if.clk;
    assign afu_avmm_rdwr_if.reset_n = afu_avmm_if.reset_n;
    assign afu_avmm_rdwr_if.instance_number = afu_avmm_if.instance_number;

    wire clk;
    assign clk = afu_avmm_rdwr_if.clk;
    assign to_afu.clk = clk;

    logic reset_n;
    assign reset_n = afu_avmm_rdwr_if.reset_n;
    assign to_afu.reset_n = reset_n;


    //
    // CCI-P reads (c0)
    //
    localparam C0_TRACKER_DEPTH = ccip_@group@_cfg_pkg::C0_MAX_BW_ACTIVE_LINES[0];

    t_if_ccip_c0_Tx afu_c0Tx;
    logic afu_c0Tx_notEmpty;
    logic afu_c0Tx_deq_en;
    logic afu_c0Tx_tracker_notFull;

    // Buffer AFU-generated requests to satisfy the CCI-P almostFull protocol
    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_if_ccip_c0_Tx)),
        .N_ENTRIES(CCIP_TX_ALMOST_FULL_THRESHOLD + 4),
        .THRESHOLD(CCIP_TX_ALMOST_FULL_THRESHOLD),
        .REGISTER_OUTPUT(1)
        )
      fifo_c0_in
       (
        .clk,
        .reset_n,
        .enq_data(to_afu.sTx.c0),
        .enq_en(to_afu.sTx.c0.valid),
        .notFull(),
        .almostFull(to_afu.sRx.c0TxAlmFull),
        .first(afu_c0Tx),
        .deq_en(afu_c0Tx_deq_en),
        .notEmpty(afu_c0Tx_notEmpty)
        );

    // Map CCI-P read request to AVMM request
    assign afu_avmm_rdwr_if.rd_read = afu_c0Tx_notEmpty && afu_c0Tx_tracker_notFull;
    assign afu_c0Tx_deq_en = afu_avmm_rdwr_if.rd_read && ! afu_avmm_rdwr_if.rd_waitrequest;

    always_comb
    begin
        afu_avmm_rdwr_if.rd_address = afu_c0Tx.hdr.address;
        afu_avmm_rdwr_if.rd_burstcount = 3'(afu_c0Tx.hdr.cl_len) + 3'b1;
        afu_avmm_rdwr_if.rd_byteenable = ~'0;
    end

    // Track read bursts in flight, required to fill in CCI-P details in responses
    logic afu_c0Rx_deq_en;
    t_ccip_clLen afu_c0Rx_cl_len;
    t_ccip_mdata afu_c0Rx_mdata;

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS($bits(t_ccip_clLen) + $bits(t_ccip_mdata)),
        .N_ENTRIES(C0_TRACKER_DEPTH)
        )
      fifo_c0_track
       (
        .clk,
        .reset_n,
        .enq_data({ afu_c0Tx.hdr.cl_len, afu_c0Tx.hdr.mdata }),
        .enq_en(afu_c0Tx_deq_en),
        .notFull(afu_c0Tx_tracker_notFull),
        .almostFull(),
        .first({ afu_c0Rx_cl_len, afu_c0Rx_mdata }),
        .deq_en(afu_c0Rx_deq_en),
        .notEmpty()
        );

    // Read responses
    t_ccip_clNum afu_c0Rx_cl_num;

    // Pop the oldest tracker entry when all response flits for the packet
    // are processed.
    assign afu_c0Rx_deq_en = afu_avmm_rdwr_if.rd_readdatavalid &&
                             (afu_c0Rx_cl_num == t_ccip_clNum'(afu_c0Rx_cl_len));

    // Map Avalon read responses back to AFU CCI-P responses
    always_ff @(posedge clk)
    begin
        to_afu.sRx.c0.rspValid <= afu_avmm_rdwr_if.rd_readdatavalid;
        to_afu.sRx.c0.data <= afu_avmm_rdwr_if.rd_readdata;

        to_afu.sRx.c0.hdr <= '0;
        to_afu.sRx.c0.hdr.cl_num <= afu_c0Rx_cl_num;
        to_afu.sRx.c0.hdr.mdata <= afu_c0Rx_mdata;

        // MMIO not supported
        to_afu.sRx.c0.mmioRdValid <= 1'b0;
        to_afu.sRx.c0.mmioWrValid <= 1'b0;

        if (afu_c0Rx_deq_en)
        begin
            // Finished the current packet
            afu_c0Rx_cl_num <= t_ccip_clNum'(0);
        end
        else if (afu_avmm_rdwr_if.rd_readdatavalid)
        begin
            afu_c0Rx_cl_num <= afu_c0Rx_cl_num + t_ccip_clNum'(1);
        end

        if (!reset_n)
        begin
            to_afu.sRx.c0.rspValid <= 1'b0;
            afu_c0Rx_cl_num <= t_ccip_clNum'(0);
        end
    end


    //
    // CCI-P writes (c1)
    //
    localparam C1_TRACKER_DEPTH = ccip_@group@_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0];

    t_if_ccip_c1_Tx afu_c1Tx;
    logic afu_c1Tx_notEmpty;
    logic afu_c1Tx_deq_en;
    logic afu_c1Tx_tracker_notFull;
    t_ccip_clByteIdx afu_c1Tx_byte_end;

    // Buffer AFU-generated requests to satisfy the CCI-P almostFull protocol.
    // The sum of byte_start and byte_len is computed on entry to the FIFO
    // because it will be needed in a critical path later.
    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_ccip_clByteIdx) + $bits(t_if_ccip_c1_Tx)),
        .N_ENTRIES(CCIP_TX_ALMOST_FULL_THRESHOLD + 4),
        .THRESHOLD(CCIP_TX_ALMOST_FULL_THRESHOLD),
        .REGISTER_OUTPUT(1)
        )
      fifo_c1_in
       (
        .clk,
        .reset_n,
        .enq_data({ to_afu.sTx.c1.hdr.byte_start + to_afu.sTx.c1.hdr.byte_len,
                    to_afu.sTx.c1 }),
        .enq_en(to_afu.sTx.c1.valid),
        .notFull(),
        .almostFull(to_afu.sRx.c1TxAlmFull),
        .first({ afu_c1Tx_byte_end, afu_c1Tx }),
        .deq_en(afu_c1Tx_deq_en),
        .notEmpty(afu_c1Tx_notEmpty)
        );

    // Convert CCI-P start/end byte mask to Avalon byteenable
    logic [CCIP_CLDATA_BYTE_WIDTH-1 : 0] afu_c1Tx_byteenable;

    ofs_plat_utils_ccip_gen_bmask c1_bmask
       (
        .byte_start(afu_c1Tx.hdr.byte_start),
        .byte_start_plus_len(afu_c1Tx_byte_end),
        .bmask(afu_c1Tx_byteenable)
        );

    // Map CCI-P write request to AVMM request
    assign afu_avmm_rdwr_if.wr_write = afu_c1Tx_notEmpty && afu_c1Tx_tracker_notFull;
    assign afu_c1Tx_deq_en = afu_avmm_rdwr_if.wr_write && ! afu_avmm_rdwr_if.wr_waitrequest;

    always_comb
    begin
        afu_avmm_rdwr_if.wr_writedata = afu_c1Tx.data;
        afu_avmm_rdwr_if.wr_address = afu_c1Tx.hdr.address;
        afu_avmm_rdwr_if.wr_burstcount = 3'(afu_c1Tx.hdr.cl_len) + 3'b1;
        afu_avmm_rdwr_if.wr_byteenable = afu_c1Tx.hdr.mode ? afu_c1Tx_byteenable : ~'0;

        afu_avmm_rdwr_if.wr_user = '0;
        if (afu_c1Tx.hdr.req_type == eREQ_WRFENCE)
        begin
            // Use AVMM special fence encoding
            afu_avmm_rdwr_if.wr_address = '0;
            afu_avmm_rdwr_if.wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_FENCE] = 1'b1;
        end
    end

    // Track in-flight state that will be needed to fill in CCI-P responses.
    logic afu_c1_track_enq_en;
    logic afu_c1Rx_deq_en;
    logic afu_c1Rx_isFence;
    t_ccip_clNum afu_c1Rx_cl_num;
    t_ccip_mdata afu_c1Rx_mdata;

    // Track write bursts, not individual flits
    assign afu_c1_track_enq_en =
        afu_c1Tx_deq_en &&
        (afu_c1Tx.hdr.sop || (afu_c1Tx.hdr.req_type == eREQ_WRFENCE));

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(1 + $bits(t_ccip_clNum) + $bits(t_ccip_mdata)),
        .N_ENTRIES(C1_TRACKER_DEPTH)
        )
      fifo_c1_track
       (
        .clk,
        .reset_n,
        .enq_data({ afu_c1Tx.hdr.req_type == eREQ_WRFENCE,
                    t_ccip_clNum'(afu_c1Tx.hdr.cl_len),
                    afu_c1Tx.hdr.mdata }),
        .enq_en(afu_c1_track_enq_en),
        .notFull(afu_c1Tx_tracker_notFull),
        .almostFull(),
        .first({ afu_c1Rx_isFence, afu_c1Rx_cl_num, afu_c1Rx_mdata }),
        .deq_en(afu_c1Rx_deq_en),
        .notEmpty()
        );

    // Write responses. AVMM gives a single response for a burst.
    assign afu_c1Rx_deq_en = afu_avmm_rdwr_if.wr_writeresponsevalid;

    always_ff @(posedge clk)
    begin
        to_afu.sRx.c1.rspValid <= afu_avmm_rdwr_if.wr_writeresponsevalid;

        to_afu.sRx.c1.hdr <= '0;
        to_afu.sRx.c1.hdr.format <= 1'b1;
        to_afu.sRx.c1.hdr.cl_num <= afu_c1Rx_cl_num;
        to_afu.sRx.c1.hdr.resp_type <= afu_c1Rx_isFence ? eRSP_WRFENCE : eRSP_WRLINE;
        to_afu.sRx.c1.hdr.mdata <= afu_c1Rx_mdata;

        if (!reset_n)
        begin
            to_afu.sRx.c1.rspValid <= 1'b0;
        end
    end


    //
    // MMIO read response (c2)
    //

    // synthesis translate_off
    always_ff @(posedge clk)
    begin
        if (reset_n && to_afu.sTx.c2.mmioRdValid)
            $fatal(2, "** ERROR ** %m: MMIO read not supported in native AVMM host channels!");
    end
    // synthesis translate_on

endmodule // ofs_plat_host_chan_@group@_as_ccip
