// ***************************************************************************
// Copyright (c) 2013-2017, Intel Corporation
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
// * Neither the name of Intel Corporation nor the names of its contributors
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
// ***************************************************************************

`include "fpga_defines.vh"

//
// platform_if.vh defines many required components, including both top-level
// SystemVerilog interfaces and the platform/AFU configuration parameters
// required to match the interfaces offered by the platform to the needs
// of the AFU.
//
// Most preprocessor variables used in this file come from this.
//
`include "platform_if.vh"
`include "ofs_plat_if.vh"

`ifdef INCLUDE_ETHERNET
`include "pr_hssi_if.vh"
`endif
parameter CCIP_TXPORT_WIDTH = $bits(t_if_ccip_Tx);  // TODO: Move this to ccip_if_pkg
parameter CCIP_RXPORT_WIDTH = $bits(t_if_ccip_Rx);  // TODO: Move this to ccip_if_pkg

module green_bs
(
   // CCI-P Interface
   input   logic                         Clk_400,             // Core clock. CCI interface is synchronous to this clock.
   input   logic                         Clk_200,             // Core clock. CCI interface is synchronous to this clock.
   input   logic                         Clk_100,             // Core clock. CCI interface is synchronous to this clock.
   input   logic                         uClk_usr,
   input   logic                         uClk_usrDiv2,
   input   logic                         SoftReset,           // CCI interface reset. The Accelerator IP must use this Reset. ACTIVE HIGH
   input   logic [1:0]                   pck_cp2af_pwrState,
   input   logic                         pck_cp2af_error,
   output  logic [CCIP_TXPORT_WIDTH-1:0] bus_ccip_Tx,         // CCI-P TX port
   input   logic [CCIP_RXPORT_WIDTH-1:0] bus_ccip_Rx,         // CCI-P RX port

`ifdef INCLUDE_DDR4
    input  logic                          DDR4a_USERCLK,
    input  logic                          DDR4a_waitrequest,
    input  logic [511:0]                  DDR4a_readdata,
    input  logic                          DDR4a_readdatavalid,
    output logic [6:0]                    DDR4a_burstcount,
    output logic [511:0]                  DDR4a_writedata,
    output logic [26:0]                   DDR4a_address,
    output logic                          DDR4a_write,
    output logic                          DDR4a_read,
    output logic [63:0]                   DDR4a_byteenable,
    input  logic                          DDR4b_USERCLK,
    input  logic                          DDR4b_waitrequest,
    input  logic [511:0]                  DDR4b_readdata,
    input  logic                          DDR4b_readdatavalid,
    output logic [6:0]                    DDR4b_burstcount,
    output logic [511:0]                  DDR4b_writedata,
    output logic [26:0]                   DDR4b_address,
    output logic                          DDR4b_write,
    output logic                          DDR4b_read,
    output logic [63:0]                   DDR4b_byteenable,
`endif

`ifdef INCLUDE_ETHERNET
    pr_hssi_if.to_fiu              hssi,
`endif // INCLUDE_ETHERNET

    // BIP Interface
    input  logic                tcm_mmio_clk,
    input  logic                tcm_mmio_rst_n,
    input  logic      [8:0]     tcm_mmio_address,
    input  logic                tcm_mmio_rd,
    input  logic                tcm_mmio_wr,
    output logic                tcm_mmio_waitreq,
    input  logic     [31:0]     tcm_mmio_writedata,
    output logic     [31:0]     tcm_mmio_readdata,
    output logic                tcm_mmio_readdatavalid,

   // JTAG Interface for PR region debug
   input   logic            sr2pr_tms,
   input   logic            sr2pr_tdi,
   output  logic            pr2sr_tdo,
   input   logic            sr2pr_tck,
   input   logic            sr2pr_tckena
);


// ===========================================
// Top-level AFU platform interface
// ===========================================

    // OFS platform interface constructs a single interface object that
    // wraps all ports to the AFU.
    ofs_plat_if plat_ifc();

    // Clocks
    ofs_plat_std_clocks_gen_resets_from_active_high clocks
       (
        .pClk(Clk_400),
        .pClk_reset(SoftReset),
        .pClkDiv2(Clk_200),
        .pClkDiv4(Clk_100),
        .uClk_usr(uClk_usr),
        .uClk_usrDiv2(uClk_usrDiv2),
        .clocks(plat_ifc.clocks)
        );

    // Reset, etc.
    assign plat_ifc.softReset_n = plat_ifc.clocks.pClk.reset_n;
    assign plat_ifc.pwrState = pck_cp2af_pwrState;

    // Host CCI-P port
    assign plat_ifc.host_chan.ports[0].clk = plat_ifc.clocks.pClk.clk;
    assign plat_ifc.host_chan.ports[0].reset_n = plat_ifc.softReset_n;
    assign plat_ifc.host_chan.ports[0].instance_number = 0;
    assign plat_ifc.host_chan.ports[0].error = pck_cp2af_error;
    assign plat_ifc.host_chan.ports[0].sRx = bus_ccip_Rx;
    assign bus_ccip_Tx = plat_ifc.host_chan.ports[0].sTx;

// ===========================================
// AFU - Remote Debug JTAG IP instantiation
// ===========================================

`ifdef SIM_MODE
  assign pr2sr_tdo = 0;
`else
  `ifdef INCLUDE_REMOTE_STP
    wire loopback;
    sld_virtual_jtag
    inst_sld_virtual_jtag (
          .tdi (loopback),
          .tdo (loopback)
    );

    // Q17.0 modified SCJIO
    // with tck_ena
    altera_sld_host_endpoint#(
        .NEGEDGE_TDO_LATCH(0),
        .USE_TCK_ENA(1)
    ) scjio
    (
        .tck         (sr2pr_tck),         //  jtag.tck
        .tck_ena     (sr2pr_tckena),      //      .tck_ena
        .tms         (sr2pr_tms),         //      .tms
        .tdi         (sr2pr_tdi),         //      .tdi
        .tdo         (pr2sr_tdo),         //      .tdo

        .vir_tdi     (sr2pr_tdi),         //      .vir_tdi
        .select_this (1'b1)               //      .select_this
    );

  `else
    assign pr2sr_tdo = 0;
  `endif // INCLUDE_REMOTE_STP
`endif // SIM_MODE


// ===========================================
// Transform local memory for better timing
// ===========================================

`ifdef INCLUDE_DDR4
    logic DDR4a_softReset;
    logic DDR4b_softReset;

    // Reset synchronizer
    green_bs_resync #(
             .SYNC_CHAIN_LENGTH(2),
             .WIDTH(1),
             .INIT_VALUE(1)
    ) ddr4a_reset_sync (
             .clk(DDR4a_USERCLK),
             .reset(SoftReset),
             .d(1'b0),
             .q(DDR4a_softReset)
    );

    green_bs_resync #(
             .SYNC_CHAIN_LENGTH(2),
             .WIDTH(1),
             .INIT_VALUE(1)
    ) ddr4b_reset_sync (
             .clk(DDR4b_USERCLK),
             .reset(SoftReset),
             .d(1'b0),
             .q(DDR4b_softReset)
    );

    assign plat_ifc.local_mem.banks[0].clk = DDR4a_USERCLK;
    assign plat_ifc.local_mem.banks[0].reset_n = !DDR4a_softReset;
    assign plat_ifc.local_mem.banks[1].clk = DDR4b_USERCLK;
    assign plat_ifc.local_mem.banks[1].reset_n = !DDR4b_softReset;

    ddr_avmm_bridge #(
            .DATA_WIDTH        (512),
            .SYMBOL_WIDTH      (8),
            .ADDR_WIDTH    (27),
            .BURSTCOUNT_WIDTH  (7)
    ) ddr4a_avmm_bridge (
            .clk              (DDR4a_USERCLK),
            .reset            (DDR4a_softReset),
            .s0_waitrequest   (plat_ifc.local_mem.banks[0].waitrequest),
            .s0_readdata      (plat_ifc.local_mem.banks[0].readdata),
            .s0_readdatavalid (plat_ifc.local_mem.banks[0].readdatavalid),
            .s0_burstcount    (plat_ifc.local_mem.banks[0].burstcount),
            .s0_writedata     (plat_ifc.local_mem.banks[0].writedata),
            .s0_address       (plat_ifc.local_mem.banks[0].address),
            .s0_write         (plat_ifc.local_mem.banks[0].write),
            .s0_read          (plat_ifc.local_mem.banks[0].read),
            .s0_byteenable    (plat_ifc.local_mem.banks[0].byteenable),
            .m0_waitrequest   (DDR4a_waitrequest),
            .m0_readdata      (DDR4a_readdata),
            .m0_readdatavalid (DDR4a_readdatavalid),
            .m0_burstcount    (DDR4a_burstcount),
            .m0_writedata     (DDR4a_writedata),
            .m0_address       (DDR4a_address),
            .m0_write         (DDR4a_write),
            .m0_read          (DDR4a_read),
            .m0_byteenable    (DDR4a_byteenable)
    );

    ddr_avmm_bridge #(
            .DATA_WIDTH        (512),
            .SYMBOL_WIDTH      (8),
            .ADDR_WIDTH    (27),
            .BURSTCOUNT_WIDTH  (7)
    ) ddr4b_avmm_bridge (
            .clk              (DDR4b_USERCLK),
            .reset            (DDR4b_softReset),
            .s0_waitrequest   (plat_ifc.local_mem.banks[1].waitrequest),
            .s0_readdata      (plat_ifc.local_mem.banks[1].readdata),
            .s0_readdatavalid (plat_ifc.local_mem.banks[1].readdatavalid),
            .s0_burstcount    (plat_ifc.local_mem.banks[1].burstcount),
            .s0_writedata     (plat_ifc.local_mem.banks[1].writedata),
            .s0_address       (plat_ifc.local_mem.banks[1].address),
            .s0_write         (plat_ifc.local_mem.banks[1].write),
            .s0_read          (plat_ifc.local_mem.banks[1].read),
            .s0_byteenable    (plat_ifc.local_mem.banks[1].byteenable),
            .m0_waitrequest   (DDR4b_waitrequest),
            .m0_readdata      (DDR4b_readdata),
            .m0_readdatavalid (DDR4b_readdatavalid),
            .m0_burstcount    (DDR4b_burstcount),
            .m0_writedata     (DDR4b_writedata),
            .m0_address       (DDR4b_address),
            .m0_write         (DDR4b_write),
            .m0_read          (DDR4b_read),
            .m0_byteenable    (DDR4b_byteenable)
    );

    assign plat_ifc.local_mem.banks[0].response = '0;
    assign plat_ifc.local_mem.banks[0].writeresponsevalid = 1'b0;
    assign plat_ifc.local_mem.banks[0].writeresponse = '0;
    assign plat_ifc.local_mem.banks[1].response = '0;
    assign plat_ifc.local_mem.banks[1].writeresponsevalid = 1'b0;
    assign plat_ifc.local_mem.banks[1].writeresponse = '0;
`endif


// ===========================================
// HSSI Ethernet
// ===========================================

`ifdef INCLUDE_ETHERNET
    // OFS platform interface passes all HSSI ports through the top-level
    // wrapper.
    assign plat_ifc.hssi.ports[0].f2a_tx_clk = hssi.f2a_tx_clk;
    assign plat_ifc.hssi.ports[0].f2a_tx_clkx2 = hssi.f2a_tx_clkx2;
    assign plat_ifc.hssi.ports[0].f2a_rx_clk_ln0 = hssi.f2a_rx_clk_ln0;
    assign plat_ifc.hssi.ports[0].f2a_rx_clkx2_ln0 = hssi.f2a_rx_clkx2_ln0;
    assign plat_ifc.hssi.ports[0].f2a_rx_clk_ln4 = hssi.f2a_rx_clk_ln4;
    assign plat_ifc.hssi.ports[0].f2a_prmgmt_ctrl_clk = hssi.f2a_prmgmt_ctrl_clk;

    always_comb
    begin
        plat_ifc.hssi.ports[0].f2a_tx_locked = hssi.f2a_tx_locked;
       
        plat_ifc.hssi.ports[0].f2a_rx_locked_ln0 = hssi.f2a_rx_locked_ln0;
        plat_ifc.hssi.ports[0].f2a_rx_locked_ln4 = hssi.f2a_rx_locked_ln4;
    
        hssi.a2f_tx_analogreset = plat_ifc.hssi.ports[0].a2f_tx_analogreset;
        hssi.a2f_tx_digitalreset = plat_ifc.hssi.ports[0].a2f_tx_digitalreset;
        hssi.a2f_rx_analogreset = plat_ifc.hssi.ports[0].a2f_rx_analogreset;
        hssi.a2f_rx_digitalreset = plat_ifc.hssi.ports[0].a2f_rx_digitalreset;

        hssi.a2f_rx_seriallpbken = plat_ifc.hssi.ports[0].a2f_rx_seriallpbken;
        hssi.a2f_rx_set_locktoref = plat_ifc.hssi.ports[0].a2f_rx_set_locktoref;
        hssi.a2f_rx_set_locktodata = plat_ifc.hssi.ports[0].a2f_rx_set_locktodata;

        plat_ifc.hssi.ports[0].f2a_tx_cal_busy = hssi.f2a_tx_cal_busy;
        plat_ifc.hssi.ports[0].f2a_tx_pll_locked = hssi.f2a_tx_pll_locked;
        plat_ifc.hssi.ports[0].f2a_rx_cal_busy = hssi.f2a_rx_cal_busy;
        plat_ifc.hssi.ports[0].f2a_rx_is_lockedtoref = hssi.f2a_rx_is_lockedtoref;
        plat_ifc.hssi.ports[0].f2a_rx_is_lockedtodata = hssi.f2a_rx_is_lockedtodata;

        hssi.a2f_tx_parallel_data = plat_ifc.hssi.ports[0].a2f_tx_parallel_data;
        hssi.a2f_tx_control = plat_ifc.hssi.ports[0].a2f_tx_control;
        plat_ifc.hssi.ports[0].f2a_rx_parallel_data = hssi.f2a_rx_parallel_data;
        plat_ifc.hssi.ports[0].f2a_rx_control = hssi.f2a_rx_control;

        plat_ifc.hssi.ports[0].f2a_tx_enh_fifo_full = hssi.f2a_tx_enh_fifo_full;
        plat_ifc.hssi.ports[0].f2a_tx_enh_fifo_pfull = hssi.f2a_tx_enh_fifo_pfull;
        plat_ifc.hssi.ports[0].f2a_tx_enh_fifo_empty = hssi.f2a_tx_enh_fifo_empty;
        plat_ifc.hssi.ports[0].f2a_tx_enh_fifo_pempty = hssi.f2a_tx_enh_fifo_pempty;
        plat_ifc.hssi.ports[0].f2a_rx_enh_data_valid = hssi.f2a_rx_enh_data_valid;
        plat_ifc.hssi.ports[0].f2a_rx_enh_fifo_full = hssi.f2a_rx_enh_fifo_full;
        plat_ifc.hssi.ports[0].f2a_rx_enh_fifo_pfull = hssi.f2a_rx_enh_fifo_pfull;
        plat_ifc.hssi.ports[0].f2a_rx_enh_fifo_empty = hssi.f2a_rx_enh_fifo_empty;
        plat_ifc.hssi.ports[0].f2a_rx_enh_fifo_pempty = hssi.f2a_rx_enh_fifo_pempty;
        plat_ifc.hssi.ports[0].f2a_rx_enh_blk_lock = hssi.f2a_rx_enh_blk_lock;
        plat_ifc.hssi.ports[0].f2a_rx_enh_highber = hssi.f2a_rx_enh_highber;
        hssi.a2f_rx_enh_fifo_rd_en = plat_ifc.hssi.ports[0].a2f_rx_enh_fifo_rd_en;
        hssi.a2f_tx_enh_data_valid = plat_ifc.hssi.ports[0].a2f_tx_enh_data_valid;

        hssi.a2f_init_start = plat_ifc.hssi.ports[0].a2f_init_start;
        plat_ifc.hssi.ports[0].f2a_init_done = hssi.f2a_init_done;

        hssi.a2f_prmgmt_fatal_err = plat_ifc.hssi.ports[0].a2f_prmgmt_fatal_err;
        hssi.a2f_prmgmt_dout = plat_ifc.hssi.ports[0].a2f_prmgmt_dout;
        plat_ifc.hssi.ports[0].f2a_prmgmt_cmd = hssi.f2a_prmgmt_cmd;
        plat_ifc.hssi.ports[0].f2a_prmgmt_addr = hssi.f2a_prmgmt_addr;
        plat_ifc.hssi.ports[0].f2a_prmgmt_din = hssi.f2a_prmgmt_din;
        plat_ifc.hssi.ports[0].f2a_prmgmt_freeze = hssi.f2a_prmgmt_freeze;
        plat_ifc.hssi.ports[0].f2a_prmgmt_arst = hssi.f2a_prmgmt_arst;
        plat_ifc.hssi.ports[0].f2a_prmgmt_ram_ena = hssi.f2a_prmgmt_ram_ena;
    end
`endif // INCLUDE_ETHERNET


// ===========================================
// OFS platform interface instantiation
// ===========================================

    `PLATFORM_SHIM_MODULE_NAME `PLATFORM_SHIM_MODULE_NAME
       (
        .plat_ifc
        );


// ======================================================
// Workaround: To preserve uClk_usr routing to  PR region
// ======================================================

(* noprune *) logic uClk_usr_q1, uClk_usr_q2;
(* noprune *) logic uClk_usrDiv2_q1, uClk_usrDiv2_q2;
(* noprune *) logic pClkDiv4_q1, pClkDiv4_q2;
(* noprune *) logic pClkDiv2_q1, pClkDiv2_q2;

always_ff @(posedge uClk_usr)
begin
  uClk_usr_q1     <= uClk_usr_q2;
  uClk_usr_q2     <= !uClk_usr_q1;
end

always_ff @(posedge uClk_usrDiv2)
begin
  uClk_usrDiv2_q1 <= uClk_usrDiv2_q2;
  uClk_usrDiv2_q2 <= !uClk_usrDiv2_q1;
end

always_ff @(posedge Clk_100)
begin
  pClkDiv4_q1     <= pClkDiv4_q2;
  pClkDiv4_q2     <= !pClkDiv4_q1;
end

always_ff @(posedge Clk_200)
begin
  pClkDiv2_q1     <= pClkDiv2_q2;
  pClkDiv2_q2     <= !pClkDiv2_q1;
end

endmodule
