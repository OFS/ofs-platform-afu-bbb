// ***************************************************************************
//                         INTEL RESTRICTED SECRET
// 
//          Copyright (C) 2020 Intel Corporation All Rights Reserved.
//
// The source code contained or described herein and all  documents related to
// the  source  code  ("Material")  are  owned  by  Intel  Corporation  or its
// suppliers  or  licensors.    Title  to  the  Material  remains  with  Intel
// Corporation or  its suppliers  and licensors.  The Material  contains trade
// secrets  and  proprietary  and  confidential  information  of  Intel or its
// suppliers and licensors.  The Material is protected  by worldwide copyright
// and trade secret laws and treaty provisions. No part of the Material may be 
// used,   copied,   reproduced,   modified,   published,   uploaded,  posted,
// transmitted,  distributed,  or  disclosed  in any way without Intel's prior
// express written permission.
//
// No license under any patent,  copyright, trade secret or other intellectual
// property  right  is  granted  to  or  conferred  upon  you by disclosure or
// delivery  of  the  Materials, either expressly, by implication, inducement,
// estoppel or otherwise.  Any license under such intellectual property rights
// must be express and approved by Intel in writing.
// 
//
// Module Name: Nmux.sv
// Project:     IOFS
// Description:  N:1 Streaming Mux with Round Robin Priority Arbitraton and Bandwidth Control
//
// ***************************************************************************
//
// All ouputs are registered
// Inputs are NOT registered
//
// Note output FIFO is required for full bandwidth design
// pipe line registers would not work due to the delays of the 
// handshake signals (ready) at the input port.
//
// 1.  N:1 mux is consisit of 
//     a.  N inputs and 1 output mux
//     b.  round robin priority arbitration for N inputs to access 1 output
//     d.  optional instantiation of mux out register for timing
//     e.  optional instantion of input register for timing (done in next higher level switch.v)
//     f.  output fifo to handle arbitrary delays in ready handshake at the input port
//      
// 2.  N:1 mux are instantiated to form N X M switch (instantiate M instances of N:1 mux)
//
//
//                                         Optional                 Optional
//                                          IN REG                  MUX REG                              ____________
//                                           ___                      ___                               |            |
//                                          |   |      |\            |   |                              |   OUTPUT   |
//    mux_in_data[0][WIDTH-1:0]  ------/----|---|----->| \           |   |                              |    FIFO    |
//                                          |   |      |  |          |MUX|                              |            |
//    mux_in_data[1][WIDTH-1:0]  ------/----|---|----->|  |          |REG|  mux_in_data [select]        |            |   
//                                          | IN|      |  |--------->|---|----------------------------->|din     dout|------------/--------> mux_out_data
//               .                     .    |REG|      |  |          |   |  mux_in_valid[select]        |            |
//               .                     .    |   |      |  |--------->|---|---------------------.        |            |
//                                    WIDTH |   |      |  |          |   |                     |        |            |
//    mux_in_data[N][WIDTH-1:0]  ------/----|---|----->| /           |   |                     '--|     |            |
//                                          |___|      |/|           |___|                        |AND--|wen         |             
//                                                       |                                     .--|     |            |             
//                                                       '-----------------------------.       |        |            |
//                                                                    ___              |       |        |            |
//                                                    select_q       |   |             |       |        |            |
//                                         -------*------------------|REG|<------------*       |        |            |
//                                                |   mux_in_eop --->|en |             |       |        |            |
//                                                |                  |___|             |       |        |            |             
//                                                |                    |               |       |        |       valid|------------*--------> mux_out_valid 
//                                         -------|--------------------|---------------|-------*-------o|full        |            |
//                                                |               _____v____    mux    |                |            |            |
//                                              __V___           |          |   select |                |            |            |
//                             freeze___|      |      |-----/--->| Priority |------->--*                |            |        |---'    
//                                      |AND---|Rotate|          | Encoder  |          |                |         ren|<----AND|       
//                                N     |      |      |          |__________|          |                |            |        |<-----------   mux_out_ready 
//     mux_in_valid [N-1:0] ------/-----|      |______|                                |                |____________|    
//                                              ___               __________           |                                    
//                                             |   |        N    |          |      M   |                                    
//     mux_in_ready [N-1:0]<-------------------|REG|--------/----| Select   |<-----/---'                              
//                                             |___|             | Decoder  |
//                                                               |__________|  
//  example of mux arbitration (assuming 4:1 mux).  
//  *_q denotes 1 clk delay/registered signal
//        
//------------ |--------------------------------------------------------------------------------------------------------------------------------------------
//  clk#       |    0         1         2         3         4         5         6         7         8         9         10        11        12        13
//------------ |--------------------------------------------------------------------------------------------------------------------------------------------
//             |
//  in_port0   |    0         valid     valid     eop       valid     valid     valid    valid      eop       valid     eop       eop       0         0       
//             |              
//  in_port1   |    0         0         0         valid     valid1    valid1    valid    eop        0         0         0         0         0         0
//             |              
//  in_port2   |    0         valid     valid     valid     eop2      0         0         0         0         0         0         0         0         0
//             |              
//  in_port3   |    0         0         valid     valid     valid3    valid3    eop3      0         0         0         0         0         0         0
//             |              
// out_ready   |    0         1         1         1         1         1         1         1         1         1         0         1         1         1       
//------------------------------------------------------------------------------------------------------------------------------------------------------------
//  out_port   |    x         port0_q   port0_q   port0_q   port2_q   port3_q   port3_q   port1_q   port0_q   port0_q   port0_q   port0_q   ..
//  in_ready   |              ready0    ready0    ready0    ready2    ready3    ready3    ready1    ready0    ready0    0         ready0    0
//------------------------------------------------------------------------------------------------------------------------------------------------------------
//             |
// mux_in_sop  |    0         sop0      0         0         sop2      sop3      0         sop1      sop0      0         sop0      0         0         0
// mux_in_eop  |    0         0         0         eop0      eop2      0         eop3      eop1      0         eop0      0         eop0      eop0      0 
// select      |    0         0         0         0         2         3         3         1         0         0         0         0         0         0
// select_en        1         1         0         0         1         1         0         1         1         0         1         0         1         1
//                            1         0         1         1         1         1         1         1         1         1         1          
// mux_in_sop  =    mux_in_valid[priority] & !mux_in_valid_q
//             |    mux_in_valid[priority] &  mux_in_eop_q  
//
//         
// 
//        
module ase_emul_Nmux 
     #(parameter                        WIDTH   = 128                         ,// width of the input port
                                        DEPTH   = 1                           ,// depth of the output fifo = 2**DEPTH
                                        N       = 4                          ) // number of mux input ports
      (                                                                        //  
      input      [N-1:0][WIDTH-1:0]     mux_in_data                           ,// Mux in data
      input      [N-1:0]                mux_in_sop                            ,// Mux in start of packet
      input      [N-1:0]                mux_in_eop                            ,// Mux in end of packet
      input      [N-1:0]                mux_in_valid                          ,// Mux in data valid
      input                             mux_out_ready                         ,// output ready from next stage logic
      input                             rst_n                                 ,// reset low active
      input                             clk                                   ,//
                                                                               //
      output logic [N-1:0]              mux_in_ready                          ,// mux_in_valid & mux_in_ready indicates data is transferred to output
      output logic [WIDTH-1:0]          mux_out_data                          ,// Mux out data
      output logic                      mux_out_valid                         ,// Mux out data valid
      output logic                      out_q_err                             ,// Mux out fifo error
      output logic                      out_q_perr                             // Mux out fifo ram parity error
      );                                                                       //
      parameter                         M =(N==1)? 1 : $clog2(N)              ;// determine array index size. 
      logic      [M-1:0]                select                                ;// round robin mux select
      logic      [M-1:0]                select_q                              ;// registered select (current selected port)
      logic                             select_en                             ;// update mux select from round robin search 
      logic      [N-1:0]                bit_vector                            ;// bit_vector = mux_in_valid & (bandwidth_counter > 0)
      logic      [N-1:0]                bit_rotate                            ;// round robin rotated version of bit_vector
      logic                             mux_in_sop_or                         ;// OR of all mux in sop except for the current selected port
      logic      [WIDTH-1:0]            out_q_din                             ;// out_q(fifo) data in
      logic                             out_q_wen                             ;// out_q(fifo) write enable strobe
      logic                             out_q_ren                             ;// out_q(fifo) read enable strobe
      logic                             out_q_full                            ;// out_q(fifo) full threshold reached
      integer                           i , j                                 ;// index
                                                                               //
      always @(*) begin                                                        //
                               mux_in_sop_or = 0                              ;//
          for (i=0; i<N; i++)                                                  //
              if (i!=select_q) mux_in_sop_or = mux_in_sop_or | mux_in_sop[i]  ;// OR of all mux_in_sop except for current selected mux port
                                                                               //
          for (i=0; i<N; i++)                                                  //
               bit_vector[i]=  mux_in_valid[i]                                ;// bit_vector represents mux_in_valid AND bandwidth_count > 0 
               bit_rotate   =  bit_vector >> select_q                          //
                            |  bit_vector <<(N-select_q)                      ;// rotate higest port to least priority (round robin priority)
                                                                               //
                                                    select = select_q         ;//
               for (i=0; i<N; i++)                                             //
                    if (bit_rotate[i])                                         //
                        select = (select_q+i+1)>N ? select_q + i - N           // select = highest priority port on the rotated mux_in_valid  
                                                  : select_q + i              ;//
                                                                               //
               mux_in_ready           = 0                                     ;//                                                        
               mux_in_ready[select_q] = !out_q_full                           ;// indicates arbitration accepted input port data
                                                                               //
               out_q_din    = mux_in_data  [select_q]                         ;// if mux pipe reg is instantiated connect fifo to pipe out        
               out_q_wen    = mux_in_ready [select_q]                          //
                            & mux_in_valid [select_q]                         ;// output fifo write enable = in_ready &  in_valid
               out_q_ren    = mux_out_ready           & mux_out_valid         ;// output fifo read enable = out_ready & out_valid
      end                                                                      //
                                                                               //
      always @(posedge clk) begin                                              //
                                                                               //
          if (select_en) select_q <= select                                   ;// update select if enabled; else hold
                                                                               //
          if ( mux_in_ready[select_q])   begin                                 // if current selected mux port ready is asserted
             if (mux_in_sop[select_q] &  select_en    ) select_en <= 0        ;// check if it is a start of packet, if so disable switching to prevent mux
             if (mux_in_sop[select_q] &  select_en    ) select_q  <= select_q ;// port change during a xfer.  hold select_q throughout the xfer.
             if (mux_in_eop[select_q] &  mux_in_sop_or) select_q  <= select   ;// packet is completing and there are other xfer requests.  swithc to new owner
             if (mux_in_eop[select_q] & !mux_in_sop_or) select_en <= 1        ;// if no other requests, reenable mux switching
          end                                                                  //
                                                                               //
          if (!rst_n)   begin                                                  // reset low active
              select_q        <=  0                                           ;//
              select_en       <=  1                                           ;//
          end                                                                  //
      end                                                                      //
                                                                               //
      logic out_q_notFull;
      assign out_q_full = ~out_q_notFull;

      ofs_plat_prim_fifo2
        #(
          .N_DATA_BITS(WIDTH)
          )
        out_q
         (
          .clk,
          .reset_n(rst_n),

          .enq_data(out_q_din),
          .enq_en(out_q_wen),
          .notFull(out_q_notFull),

          .first(mux_out_data),
          .deq_en(out_q_ren),
          .notEmpty(mux_out_valid)
          );

      assign out_q_err = 1'b0;
      assign out_q_perr = 1'b0;
endmodule                                                                      //                
