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
    ofs_plat_axi_mem_lite_if.to_master mmio_if,

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

    // Registers so write data and address can be held until both arrive
    logic mmio_wr_addr_valid, mmio_wr_data_valid;
    t_mmio_addr mmio_wr_addr;
    t_mmio_data mmio_wr_data;
    logic [mmio_if.WID_WIDTH-1 : 0] mmio_wr_id;
    logic [mmio_if.USER_WIDTH-1 : 0] mmio_wr_user;

    // Flow control -- prevent overwriting of registered data or address
    assign mmio_if.awready = !mmio_wr_addr_valid;
    assign mmio_if.wready = !mmio_wr_data_valid;

    logic process_mmio_wr;
    assign process_mmio_wr = mmio_wr_addr_valid && mmio_wr_data_valid &&
                             mmio_if.bready;

    always_ff @(posedge clk)
    begin
        // Receive address
        if (!mmio_wr_addr_valid && mmio_if.awvalid)
        begin
            mmio_wr_addr_valid <= 1'b1;
            mmio_wr_addr <= mmio_if.aw.addr[MMIO_ADDR_START_BIT +: MMIO_ADDR_WIDTH];
            mmio_wr_id <= mmio_if.aw.id;
            mmio_wr_user <= mmio_if.aw.user;
        end

        // Receive data
        if (!mmio_wr_data_valid && mmio_if.wvalid)
        begin
            mmio_wr_data_valid <= 1'b1;
            mmio_wr_data <= mmio_if.w.data;
        end

        // Pass write to CSR manager when data and address have arrived
        if (process_mmio_wr)
        begin
            mmio_wr_addr_valid <= 1'b0;
            mmio_wr_data_valid <= 1'b0;
        end

        if (!reset_n)
        begin
            mmio_wr_addr_valid <= 1'b0;
            mmio_wr_data_valid <= 1'b0;
        end
    end

    // Read tracking. Since the AXI read response path may have flow control,
    // the logic here allows only one read request to be in flight within
    // the CSR manager.
    logic mmio_rd_busy, mmio_rd_valid, mmio_rd_valid_reg;
    t_mmio_data mmio_rd_data, mmio_rd_data_reg;
    logic [mmio_if.RID_WIDTH-1 : 0] mmio_rd_id, mmio_rd_id_reg;
    logic [mmio_if.USER_WIDTH-1 : 0] mmio_rd_user, mmio_rd_user_reg;

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

        .wr_write(process_mmio_wr),
        .wr_address(mmio_wr_addr),
        .wr_writedata(mmio_wr_data),

        .rd_read(mmio_if.arvalid && !mmio_rd_busy),
        .rd_address(mmio_if.ar.addr[MMIO_ADDR_START_BIT +: MMIO_ADDR_WIDTH]),
        .rd_tid_in({ mmio_if.ar.user, mmio_if.ar.id }),
        .rd_readdatavalid(mmio_rd_valid),
        .rd_readdata(mmio_rd_data),
        .rd_tid_out({ mmio_rd_user, mmio_rd_id }),

        .eng_csr_glob,
        .eng_csr
        );

    // Only one read in flight at a time. This will be held until the master
    // accepts a response.
    assign mmio_if.arready = !mmio_rd_busy;

    // Register and hold read responses until the master accepts them.
    always_ff @(posedge clk)
    begin
        // Only one read request at a time
        if (mmio_if.arvalid && !mmio_rd_busy)
        begin
            mmio_rd_busy <= 1'b1;
        end

        // Available response accepted?
        if (mmio_rd_valid_reg && mmio_if.rready)
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

    // Read response to master
    assign mmio_if.rvalid = mmio_rd_valid_reg;
    always_comb
    begin
        mmio_if.r = '0;
        mmio_if.r.data = mmio_rd_data_reg;
        mmio_if.r.id = mmio_rd_id_reg;
        mmio_if.r.user = mmio_rd_user_reg;
    end

    // Write response to master
    assign mmio_if.bvalid = process_mmio_wr;
    always_comb
    begin
        mmio_if.b = '0;
        mmio_if.b.id = mmio_wr_id;
        mmio_if.b.user = mmio_wr_user;
    end

endmodule // csr_mgr_axi
