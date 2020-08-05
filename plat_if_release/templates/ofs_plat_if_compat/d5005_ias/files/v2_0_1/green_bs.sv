// ***************************************************************************
// Copyright (c) 2013-2018, Intel Corporation
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

`ifdef INCLUDE_DDR4
`include "pr_avalon_mem_if.vh"
`endif

`ifdef INCLUDE_ETHERNET
`include "pr_hssi_if.vh"
import hssi_eth_pkg::*;
`endif

parameter CCIP_TXPORT_WIDTH = $bits(t_if_ccip_Tx);  // TODO: Move this to ccip_if_pkg
parameter CCIP_RXPORT_WIDTH = $bits(t_if_ccip_Rx);  // TODO: Move this to ccip_if_pkg

module green_bs
#(
   parameter NUM_FIU_LOCAL_MEM_BANKS = 4,
   parameter PR_LOCAL_MEM_ADDR_WIDTH = 27,
   parameter PR_LOCAL_MEM_DATA_WIDTH = 576,
   parameter PR_LOCAL_MEM_BYTEENA_WIDTH = (PR_LOCAL_MEM_DATA_WIDTH/8),
   parameter PR_LOCAL_MEM_BURSTCOUNT_WIDTH = 7
)
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
   input  logic                                      DDR4a_USERCLK,
   input  logic                                      DDR4a_waitrequest,
   input  logic [PR_LOCAL_MEM_DATA_WIDTH-1:0]        DDR4a_readdata,
   input  logic                                      DDR4a_readdatavalid,
   output logic [PR_LOCAL_MEM_BURSTCOUNT_WIDTH-1:0]  DDR4a_burstcount,
   output logic [PR_LOCAL_MEM_DATA_WIDTH-1:0]        DDR4a_writedata,
   output logic [PR_LOCAL_MEM_ADDR_WIDTH-1:0]        DDR4a_address,
   output logic                                      DDR4a_write,
   output logic                                      DDR4a_read,
   output logic [PR_LOCAL_MEM_BYTEENA_WIDTH-1:0]     DDR4a_byteenable,
   input  logic                                      DDR4a_ecc_interrupt,
   input  logic                                      DDR4b_USERCLK,
   input  logic                                      DDR4b_waitrequest,
   input  logic [PR_LOCAL_MEM_DATA_WIDTH-1:0]        DDR4b_readdata,
   input  logic                                      DDR4b_readdatavalid,
   output logic [PR_LOCAL_MEM_BURSTCOUNT_WIDTH-1:0]  DDR4b_burstcount,
   output logic [PR_LOCAL_MEM_DATA_WIDTH-1:0]        DDR4b_writedata,
   output logic [PR_LOCAL_MEM_ADDR_WIDTH-1:0]        DDR4b_address,
   output logic                                      DDR4b_write,
   output logic                                      DDR4b_read,
   output logic [PR_LOCAL_MEM_BYTEENA_WIDTH-1:0]     DDR4b_byteenable,
   input  logic                                      DDR4b_ecc_interrupt,
   input  logic                                      DDR4c_USERCLK,
   input  logic                                      DDR4c_waitrequest,
   input  logic [PR_LOCAL_MEM_DATA_WIDTH-1:0]        DDR4c_readdata,
   input  logic                                      DDR4c_readdatavalid,
   output logic [PR_LOCAL_MEM_BURSTCOUNT_WIDTH-1:0]  DDR4c_burstcount,
   output logic [PR_LOCAL_MEM_DATA_WIDTH-1:0]        DDR4c_writedata,
   output logic [PR_LOCAL_MEM_ADDR_WIDTH-1:0]        DDR4c_address,
   output logic                                      DDR4c_write,
   output logic                                      DDR4c_read,
   output logic [PR_LOCAL_MEM_BYTEENA_WIDTH-1:0]     DDR4c_byteenable,
   input  logic                                      DDR4c_ecc_interrupt,
   input  logic                                      DDR4d_USERCLK,
   input  logic                                      DDR4d_waitrequest,
   input  logic [PR_LOCAL_MEM_DATA_WIDTH-1:0]        DDR4d_readdata,
   input  logic                                      DDR4d_readdatavalid,
   output logic [PR_LOCAL_MEM_BURSTCOUNT_WIDTH-1:0]  DDR4d_burstcount,
   output logic [PR_LOCAL_MEM_DATA_WIDTH-1:0]        DDR4d_writedata,
   output logic [PR_LOCAL_MEM_ADDR_WIDTH-1:0]        DDR4d_address,
   output logic                                      DDR4d_write,
   output logic                                      DDR4d_read,
   output logic [PR_LOCAL_MEM_BYTEENA_WIDTH-1:0]     DDR4d_byteenable,
   input  logic                                      DDR4d_ecc_interrupt,
`endif

`ifdef INCLUDE_ETHERNET
   pr_hssi_if.to_fiu  hssi[NUM_QSFP_IF], // HSSI vector interface
`endif // INCLUDE_ETHERNET

   // JTAG Interface for PR region debug
   input  logic                          sr2pr_tms,
   input  logic                          sr2pr_tdi,             
   output logic                          pr2sr_tdo,             
   input  logic                          sr2pr_tck,
   input  logic                          sr2pr_tckena
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
// Transform PR local memory to the AFU interface
// ===========================================

`ifdef INCLUDE_DDR4
    // This section is temporary.  It converts the PR wires to a SystemVerilog interface.
    // Eventually, we will simply pass the pr_local_mem vector as a port to green_bs()
    // from the FIU and eliminate the instantiation here of pr_local_mem and the wire
    // mappings from DDR4x PR wires.
    pr_avalon_mem_if pr_local_mem[NUM_FIU_LOCAL_MEM_BANKS]();

    assign pr_local_mem[0].clk = DDR4a_USERCLK;
    assign pr_local_mem[1].clk = DDR4b_USERCLK;
    assign pr_local_mem[2].clk = DDR4c_USERCLK;
    assign pr_local_mem[3].clk = DDR4d_USERCLK;

    always_comb
    begin
        pr_local_mem[0].waitrequest = DDR4a_waitrequest;
        pr_local_mem[0].readdata = DDR4a_readdata;
        pr_local_mem[0].readdatavalid = DDR4a_readdatavalid;
        DDR4a_burstcount = pr_local_mem[0].burstcount;
        DDR4a_writedata = pr_local_mem[0].writedata;
        DDR4a_address = pr_local_mem[0].address;
        DDR4a_write = pr_local_mem[0].write;
        DDR4a_read = pr_local_mem[0].read;
        DDR4a_byteenable = pr_local_mem[0].byteenable;
        pr_local_mem[0].ecc_interrupt = DDR4a_ecc_interrupt;

        pr_local_mem[1].waitrequest = DDR4b_waitrequest;
        pr_local_mem[1].readdata = DDR4b_readdata;
        pr_local_mem[1].readdatavalid = DDR4b_readdatavalid;
        DDR4b_burstcount = pr_local_mem[1].burstcount;
        DDR4b_writedata = pr_local_mem[1].writedata;
        DDR4b_address = pr_local_mem[1].address;
        DDR4b_write = pr_local_mem[1].write;
        DDR4b_read = pr_local_mem[1].read;
        DDR4b_byteenable = pr_local_mem[1].byteenable;
        pr_local_mem[1].ecc_interrupt = DDR4b_ecc_interrupt;

        pr_local_mem[2].waitrequest = DDR4c_waitrequest;
        pr_local_mem[2].readdata = DDR4c_readdata;
        pr_local_mem[2].readdatavalid = DDR4c_readdatavalid;
        DDR4c_burstcount = pr_local_mem[2].burstcount;
        DDR4c_writedata = pr_local_mem[2].writedata;
        DDR4c_address = pr_local_mem[2].address;
        DDR4c_write = pr_local_mem[2].write;
        DDR4c_read = pr_local_mem[2].read;
        DDR4c_byteenable = pr_local_mem[2].byteenable;
        pr_local_mem[2].ecc_interrupt = DDR4c_ecc_interrupt;

        pr_local_mem[3].waitrequest = DDR4d_waitrequest;
        pr_local_mem[3].readdata = DDR4d_readdata;
        pr_local_mem[3].readdatavalid = DDR4d_readdatavalid;
        DDR4d_burstcount = pr_local_mem[3].burstcount;
        DDR4d_writedata = pr_local_mem[3].writedata;
        DDR4d_address = pr_local_mem[3].address;
        DDR4d_write = pr_local_mem[3].write;
        DDR4d_read = pr_local_mem[3].read;
        DDR4d_byteenable = pr_local_mem[3].byteenable;
        pr_local_mem[3].ecc_interrupt = DDR4d_ecc_interrupt;
    end

    //
    // Add a pipeline stage to local memory for better timing
    // and map memory the plat_ifc.local_mem.
    //

    // Construct a reset from the global soft reset in each bank's clock domain.
    logic local_mem_reset[NUM_FIU_LOCAL_MEM_BANKS];
    logic local_mem_reset_q0[NUM_FIU_LOCAL_MEM_BANKS] = '{NUM_FIU_LOCAL_MEM_BANKS{1'b1}};
    logic local_mem_reset_q1[NUM_FIU_LOCAL_MEM_BANKS] = '{NUM_FIU_LOCAL_MEM_BANKS{1'b1}};

    genvar b;
    generate
        for (b = 0; b < NUM_FIU_LOCAL_MEM_BANKS; b = b + 1)
        begin : lm_pipe
            // Reset synchronizer
            green_bs_resync
              #(
                .SYNC_CHAIN_LENGTH(2),
                .WIDTH(1),
                .INIT_VALUE(1)
                )
              local_mem_reset_sync
               (
                .clk(pr_local_mem[b].clk),
                .reset(SoftReset),
                .d(1'b0),
                .q(local_mem_reset[b])
                );

            always @(posedge pr_local_mem[b].clk)
            begin
                local_mem_reset_q0[b] <= local_mem_reset[b];
                local_mem_reset_q1[b] <= local_mem_reset[b];
            end

            assign plat_ifc.local_mem.banks[b].reset_n = !local_mem_reset_q1[b];
            assign plat_ifc.local_mem.banks[b].clk = pr_local_mem[b].clk;

            ddr_avmm_bridge
              #(
                .DATA_WIDTH(PR_LOCAL_MEM_DATA_WIDTH),
                .SYMBOL_WIDTH(8),
                .ADDR_WIDTH(PR_LOCAL_MEM_ADDR_WIDTH),
                .BURSTCOUNT_WIDTH(PR_LOCAL_MEM_BURSTCOUNT_WIDTH),
                .READDATA_PIPE_DEPTH(2)
                )
              local_mem_avmm_bridge
               (
                .clk              (pr_local_mem[b].clk),
                .reset            (local_mem_reset_q0[b]),
                .s0_waitrequest   (plat_ifc.local_mem.banks[b].waitrequest),
                .s0_readdata      (plat_ifc.local_mem.banks[b].readdata),
                .s0_readdatavalid (plat_ifc.local_mem.banks[b].readdatavalid),
                .s0_burstcount    (plat_ifc.local_mem.banks[b].burstcount),
                .s0_writedata     (plat_ifc.local_mem.banks[b].writedata),
                .s0_address       (plat_ifc.local_mem.banks[b].address),
                .s0_write         (plat_ifc.local_mem.banks[b].write),
                .s0_read          (plat_ifc.local_mem.banks[b].read),
                .s0_byteenable    (plat_ifc.local_mem.banks[b].byteenable),
                .m0_waitrequest   (pr_local_mem[b].waitrequest),
                .m0_readdata      (pr_local_mem[b].readdata),
                .m0_readdatavalid (pr_local_mem[b].readdatavalid),
                .m0_burstcount    (pr_local_mem[b].burstcount),
                .m0_writedata     (pr_local_mem[b].writedata),
                .m0_address       (pr_local_mem[b].address),
                .m0_write         (pr_local_mem[b].write),
                .m0_read          (pr_local_mem[b].read),
                .m0_byteenable    (pr_local_mem[b].byteenable)
                );

            assign plat_ifc.local_mem.banks[b].response = '0;
            assign plat_ifc.local_mem.banks[b].writeresponsevalid = 1'b0;
            assign plat_ifc.local_mem.banks[b].writeresponse = '0;
        end
    endgenerate
`endif // INCLUDE_DDR4


// ===========================================
// HSSI Ethernet
// ===========================================
// What does the platform provide and the AFU require?
`ifdef INCLUDE_ETHERNET // platform provides HSSI interface(s)
    `ifndef INCLUDE_GREEN_ETHERNET_WRAPPER // AFU build only

        // Map HSSI interface(s) required by AFU
        genvar qsfp_num;
        generate
            for (qsfp_num = 0; qsfp_num < NUM_QSFP_IF; qsfp_num = qsfp_num + 1)
            begin : hssi_map
                assign plat_ifc.hssi.ports[qsfp_num].f2a_tx_parallel_clk_x1 = hssi[qsfp_num].f2a_tx_parallel_clk_x1;
                assign plat_ifc.hssi.ports[qsfp_num].f2a_tx_parallel_clk_x2 = hssi[qsfp_num].f2a_tx_parallel_clk_x2;
                assign plat_ifc.hssi.ports[qsfp_num].f2a_rx_clkout = hssi[qsfp_num].f2a_rx_clkout;

                // Reset IP Control/Status signals
                assign plat_ifc.hssi.ports[qsfp_num].f2a_rx_analogreset_stat = hssi[qsfp_num].f2a_rx_analogreset_stat;
                assign plat_ifc.hssi.ports[qsfp_num].f2a_rx_digitalreset_stat = hssi[qsfp_num].f2a_rx_digitalreset_stat;
                assign plat_ifc.hssi.ports[qsfp_num].f2a_tx_analogreset_stat = hssi[qsfp_num].f2a_tx_analogreset_stat;
                assign plat_ifc.hssi.ports[qsfp_num].f2a_tx_digitalreset_stat = hssi[qsfp_num].f2a_tx_digitalreset_stat;
                assign hssi[qsfp_num].a2f_tx_analogreset = plat_ifc.hssi.ports[qsfp_num].a2f_tx_analogreset;
                assign hssi[qsfp_num].a2f_tx_digitalreset = plat_ifc.hssi.ports[qsfp_num].a2f_tx_digitalreset;
                assign hssi[qsfp_num].a2f_rx_analogreset = plat_ifc.hssi.ports[qsfp_num].a2f_rx_analogreset;
                assign hssi[qsfp_num].a2f_rx_digitalreset = plat_ifc.hssi.ports[qsfp_num].a2f_rx_digitalreset;

                always_comb
                begin
                    // TX PCS
                    plat_ifc.hssi.ports[qsfp_num].f2a_tx_ready = hssi[qsfp_num].f2a_tx_ready;
                    plat_ifc.hssi.ports[qsfp_num].f2a_tx_fifo_empty = hssi[qsfp_num].f2a_tx_fifo_empty;
                    plat_ifc.hssi.ports[qsfp_num].f2a_tx_fifo_full = hssi[qsfp_num].f2a_tx_fifo_full;
                    plat_ifc.hssi.ports[qsfp_num].f2a_tx_fifo_pempty = hssi[qsfp_num].f2a_tx_fifo_pempty;
                    plat_ifc.hssi.ports[qsfp_num].f2a_tx_fifo_pfull = hssi[qsfp_num].f2a_tx_fifo_pfull;
                    hssi[qsfp_num].a2f_tx_parallel_data = plat_ifc.hssi.ports[qsfp_num].a2f_tx_parallel_data;
                    plat_ifc.hssi.ports[qsfp_num].f2a_tx_cal_busy = hssi[qsfp_num].f2a_tx_cal_busy;

                    // RX PCS
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_ready = hssi[qsfp_num].f2a_rx_ready;
                    hssi[qsfp_num].a2f_rx_bitslip = plat_ifc.hssi.ports[qsfp_num].a2f_rx_bitslip;
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_fifo_empty = hssi[qsfp_num].f2a_rx_fifo_empty;
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_fifo_full = hssi[qsfp_num].f2a_rx_fifo_full;
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_fifo_pempty = hssi[qsfp_num].f2a_rx_fifo_pempty;
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_fifo_pfull = hssi[qsfp_num].f2a_rx_fifo_pfull;
                    hssi[qsfp_num].a2f_rx_fifo_rd_en = plat_ifc.hssi.ports[qsfp_num].a2f_rx_fifo_rd_en;
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_parallel_data = hssi[qsfp_num].f2a_rx_parallel_data;
                    hssi[qsfp_num].a2f_rx_seriallpbken = plat_ifc.hssi.ports[qsfp_num].a2f_rx_seriallpbken;
                    hssi[qsfp_num].a2f_channel_reset = plat_ifc.hssi.ports[qsfp_num].a2f_channel_reset;
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_is_lockedtodata = hssi[qsfp_num].f2a_rx_is_lockedtodata;
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_is_lockedtoref = hssi[qsfp_num].f2a_rx_is_lockedtoref;
                    plat_ifc.hssi.ports[qsfp_num].f2a_atxpll_locked = hssi[qsfp_num].f2a_atxpll_locked;
                    plat_ifc.hssi.ports[qsfp_num].f2a_fpll_locked = hssi[qsfp_num].f2a_fpll_locked;
                    plat_ifc.hssi.ports[qsfp_num].f2a_rx_cal_busy = hssi[qsfp_num].f2a_rx_cal_busy;
                end
            end
        endgenerate
    `endif
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

// =============================================================
// Partial reconfiguration zone for HSSI instances
// =============================================================
`ifdef INCLUDE_ETHERNET
    `ifdef INCLUDE_GREEN_ETHERNET_WRAPPER
        genvar hssi_inst;
        generate
            for (hssi_inst = 0; hssi_inst < NUM_QSFP_IF; hssi_inst = hssi_inst+1)
            begin : hssi_wrapper
                green_hssi prz0
                (
                    .upi_clk_125  (Clk_200),
                    .hssi         (hssi[hssi_inst])
                );
            end
        endgenerate
    `endif // INCLUDE_ETHERNET_GREEN_WRAPPER
`endif // INCLUDE_ETHERNET

endmodule
