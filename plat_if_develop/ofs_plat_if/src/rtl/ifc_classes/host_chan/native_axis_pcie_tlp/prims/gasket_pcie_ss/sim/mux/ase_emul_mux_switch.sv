// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Module Name: switch.sv
// Project:     IOFS
// Description: see below 
//
// ***************************************************************************     
//     
//   Please refer to Nmux.sv for more detials on the design of Nmux.
//     
//   N X M mux is composed of M instances of N:1 mux (Nmux.sv) and N instances of M:1 mux (Nmux.sv) 
//   Each mux output port has an arbitor for the incoming ports that does round robin arbitration.
//   at the high level, switch appears as below:
//     
//                                                          
//                   M to N Muxing                                         N to M Muxing
//                                                          
//                                                          
//           M_in_port[0] ....    M_in_port[M-1]                     M_out_port[0]         M_out_port[M-1]
//               |                  |                                       A                   A
//               |                  |                                       |                   |
//               |                  |                                   M_FIFO[0]          M_FIFO[M-1]
//               |                  |                                       |                   |
//               |      ____________|                                       |                   |
//               | ... |                                     M_Arb[0]--->M_mux[0]  .....     M_mux[M-1]<--M_Arb[M-1]
//               |     |         | .....|                                A    A              A       A
//               V     V         V      V                                |    |              |.......|
// N_Arb[0]-->  N_mux[0].....   N_mux[N-1:0]<--N_Arb[N-1:0]              |....|                     
//                 |                |                                    |    |___________________
//                 |                |                                    |                        |
//              N_FIFO[0]       N_FIFO[N-1]                              |                        |
//                 |                |                                    |                        | 
//                 V                V                                    |                        |
//            N_out_port[0]     N_out_port[N-1]                    N_in_port[0]   ......  N_in_prot[N-1]
//              
//  
// 
//

module ase_emul_mux_switch #(parameter WIDTH=80, N=4, M=2, DEPTH=2)              // crossbar switch of N ports to M ports
      (                                                                          //----------- input -------------------------------------
      input   wire  [M-1:0][WIDTH-1:0]  M_in_data                               ,// Mux M to N ports data in 
      input   wire  [M-1:0][N-1:0]      M_in_sop                                ,// Mux M to N ports start of packet
      input   wire  [M-1:0][N-1:0]      M_in_eop                                ,// Mux M to N ports end of packet
      input   wire  [M-1:0][N-1:0]      M_in_valid                              ,// Mux M to N ports data in valid
      input   wire  [M-1:0]             M_out_ready                             ,// Mux M to N ports data out ready from next stage logic
      input   wire  [N-1:0][WIDTH-1:0]  N_in_data                               ,// Mux N to M data in 
      input   wire  [N-1:0][M-1:0]      N_in_sop                                ,// Mux N to M data in start of packet
      input   wire  [N-1:0][M-1:0]      N_in_eop                                ,// Mux N to M data in end of packet
      input   wire  [N-1:0][M-1:0]      N_in_valid                              ,// Mux N to M data in valid
      input   wire  [N-1:0]             N_out_ready                             ,// Mux N to M data out ready from next stage logic 
      input   wire                      rst_n                                   ,// reset low active
      input   wire                      clk                                     ,// clock
                                                                                 //----------  output ----------------------------------
      output  logic [M-1:0][N-1:0]      M_in_ready                              ,// Mux M to N ready 
      output  logic [M-1:0]             M_out_valid                             ,// Mux M to N out valid
      output  logic [M-1:0][WIDTH-1:0]  M_out_data                              ,// Mux M to N data out
      output  logic [N-1:0][M-1:0]      N_in_ready                              ,// Mux N to M ready 
      output  logic [N-1:0]             N_out_valid                             ,// Mux N to M out valid
      output  logic [N-1:0][WIDTH-1:0]  N_out_data                              ,// Mux N to M data out
      output  logic                     out_q_err                               ,// output queue FIFO error
      output  logic                     out_q_perr                               // output queue FIFO ram parity error
      )                                                                         ;//
                                                                                 //
      integer                                 i, j, k                           ;// 
      logic [M-1:0][N-1:0][WIDTH-1:0]   M_mux_in_data                           ;// M Mux in data
      logic [M-1:0][N-1:0][WIDTH-1:0]   M_mux_in_data_q     = 0                 ;// M Mux in data
      logic [M-1:0][N-1:0]              M_mux_in_sop                            ;// M Mux in start of packet
      logic [M-1:0][N-1:0]              M_mux_in_sop_q      = 0                 ;// M Mux in start of packet
      logic [M-1:0][N-1:0]              M_mux_in_eop                            ;// M Mux in end of packet
      logic [M-1:0][N-1:0]              M_mux_in_eop_q      = 0                 ;// M Mux in end of packet
      logic [M-1:0][N-1:0]              M_mux_in_valid                          ;// M Mux in data valid
      logic [M-1:0][N-1:0]              M_mux_in_valid_q    = 0                 ;// M Mux in data valid
      logic [M-1:0]                     M_mux_out_ready                         ;// M Mux output ready from next stage logic
      logic [M-1:0][N-1:0]              M_mux_in_ready                          ;// M mux_in_valid & mux_in_ready indicates data is transferred to output
      logic [M-1:0][WIDTH-1:0]          M_mux_out_data                          ;// M Mux out data
      logic [M-1:0]                     M_mux_out_valid                         ;// M Mux out data valid
      logic [M-1:0]                     M_out_q_err                             ;// M Mux out queue FIFO error
      logic [M-1:0]                     M_out_q_perr                            ;// M Mux out queue FIFO parity error
                                                                                 //
      logic [N-1:0][M-1:0][WIDTH-1:0]   N_mux_in_data                           ;// N Mux in data
      logic [N-1:0][M-1:0][WIDTH-1:0]   N_mux_in_data_q     = 0                 ;// N Mux in data
      logic [N-1:0][M-1:0]              N_mux_in_sop                            ;// N Mux in data start of packet
      logic [N-1:0][M-1:0]              N_mux_in_sop_q      = 0                 ;// N Mux in data start of packet
      logic [N-1:0][M-1:0]              N_mux_in_eop                            ;// N Mux in data end of packet
      logic [N-1:0][M-1:0]              N_mux_in_eop_q      = 0                 ;// N Mux in data end of packet registered
      logic [N-1:0][M-1:0]              N_mux_in_valid                          ;// M Mux in data valid
      logic [N-1:0][M-1:0]              N_mux_in_valid_q    = 0                 ;// M Mux in data valid
      logic [N-1:0]                     N_mux_out_ready                         ;// N Mux output ready from next stage logic
      logic [N-1:0][M-1:0]              N_mux_in_ready                          ;// N mux_in_valid & mux_in_ready indicates data is transferred to output
      logic [N-1:0][WIDTH-1:0]          N_mux_out_data                          ;// N Mux out data
      logic [N-1:0]                     N_mux_out_valid                         ;// N Mux out data valid
      logic [N-1:0]                     N_out_q_err                             ;// N Mux out queue FIFO error
      logic [N-1:0]                     N_out_q_perr                            ;// N Mux out queue FIFO parity error
                                                                                 // 
      always@(*) begin                                                           // 
          for(i=0; i<M; i++)                                                     // 
              for (j=0; j<N; j++) begin                                          // N_mux/M_mux connections
                   M_mux_in_data    [i][j] = N_in_data      [j]                 ;// 
                   M_mux_in_sop     [i][j] = N_in_sop       [j][i]              ;// 
                   M_mux_in_eop     [i][j] = N_in_eop       [j][i]              ;//  
                   M_mux_in_valid   [i][j] = N_in_valid     [j][i]              ;// 
                   M_in_ready       [i][j] = N_mux_in_ready [j][i]              ;// 
                   N_mux_in_data    [j][i] = M_in_data      [i]                 ;// 
                   N_mux_in_sop     [j][i] = M_in_sop       [i][j]              ;// 
                   N_mux_in_eop     [j][i] = M_in_eop       [i][j]              ;// 
                   N_mux_in_valid   [j][i] = M_in_valid     [i][j]              ;// 
                   N_in_ready       [j][i] = M_mux_in_ready [i][j]              ;// 
              end                                                                // 
                   M_mux_out_ready     =     M_out_ready                        ;// 
                   M_out_data          =     M_mux_out_data                     ;// 
                   M_out_valid         =     M_mux_out_valid                    ;// 
                   N_mux_out_ready     =     N_out_ready                        ;// 
                   N_out_data          =     N_mux_out_data                     ;// 
                   N_out_valid         =     N_mux_out_valid                    ;// 
                   out_q_err           =    |N_out_q_err                         //
                                       |    |M_out_q_err                        ;//
                   out_q_perr          =    |N_out_q_perr                        //
                                       |    |M_out_q_perr                       ;//
      end                                                                        //                                                                                // 
         ase_emul_Nmux #(.WIDTH     (   WIDTH    )                              ,// Port Data Width
                         .DEPTH     (   DEPTH    )                              ,// out_q fifo depth = 2**DEPTH
                         .N         (   N        )                               // Number of input ports to mux
                        )                                                        //
          M_mux [M-1:0] (                                                        // Mux from M ports to N ports
                                M_mux_in_data                                   ,// Mux in data 
                                M_mux_in_sop                                    ,// Mux in start of packet
                                M_mux_in_eop                                    ,// Mux in end of packet
                                M_mux_in_valid                                  ,// Mux in data valid
                                M_mux_out_ready                                 ,// output ready from next stage logic
                                rst_n                                           ,// reset low active
                                clk                                             ,// clock
                                                                                 //
                                M_mux_in_ready                                  ,// mux_in_valid & mux_in_ready indicates data is transferred to output
                                M_mux_out_data                                  ,// Mux out data
                                M_mux_out_valid                                 ,// Mux out data valid
                                M_out_q_err                                     ,//
                                M_out_q_perr                                     //
                        )                                                       ;//
                                                                                 //
         ase_emul_Nmux #(.WIDTH     (   WIDTH    )                              ,// Port Data Width
                         .DEPTH     (   DEPTH    )                              ,// out_q fifo depth = 2**DEPTH
                         .N         (   M        )                               // Number of input ports to mux
                        )                                                        //
          N_mux [N-1:0] (                                                        // Mux from N ports to M ports
                                N_mux_in_data                                   ,// Mux in data
                                N_mux_in_sop                                    ,// Mux in start of packet
                                N_mux_in_eop                                    ,// Mux in end of packet
                                N_mux_in_valid                                  ,// Mux in data valid
                                N_mux_out_ready                                 ,// output ready from next stage logic
                                rst_n                                           ,// reset low active
                                clk                                             ,// clock
                                                                                 //
                                N_mux_in_ready                                  ,// mux_in_valid & mux_in_ready indicates data is transferred to output
                                N_mux_out_data                                  ,// Mux out data
                                N_mux_out_valid                                 ,// Mux out data valid
                                N_out_q_err                                     ,//
                                N_out_q_perr                                     //
                        )                                                       ;//
endmodule                                                                 
