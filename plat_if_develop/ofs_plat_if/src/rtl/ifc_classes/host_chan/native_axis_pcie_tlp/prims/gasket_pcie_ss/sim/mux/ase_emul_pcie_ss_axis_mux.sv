// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

// Description
//-----------------------------------------------------------------------------
//
// PCIe SS AXI-S multiplexor. This implementation is smaller and simpler than
// the full Nmux() used in the PF/VF MUX. It is designed for multiplexing
// a relatively small number of connections, providing pipeline skid
// buffers on the inputs and a simple register on output.
//
//-----------------------------------------------------------------------------

module ase_emul_pcie_ss_axis_mux #(
   parameter NUM_CH = 1,

   parameter TDATA_WIDTH = ofs_pcie_ss_cfg_pkg::TDATA_WIDTH,
   parameter TUSER_WIDTH = ofs_pcie_ss_cfg_pkg::TUSER_WIDTH
)(
   input  wire clk,
   input  wire rst_n,

   pcie_ss_axis_if.sink   sink[NUM_CH],
   pcie_ss_axis_if.source source
);

localparam SEL_WIDTH = $clog2(NUM_CH);
localparam TKEEP_WIDTH = (TDATA_WIDTH/8);

logic [SEL_WIDTH-1:0] sel; 
logic [NUM_CH-1:0]    sel_1hot;
logic                 sel_valid;

logic [NUM_CH-1:0]    hold_1hot;
logic                 hold_valid;

logic ready;
assign ready = (~source.tvalid | source.tready);

//-----------------
// Input Stage
//-----------------

// Skid buffer in front of the arbiter both helps timing and avoids problems
// with upstream logic inserting bubbles when tready goes low.
pcie_ss_axis_if sink_in[NUM_CH](clk, rst_n);

logic [NUM_CH-1:0]                  in_tvalid;
logic [NUM_CH-1:0][TDATA_WIDTH-1:0] in_tdata;
logic [NUM_CH-1:0][TKEEP_WIDTH-1:0] in_tkeep; 
logic [NUM_CH-1:0]                  in_tlast; 
logic [NUM_CH-1:0][TUSER_WIDTH-1:0] in_tuser_vendor;
logic [NUM_CH-1:0]                  in_tready;

generate
   for (genvar c = 0; c < NUM_CH; c = c + 1) begin : in_pipe
      ase_emul_pcie_ss_axis_pipeline #(
             .TDATA_WIDTH(TDATA_WIDTH),
             .TUSER_WIDTH(TUSER_WIDTH),
             .PL_DEPTH(2) )
       skid (
             .clk,
             .rst_n,
             .axis_s(sink[c]),
             .axis_m(sink_in[c]));

      assign in_tvalid[c] = sink_in[c].tvalid;
      assign in_tdata[c] = sink_in[c].tdata;
      assign in_tkeep[c] = sink_in[c].tkeep;
      assign in_tlast[c] = sink_in[c].tlast;
      assign in_tuser_vendor[c] = sink_in[c].tuser_vendor;

      assign sink_in[c].tready = in_tready[c];
   end
endgenerate

assign in_tready = sel_1hot;
assign hold_valid = |hold_1hot;

always_ff @(posedge clk) begin
   for (int i=0; i<NUM_CH; ++i) begin
      if (in_tvalid[i] & in_tready[i]) begin
         hold_1hot[i] <= !in_tlast[i];
      end
   end

   if (~rst_n) begin
      hold_1hot <= '0;
   end
end

//-----------------
// Mux logic
//-----------------

logic [NUM_CH-1:0] bid_tvalid;

always_comb begin
   for (int i=0; i<NUM_CH; ++i) begin
      bid_tvalid[i] = in_tvalid[i] & (hold_1hot[i] | !hold_valid) & ready;
   end
end

ase_emul_fair_arbiter #(
   .NUM_INPUTS(NUM_CH)
) arb (
   .clk             (clk),
   .reset_n         (rst_n),
   .in_valid        (bid_tvalid),
   .hold_priority   (hold_1hot),
   .out_select      (sel),
   .out_select_1hot (sel_1hot),
   .out_valid       (sel_valid)
);

//-----------------
// Output Stage 
//-----------------
always_ff @(posedge clk) begin
   if (ready) begin
      source.tvalid <= sel_valid;
      source.tdata <= in_tdata[sel];
      source.tkeep <= in_tkeep[sel];
      source.tlast <= in_tlast[sel];
      source.tuser_vendor <= in_tuser_vendor[sel];
   end
   
   if (~rst_n) begin
      source.tvalid <= 1'b0; 
   end
end

endmodule // pcie_ss_axis_mux
