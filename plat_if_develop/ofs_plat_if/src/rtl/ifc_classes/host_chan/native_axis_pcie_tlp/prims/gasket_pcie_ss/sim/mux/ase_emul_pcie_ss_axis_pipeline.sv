// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

// Description
//-----------------------------------------------------------------------------
//
// AXIS pipeline generator
//
//-----------------------------------------------------------------------------

module ase_emul_pcie_ss_axis_pipeline 
#( 
    parameter MODE                 = 0, // 0: skid buffer 1: simple buffer 2: simple buffer (bubble) 3: bypass
    parameter TREADY_RST_VAL       = 0, // 0: tready deasserted during reset 
                                        // 1: tready asserted during reset
    parameter ENABLE_TKEEP         = 1,
    parameter ENABLE_TLAST         = 1,
    parameter ENABLE_TID           = 0,
    parameter ENABLE_TDEST         = 0,
    parameter ENABLE_TUSER         = 1,
   
    parameter TDATA_WIDTH          = 512,
    parameter TID_WIDTH            = 8,
    parameter TDEST_WIDTH          = 8,
    parameter TUSER_WIDTH          = 10,

    parameter PL_DEPTH = 1
)(
    input logic            clk,
    input logic            rst_n,
    pcie_ss_axis_if.sink   axis_s,
    pcie_ss_axis_if.source axis_m

);

pcie_ss_axis_if axis_pl [PL_DEPTH:0](clk, rst_n);

always_comb begin
   axis_pl[0].tvalid       = axis_s.tvalid;
   axis_pl[0].tlast        = axis_s.tlast;
   axis_pl[0].tuser_vendor = axis_s.tuser_vendor;
   axis_pl[0].tdata        = axis_s.tdata;
   axis_pl[0].tkeep        = axis_s.tkeep;

   axis_s.tready = axis_pl[0].tready;
   

   axis_m.tvalid       = axis_pl[PL_DEPTH].tvalid;
   axis_m.tlast        = axis_pl[PL_DEPTH].tlast;
   axis_m.tuser_vendor = axis_pl[PL_DEPTH].tuser_vendor;
   axis_m.tdata        = axis_pl[PL_DEPTH].tdata;
   axis_m.tkeep        = axis_pl[PL_DEPTH].tkeep;

   axis_pl[PL_DEPTH].tready = axis_m.tready;
end
   
genvar n;
generate
   for(n=0; n<PL_DEPTH; n=n+1) begin : axis_pl_stage
      ase_emul_pcie_ss_axis_register #( 
         .MODE           ( MODE           ),
         .TREADY_RST_VAL ( TREADY_RST_VAL ),
         .ENABLE_TKEEP   ( ENABLE_TKEEP   ),
         .ENABLE_TLAST   ( ENABLE_TLAST   ),
         .ENABLE_TID     ( ENABLE_TID     ),
         .ENABLE_TDEST   ( ENABLE_TDEST   ),
         .ENABLE_TUSER   ( ENABLE_TUSER   ),
         .TDATA_WIDTH    ( TDATA_WIDTH    ),
         .TID_WIDTH      ( TID_WIDTH      ),
         .TDEST_WIDTH    ( TDEST_WIDTH    ),
         .TUSER_WIDTH    ( TUSER_WIDTH    )
      
      ) axis_reg_inst (
        .clk       (clk),
        .rst_n     (rst_n),

        .s_tready  (axis_pl[n].tready),
        .s_tvalid  (axis_pl[n].tvalid),
        .s_tdata   (axis_pl[n].tdata),
        .s_tkeep   (axis_pl[n].tkeep),
        .s_tlast   (axis_pl[n].tlast),
        .s_tid     (),
        .s_tdest   (),
        .s_tuser   (axis_pl[n].tuser_vendor),
                   
        .m_tready  (axis_pl[n+1].tready),
        .m_tvalid  (axis_pl[n+1].tvalid),
        .m_tdata   (axis_pl[n+1].tdata),
        .m_tkeep   (axis_pl[n+1].tkeep),
        .m_tlast   (axis_pl[n+1].tlast),
        .m_tid     (),
        .m_tdest   (), 
        .m_tuser   (axis_pl[n+1].tuser_vendor)
      );
   end // for (n=0; n<PL_DEPTH; n=n+1)
endgenerate
endmodule // axis_pipeline

