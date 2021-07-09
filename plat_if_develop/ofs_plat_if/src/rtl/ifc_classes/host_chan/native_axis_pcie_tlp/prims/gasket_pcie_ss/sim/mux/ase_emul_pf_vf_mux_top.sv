// ***************************************************************************
//                               INTEL CONFIDENTIAL
//
//        Copyright (C) 2020 Intel Corporation All Rights Reserved.
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
// You will not, and will not allow any third party to modify, adapt, enhance, 
// disassemble, decompile, reverse engineer, change or create derivative works 
// from the Software except and only to the extent as specifically required by 
// mandatory applicable laws or any applicable third party license terms 
// accompanying the Software.
//
// -----------------------------------------------------------------------------
// Create Date  : Nov 2020
// Module Name  : pf_vf_demux.sv
// Project      : IOFS
// -----------------------------------------------------------------------------
//
// Description: 
//
// A Wrapper that connects host and pfvf interface to switch ports + avst/axi conversion
// switch is M X N mux structures that allows any M port to target any N port, and
// any N port to target any M port.  Each M or N port has an arbitor to handle
// multiple inputs.  Switch is common for AXI and AVST streaming.  The protocol 
// signals of AXI/AVST pass the switch as data.  Only ready, valid, and last/end_of_packet
// are used to handshake.  User can define number of N and M ports which are 
// parameterized; however, the wider the bus, the more limits on number of ports, 
// due to the timing and routing contraints of FPGA. If necessary, multiple stages 
// of switch can be connected in hierarchical fasion.  The switch contains
// a fifo to handle handshake delays (such as ready), therefore capable of
// proper handshakes and data trasnfers between multiple stages.
//
// 
// ***************************************************************************
//  
// 

//==============================================================================================================================================================
//                                     PF/VF Mux/Switch Main 
//==============================================================================================================================================================
                                                                                     //
module ase_emul_pf_vf_mux_top                                                                 //
        #(
          parameter string       MUX_NAME = ""                                      ,// Name for logging in a multi-PF/VF MUX system
          parameter string       LOG_FILE_NAME = ""                                 ,// Override the default log name if specified
          parameter              M          = 1                                     ,// Number of Host/Upstream ports
          parameter              N          = 1                                      // Number of Function/Downstream ports
          )
         (                                                                           // 1. assign each function with a specific pf/vf
          input                  clk                                                ,// 2. connect each pf/vf to one of mux ports (rx + tx) in afu_top
          input                  rst_n                                              ,// 3. modify pf/vf to port routing (pfvf_to_port function in ofs_r1_cfg)
                                                                                     //
          pcie_ss_axis_if.sink   ho2mx_rx_port                                      ,// 
          pcie_ss_axis_if.source mx2ho_tx_port                                      ,//
          pcie_ss_axis_if.source mx2fn_rx_port  [N-1:0]                             ,//
          pcie_ss_axis_if.sink   fn2mx_tx_port  [N-1:0]                             ,//
          output logic           out_fifo_err                                       ,// output fifo error
          output logic           out_fifo_perr                                       // output fifo parity error
          );                                                                         //
                                                                                     //
          localparam             D_WIDTH    = ofs_pcie_ss_cfg_pkg::TDATA_WIDTH      ;// Port Data Width
          localparam             USER_WIDTH = 10                                    ;// USER field width
          localparam             ERR_WIDTH  = 10                                    ;// ERROR field width
          localparam             DEPTH      = 1                                     ;// out_q fifo depth = 2**DEPTH
                                                                                     //-------------- AVST-----------------------
          localparam             DATA_LSB   = 0                                     ;//  if.data bit position of data LSB
          localparam             DATA_MSB   = D_WIDTH   - 1                         ;//  if.data bit position of data MSB
          localparam             VALID      = DATA_MSB  + 1                         ;//  if.data bit position of valid bit 
          localparam             END        = VALID     + 1                         ;//  if.data bit position of end of pakcet 
          localparam             START      = END       + 1                         ;//  if.data bit position of start of pakcet (for internal logic)
          localparam             ERR_LSB    = START     + 1                         ;//  if.data bit position of error LSB
          localparam             ERR_MSB    = START     + ERR_WIDTH                 ;//  if.data bit position of error MSB
          localparam             EMPTY_LSB  = ERR_MSB   + 1                         ;//  if.data bit position of empty LSB
          localparam             EMPTY_MSB  = ERR_MSB   + $clog2(D_WIDTH/8)         ;//  if.data bit position of empty MSB 
                                                                                     //------------- AXI ------------------------
          //                     DATA_LSB   = 0                                     ;//  if.data bit position of data LSB
          //                     DATA_MSB   = D_WIDTH   - 1                         ;//  if.data bit position of data MSB
          //                     VALID      = DATA_MSB  + 1                         ;//  if.data bit position of valid bit 
          localparam             LAST       = VALID     + 1                         ;//  if.data bit position of last
          //                     START      = LAST      + 1                         ;//  if.data bit position of start of pakcet 
          localparam             USER_LSB   = START     + 1                         ;//  if.data bit position of user LSB
          localparam             USER_MSB   = START     + USER_WIDTH                ;//  if.data bit position of user MSB
          localparam             KEEP_LSB   = USER_MSB  + 1                         ;//  if.data bit position of keep LSB 
          localparam             KEEP_MSB   = USER_MSB  + D_WIDTH/8                 ;//  if.data bit position of keep MSB 
          localparam             WIDTH      = KEEP_MSB  + 1                         ;//  if.data width
                                                                                     //                                                        
          localparam             VFPF_WIDTH = 14                                    ;//  virtual + physical function width
          localparam             VFPF_LSB   = 160                                   ;//  LSB postion of virtual/physical field
          localparam             VFPF_MSB   = VFPF_LSB + VFPF_WIDTH                 ;//  MSB postion of virtual/physical field
                                                                                     //
          localparam MID_WIDTH = $clog2(M);
          localparam NID_WIDTH = $clog2(N);

          logic  [M-1:0][WIDTH-1:0]    M_data                                       ;//  M input  port data  
          logic  [M-1:0]               M_sop                                        ;//  M input  port start of packet
          logic  [M-1:0]               M_sop_en                                     ;//  M input  port start of packet
          logic  [M-1:0]               M_valid                                      ;//  M input  port valid
          logic  [M-1:0]               M_ready                                      ;//  M input  port ready/grant
          logic  [M-1:0][N-1:0]        M_in_sop                                     ;//  M input  port start of packet (decoded bit vector)
          logic  [M-1:0][N-1:0]        M_in_eop                                     ;//  M input  port end of packet (decoded bit vector)
          logic  [M-1:0][N-1:0]        M_in_valid                                   ;//  M input  port data valid (decoded bit vector)
          logic  [M-1:0]               M_out_ready                                  ;//  M output port ready from next stage logic
          logic  [M-1:0]               M_out_sop                                    ;//  M port out sop for dispaly message
          logic  [M-1:0][N-1:0]        M_in_ready                                   ;//  M input  port ready/grant 
          logic  [M-1:0]               M_out_valid                                  ;//  M output port data valid
          logic  [M-1:0][WIDTH-1:0]    M_out_data                                   ;//  M output port data
          logic  [M-1:0][NID_WIDTH:0]  M_TID                                        ;//  M to N   port destination ID
          logic  [M-1:0][NID_WIDTH:0]  M_TID_q                                      ;//  M to N   port destination ID
          logic  [N-1:0][WIDTH-1:0]    N_data                                       ;//  N input  port data  
          logic  [N-1:0]               N_sop                                        ;//  N input  port start of packet
          logic  [N-1:0]               N_sop_en                                     ;//  N input  port start of packet
          logic  [N-1:0]               N_valid                                      ;//  N input  port valid
          logic  [N-1:0]               N_valid_q                                    ;//  N input  port valid 1 clk delay
          logic  [N-1:0]               N_ready                                      ;//  N input  port ready/grant
          logic  [N-1:0][M-1:0]        N_in_sop                                     ;//  N input  start of packet (decoded bit vector)
          logic  [N-1:0][M-1:0]        N_in_eop                                     ;//  N input  end of packet (decoded bit vector)
          logic  [N-1:0][M-1:0]        N_in_valid                                   ;//  N input  port data valid (decoded bit vector)
          logic  [N-1:0]               N_out_ready                                  ;//  N output port ready from next stage logic
          logic  [N-1:0][M-1:0]        N_in_ready                                   ;//  N input  port ready/grant 
          logic  [N-1:0]               N_out_valid                                  ;//  N output port data valid
          logic  [N-1:0][WIDTH-1:0]    N_out_data                                   ;//  N output port data
          logic  [N-1:0]               N_out_sop                                    ;//  N port out sop for dispaly message
          logic  [N-1:0][MID_WIDTH:0]  N_TID                                        ;//  N to M   port destination ID
          logic  [N-1:0][MID_WIDTH:0]  N_TID_q                                      ;//  N to M   port destination ID
          logic                        out_q_err                                    ;//
          logic                        out_q_perr                                   ;//
          logic  [7:0]                 ho2mx_rx_tag                                 ;//
          logic  [8:0]                 ho2mx_rx_pfvf                                ;//
          logic  [7:0]                 ho2mx_rx_cycle                               ;//
          logic  [7:0]                 mx2ho_tx_tag                                 ;//
          logic  [8:0]                 mx2ho_tx_pfvf                                ;//
          logic  [7:0]                 mx2ho_tx_cycle                               ;//
          integer                      p                                            ;//  port index
                                                                                     //  
    localparam PFVF_WIDTH = pcie_ss_hdr_pkg::PF_WIDTH +
                            pcie_ss_hdr_pkg::VF_WIDTH + 1;

    function automatic [NID_WIDTH:0] pfvf_to_port(input [PFVF_WIDTH-1:0] pfvf);
        // For simulation, port index is just the VF index. The field
        // is layed out { VF index, VF active, PF index }.
        return pfvf[pcie_ss_hdr_pkg::PF_WIDTH+1 +: NID_WIDTH];
    endfunction

    always @(*) begin                                                                //  
       for (p=0; p<M; p++) begin                                                     // sop detection using valid and eop signals:
           M_sop      [p]           =  M_data [p][VALID] & M_sop_en [p]             ;//
           M_TID      [p]           =  M_sop  [p]                                    // host header? decode header: previous latched header
                                    ?  pfvf_to_port(M_data[p][VFPF_MSB:VFPF_LSB])    // VF_ACT[174]/VF_NUM[173:163]/PF_NUM[162:160]
                                    :  M_TID_q                                      ;// pfvf_to_port function (defined in ofs_cfg_pkg)
           M_in_valid [p]           =  0                                            ;//(must match pv/vf port mapping to switch port)
           M_in_sop   [p]           =  0                                            ;// 
           M_in_eop   [p]           =  0                                            ;// decode target and assert bit-vector valid
           M_in_valid [p][M_TID[p]] =  M_data    [p][VALID]                         ;// there are N valid bits.  1 for each target
           M_in_sop   [p][M_TID[p]] =  M_sop     [p]                                ;//
           M_in_eop   [p][M_TID[p]] =  M_data    [p][VALID] & M_data[p][END]        ;// 
           M_ready    [p]           =  M_in_ready[p][M_TID[p]]                      ;//
           M_out_sop  [p]           =  M_out_data[p][START]                         ;//
       end                                                                           //        
                                                                                     //
       for (p=0; p<N; p++) begin                                                     // sop detection using valid and eop signals:
           N_sop      [p]           =  N_data    [p][VALID] & N_sop_en [p]          ;// 
           N_TID      [p]           =  0                                            ;//
           N_in_valid [p]           =  0                                            ;// decode target and assert bit-vector valid
           N_in_sop   [p]           =  0                                            ;// there are M valid bits.  1 for each target
           N_in_eop   [p]           =  0                                            ;//
           N_in_valid [p][N_TID[p]] =  N_data    [p][VALID]                         ;//
           N_in_sop   [p][N_TID[p]] =  N_sop     [p]                                ;//
           N_in_eop   [p][N_TID[p]] =  N_data    [p][VALID] & N_data[p][END]        ;//
           N_ready    [p]           =  N_in_ready[p][N_TID[p]]                      ;//
           N_out_sop  [p]           =  N_out_data[p][START]                         ;//
       end                                                                           //
                                                         /* synthesis translate_off */  
       if (M_sop[0]) begin                                                           // simulation debug signals
           ho2mx_rx_pfvf  ={ho2mx_rx_port.tdata[174]                                ,//
                            1'b0                                                    ,//
                            ho2mx_rx_port.tdata[162:160]                            ,//
                            ho2mx_rx_port.tdata[166:163]}                           ;//
           ho2mx_rx_tag   = ho2mx_rx_port.tdata[ 47: 40]                            ;//
           ho2mx_rx_cycle = ho2mx_rx_port.tdata[ 31: 24]                            ;//
       end                                                                           //
                                                                                     //
       if (M_out_sop[0]) begin                                                       // simulation debug signals
           mx2ho_tx_pfvf  ={mx2ho_tx_port.tdata[174]                                ,//
                            1'b0                                                    ,//
                            mx2ho_tx_port.tdata[162:160]                            ,//
                            mx2ho_tx_port.tdata[166:163]}                           ;//
           mx2ho_tx_tag   = mx2ho_tx_port.tdata[ 47: 40]                            ;//
           mx2ho_tx_cycle = mx2ho_tx_port.tdata[ 31: 24]                            ;//
       end                                                /* synthesis translate_on */
    end                                                                              //
                                                                                     //
    always @(posedge clk) begin                                                      //
                                                                                     //
       out_fifo_err  <= out_q_err                                                   ;//
       out_fifo_perr <= out_q_perr                                                  ;//
                                                                                     //
       for (p=0; p<M; p++) begin                                                     // 
                        M_valid  [p]<= M_data[p][VALID]                             ;//
           if (M_sop[p])M_TID_q  [p]<= M_TID [p]                                    ;// latch target ID upon sop and until eop
                                                                                     //
           if ( M_data[p][VALID]                                                     // enable sop detection
              & M_ready  [p]                                                         //
              )                                                                      //
              begin                                                                  //
                  if (  M_sop  [p])   M_sop_en [p] <= 0                             ;// enable detection between eop and sop
                  if (M_data[p][END]) M_sop_en [p] <= 1                             ;// 
              end                                                                    //
       end                                                                           //
                                                                                     //
       for (p=0; p<N; p++) begin                                                     // registers needed for sop detection
                        N_valid_q[p]<= N_data[p][VALID]                             ;// latch target ID upon sop and until eop
           if (N_sop[p])N_TID_q  [p]<= N_TID [p]                                    ;//
                                                                                     //
           if ( N_data[p][VALID]                                                     // enable sop detection
              & N_ready  [p]                                                         //
              )                                                                      // 
              begin                                                                  //
                  if (  N_sop  [p])   N_sop_en [p] <= 0                             ;// enable detection between eop and sop
                  if (N_data[p][END]) N_sop_en [p] <= 1                             ;// 
              end                                                                    //
       end                                                                           //
                                                                                     //
       if (!rst_n) begin                                                             // 
                               N_sop_en   <= ~0                                     ;//
                               M_sop_en   <= ~0                                     ;//
           for (p=0; p<M; p++) M_TID_q[p] <=  0                                     ;// reset
           for (p=0; p<N; p++) N_TID_q[p] <=  0                                     ;// 
       end                                                                           // 
                                                                                     //
                                                                                     /* synthesis translate_off */   
       if (rst_n & out_q_err ) $display("T=%e <<<<<<<<<<<<<<<ERROR: PF/VF OUTPUT FIFO ERROR>>>>>>>>>>>>>>>>",$time);
       if (rst_n & out_q_perr) $display("T=%e <<<<<<<<<<<<<<<ERROR: PF/VF OUTPUT PARITY ERROR>>>>>>>>>>>>>>",$time); 
                                                                                     /* synthesis translate_on */
    end                                                                              //
  //----------------------------------------------------------------------------------------------------------------------------------------------------------
  //               port data   port ready  port valid/sop  interface                 // interface to switch port mapping
  //----------------------------------------------------------------------------------------------------------------------------------------------------------
  ase_emul_pf_vf_axi_port_map                                                                       //
   #(
     .WIDTH(WIDTH),
     .START(START),
     .LAST(LAST),
     .VALID(VALID),
     .DATA_MSB(DATA_MSB),
     .DATA_LSB(DATA_LSB),
     .USER_MSB(USER_MSB),
     .USER_LSB(USER_LSB),
     .KEEP_MSB(KEEP_MSB),
     .KEEP_LSB(KEEP_LSB)
    )
  host_axi[M-1:0] (M_data    , M_ready    , M_sop      , ho2mx_rx_port  ,            // AXI to mux signals mapping
                   M_out_data, M_out_ready, M_out_valid, mx2ho_tx_port  )           ;// host
  ase_emul_pf_vf_axi_port_map                                                                       //
   #(
     .WIDTH(WIDTH),
     .START(START),
     .LAST(LAST),
     .VALID(VALID),
     .DATA_MSB(DATA_MSB),
     .DATA_LSB(DATA_LSB),
     .USER_MSB(USER_MSB),
     .USER_LSB(USER_LSB),
     .KEEP_MSB(KEEP_MSB),
     .KEEP_LSB(KEEP_LSB)
    )
  mux_axi [N-1:0] (N_data    , N_ready    , N_sop      , fn2mx_tx_port  ,            // downstream ports
                   N_out_data, N_out_ready, N_out_valid, mx2fn_rx_port  )           ;// 
                                                                                     //
                              ase_emul_mux_switch  # (                               // M X N switch with output FIFO
                                        .WIDTH       (    WIDTH      )              ,// Port Data Width                              
                                        .M           (    M          )              ,// Number of M Ports 
                                        .N           (    N          )              ,// Number of N Ports 
                                        .DEPTH       (    DEPTH      )               // FIFO Depth=2**DEPTH 
                                        )                                            // 
                              switch   (                                             // ----------- input -----------------------------------
                                         M_data                                     ,// Mux M to N ports data in 
                                         M_in_sop                                   ,// Mux M to N ports end of packet
                                         M_in_eop                                   ,// Mux M to N ports end of packet
                                         M_in_valid                                 ,// Mux M to N ports data in valid
                                         M_out_ready                                ,// Mux M to N ports data out ready from next stage logic
                                         N_data                                     ,// Mux N to M data in 
                                         N_in_sop                                   ,// Mux N to M data in end of packet
                                         N_in_eop                                   ,// Mux N to M data in end of packet
                                         N_in_valid                                 ,// Mux N to M data in valid
                                         N_out_ready                                ,// Mux N to M data out ready from next stage logic 
                                         rst_n                                      ,// reset low active
                                         clk                                        ,// clock
                                                                                     //----------  output ----------------------------------
                                         M_in_ready                                 ,// Mux M to N ready 
                                         M_out_valid                                ,// Mux M to N out valid
                                         M_out_data                                 ,// Mux M to N data out
                                         N_in_ready                                 ,// Mux N to M ready 
                                         N_out_valid                                ,// Mux N to M out valid
                                         N_out_data                                 ,// Mux N to M data out
                                         out_q_err                                  ,// N/M out_q FIFO error
                                         out_q_perr                                  // N/M out_q FIFO error
                                        )                                           ;//   
        

//==============================================================================================================================================================
//                               Log traffic to a file (simulation)
//==============================================================================================================================================================

    // synthesis translate_off
    static int log_fd;

    initial
    begin : log
        automatic string mux_tag = (MUX_NAME == "") ? "" : {"_", MUX_NAME};

        // Open a log file, using a default if the parent didn't specify a name.
        log_fd = $fopen(((LOG_FILE_NAME == "") ? {"log_pf_vf_mux", mux_tag, ".tsv"} : LOG_FILE_NAME), "w");

        // Write module hierarchy to the top of the log
        $fwrite(log_fd, "pf_vf_mux_top.sv: %m\n\n");

        forever @(posedge clk) begin
            // FIM to MUX (RX)
            if(rst_n && ho2mx_rx_port.tvalid && ho2mx_rx_port.tready)
            begin
                $fwrite(log_fd, "From_FIM:   %s\n",
                        pcie_ss_pkg::func_pcie_ss_flit_to_string(
                            M_sop[0], ho2mx_rx_port.tlast,
                            pcie_ss_hdr_pkg::func_hdr_is_pu_mode(ho2mx_rx_port.tuser_vendor),
                            ho2mx_rx_port.tdata, ho2mx_rx_port.tkeep));
                $fflush(log_fd);
            end

            // MUX to FIM (TX)
            if(rst_n && mx2ho_tx_port.tvalid && mx2ho_tx_port.tready)
            begin
                $fwrite(log_fd, "To_FIM:     %s\n",
                        pcie_ss_pkg::func_pcie_ss_flit_to_string(
                            M_out_sop[0], mx2ho_tx_port.tlast,
                            pcie_ss_hdr_pkg::func_hdr_is_pu_mode(mx2ho_tx_port.tuser_vendor),
                            mx2ho_tx_port.tdata, mx2ho_tx_port.tkeep));
                $fflush(log_fd);
            end
        end
    end

    generate
        // Ports to AFU
        for (genvar i = 0; i < N; i = i + 1) begin : port
            always @(posedge clk) begin
                // Traffic heading toward the FIM
                if(rst_n && fn2mx_tx_port[i].tvalid && fn2mx_tx_port[i].tready)
                begin
                    $fwrite(log_fd, "From_PORT%0d: %s\n", i,
                            pcie_ss_pkg::func_pcie_ss_flit_to_string(
                                N_sop[i], fn2mx_tx_port[i].tlast,
                                pcie_ss_hdr_pkg::func_hdr_is_pu_mode(fn2mx_tx_port[i].tuser_vendor),
                                fn2mx_tx_port[i].tdata, fn2mx_tx_port[i].tkeep));
                    $fflush(log_fd);
                end

                // Traffic heading toward the AFU
                if(rst_n && mx2fn_rx_port[i].tvalid && mx2fn_rx_port[i].tready)
                begin
                    $fwrite(log_fd, "  To_PORT%0d: %s\n", i,
                            pcie_ss_pkg::func_pcie_ss_flit_to_string(
                                N_out_sop[i], mx2fn_rx_port[i].tlast,
                                pcie_ss_hdr_pkg::func_hdr_is_pu_mode(mx2fn_rx_port[i].tuser_vendor),
                                mx2fn_rx_port[i].tdata, mx2fn_rx_port[i].tkeep));
                    $fflush(log_fd);
                end
            end
        end
    endgenerate
    // synthesis translate_on

endmodule                                                                             //

//==============================================================================================================================================================
//                                         Port Mapping of AXI to switch port
//==============================================================================================================================================================
module ase_emul_pf_vf_axi_port_map
               #(
                 parameter WIDTH,
                 parameter START,
                 parameter LAST,
                 parameter VALID,
                 parameter DATA_MSB,
                 parameter DATA_LSB,
                 parameter USER_MSB,
                 parameter USER_LSB,
                 parameter KEEP_MSB,
                 parameter KEEP_LSB
                )
                (                                                                     //
                 output  [WIDTH-1:0]               in_port_data                      ,// switch port in data
                 input                             in_port_ready                     ,// switch port in ready
                 input                             in_port_sop                       ,// swtich port in sop (header valid)
                 pcie_ss_axis_if.sink              in_interface                      ,// axi in interface
                 input   [WIDTH-1:0]               out_port_data                     ,// switch port out data
                 output                            out_port_ready                    ,// switch port out ready
                 input                             out_port_valid                    ,// switch port out valid
                 pcie_ss_axis_if.source            out_interface                      // axi out interface
                )                                                                    ;// map interface signals to port data bits
        assign  in_port_data [KEEP_MSB:KEEP_LSB] = in_interface.tkeep                ;// only valid, ready, and last/eop are used for handshake 
        assign  in_port_data [USER_MSB:USER_LSB] = in_interface.tuser_vendor         ;//  
        assign  in_port_data [START            ] = in_port_sop                       ;//  
        assign  in_port_data [LAST             ] = in_interface.tlast                ;//  
        assign  in_port_data [VALID            ] = in_interface.tvalid               ;//  
        assign  in_port_data [DATA_MSB:DATA_LSB] = in_interface.tdata                ;//  
        assign  in_interface.tready              = in_port_ready                     ;//  
                                                                                      //  
        assign  out_interface.tkeep              = out_port_data[KEEP_MSB:KEEP_LSB]  ;//  
        assign  out_interface.tuser_vendor       = out_port_data[USER_MSB:USER_LSB]  ;//  
        assign  out_interface.tlast              = out_port_data[LAST]               ;//  
        assign  out_interface.tvalid             = out_port_valid                    ;//  
        assign  out_interface.tdata              = out_port_data[DATA_MSB:DATA_LSB]  ;//  
        assign  out_port_ready                   = out_interface.tready              ;//  
endmodule                                                                             //
