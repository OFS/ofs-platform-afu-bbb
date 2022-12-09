// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Unlike Avalon and CCI-P, AXI lite is so complicated it needs a wrapper
// around the CSR manager to handle split address and data buses and
// response flow control.
//

module csr_mgr_axi
  #(
    parameter NUM_ENGINES = 1,
    parameter DFH_MMIO_NEXT_ADDR = 0
    )
   (
    // CSR read and write commands from the host
    ofs_plat_axi_mem_lite_if.to_source mmio_if,

    // Passing in pClk allows us to compute the frequency of clk given a
    // known pClk frequency.
    input  logic pClk,

    // Global engine interface (write only)
    engine_csr_if.csr_mgr eng_csr_glob,

    // Individual engine CSRs
    engine_csr_if.csr_mgr eng_csr[NUM_ENGINES]
    );

    logic clk;
    assign clk = mmio_if.clk;

    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= mmio_if.reset_n;
    end

    localparam MMIO_DATA_WIDTH = mmio_if.DATA_WIDTH;
    typedef logic [MMIO_DATA_WIDTH-1 : 0] t_mmio_data;

    // Drop low bits to address native CSR width
    localparam MMIO_ADDR_START_BIT = $clog2(MMIO_DATA_WIDTH / 8);
    localparam MMIO_ADDR_WIDTH = mmio_if.ADDR_WIDTH - MMIO_ADDR_START_BIT;
    typedef logic [MMIO_ADDR_WIDTH-1 : 0] t_mmio_addr;

    //
    // Pass the MMIO channels through skid buffers. The skid buffer module
    // also can be configured to make the AXI channel behavior more amenable
    // to use with CSRs:
    //
    //   - AW and W are guaranteed to be synchronized.
    //   - Only one of AW/W and AR may fire in a single cycle.
    //
    // In this mode, the AXI bus behaves much like Avalon memory.
    //

    //
    // Add skid buffers for timing.
    //
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_if)
        )
      mmio_skid();

    assign mmio_skid.clk = mmio_if.clk;
    assign mmio_skid.reset_n = mmio_if.reset_n;
    assign mmio_skid.instance_number = mmio_if.instance_number;

    ofs_plat_axi_mem_lite_if_skid afu_mmio_skid
       (
        .mem_source(mmio_if),
        .mem_sink(mmio_skid)
        );

    //
    // Change the behavior of the AXI channels to map more easily to CSRs.
    // The PIM provides a module that makes AXI lite more like Avalon:
    // AW and W are tied together and only a read or write request may
    // be valid but not both.
    //
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_if)
        )
      mmio_sync();

    assign mmio_sync.clk = mmio_skid.clk;
    assign mmio_sync.reset_n = mmio_skid.reset_n;
    assign mmio_sync.instance_number = mmio_skid.instance_number;

    ofs_plat_axi_mem_lite_if_sync
      #(
        .NO_SIMULTANEOUS_RW(1)
        )
      afu_mmio_sync
       (
        .mem_source(mmio_skid),
        .mem_sink(mmio_sync)
        );

    // Ready for writes as long as the response channel is ready. The
    // skid buffer module guarantees that bready is independent of bvalid.
    // The sync module guarantees that awvalid and wvalid are set together.
    logic do_write;
    assign do_write = mmio_sync.awvalid && mmio_sync.bready;
    assign mmio_sync.awready = mmio_sync.bready;
    assign mmio_sync.wready = mmio_sync.bready;

    logic mmio_rd_busy, mmio_rd_valid, mmio_rd_valid_reg;
    t_mmio_data mmio_rd_data, mmio_rd_data_reg;
    logic [mmio_if.RID_WIDTH-1 : 0] mmio_rd_id, mmio_rd_id_reg;
    logic [mmio_if.USER_WIDTH-1 : 0] mmio_rd_user, mmio_rd_user_reg;

    // Only one read in flight at a time. This will be held until the master
    // accepts a response.
    assign mmio_sync.arready = !mmio_rd_busy;

    csr_mgr
      #(
        .NUM_ENGINES(NUM_ENGINES),
        .DFH_MMIO_NEXT_ADDR(DFH_MMIO_NEXT_ADDR),
        .MMIO_ADDR_WIDTH(MMIO_ADDR_WIDTH),
        .MMIO_DATA_WIDTH(MMIO_DATA_WIDTH),
        .MMIO_TID_WIDTH(mmio_if.USER_WIDTH + mmio_if.RID_WIDTH)
        )
      csr_mgr
       (
        .clk,
        .reset_n,
        .pClk,

        .wr_write(do_write),
        .wr_address(mmio_sync.aw.addr[MMIO_ADDR_START_BIT +: MMIO_ADDR_WIDTH]),
        .wr_writedata(mmio_sync.w.data),

        .rd_read(mmio_sync.arvalid && !mmio_rd_busy),
        .rd_address(mmio_sync.ar.addr[MMIO_ADDR_START_BIT +: MMIO_ADDR_WIDTH]),
        .rd_tid_in({ mmio_sync.ar.user, mmio_sync.ar.id }),
        .rd_readdatavalid(mmio_rd_valid),
        .rd_readdata(mmio_rd_data),
        .rd_tid_out({ mmio_rd_user, mmio_rd_id }),

        .eng_csr_glob,
        .eng_csr
        );

    // Register and hold read responses until the master accepts them.
    always_ff @(posedge clk)
    begin
        // Only one read request at a time
        if (mmio_sync.arvalid)
        begin
            mmio_rd_busy <= 1'b1;
        end

        // Available response accepted?
        if (mmio_sync.rvalid && mmio_sync.rready)
        begin
            mmio_rd_valid_reg <= 1'b0;
            mmio_rd_busy <= 1'b0;
        end

        // New response?
        if (mmio_rd_valid)
        begin
            mmio_rd_valid_reg <= 1'b1;
            mmio_rd_data_reg <= mmio_rd_data;
            mmio_rd_id_reg <= mmio_rd_id;
            mmio_rd_user_reg <= mmio_rd_user;
        end

        if (!reset_n)
        begin
            mmio_rd_busy <= 1'b0;
            mmio_rd_valid_reg <= 1'b0;
        end
    end

    // Read response to source
    assign mmio_sync.rvalid = mmio_rd_valid_reg;
    always_comb
    begin
        mmio_sync.r = '0;
        mmio_sync.r.data = mmio_rd_data_reg;
        mmio_sync.r.id = mmio_rd_id_reg;
        mmio_sync.r.user = mmio_rd_user_reg;
    end

    // Write response to source
    assign mmio_sync.bvalid = do_write;
    always_comb
    begin
        mmio_sync.b = '0;
        mmio_sync.b.id = mmio_sync.aw.id;
        mmio_sync.b.user = mmio_sync.aw.user;
    end

endmodule // csr_mgr_axi
