// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

// $Id: //acds/rel/24.1/ip/iconnect/merlin/altera_merlin_waitrequest_adapter/altera_merlin_waitrequest_adapter.v#2 $
// $Revision: #2 $
// $Date: 2024/02/21 $

`timescale 1 ns / 1 ns
`default_nettype none

module ofs_plat_utils_merlin_waitrequest_adapter # (
   parameter 
      UAV_ADDRESS_W                 = 32,
      UAV_DATA_W                    = 32,
      UAV_BURSTCOUNT_W              = 10,
      UAV_RESPONSE_W                = 2,
      UAV_BYTEENABLE_W              = 4,

      // Optional
      USE_WRITERESPONSE             = 1,
      USE_READRESPONSE              = 1,

      S0_WAITREQUEST_ALLOWANCE      = 1,     // Master waitrequest allowance
      M0_WAITREQUEST_ALLOWANCE      = 0,     // Slave waitrequest allowance
      SYNC_RESET                    = 0

)(
   input wire                             clk,
   input wire                             reset,

   // Universal Avalon Master
   input wire                             s0_write,
   input wire                             s0_read,
   input wire [UAV_ADDRESS_W -1 : 0]      s0_address,
   input wire [UAV_BURSTCOUNT_W -1 : 0]   s0_burstcount,
   input wire [UAV_BYTEENABLE_W -1 : 0]   s0_byteenable,
   input wire [UAV_DATA_W -1 : 0]         s0_writedata,
   input wire                             s0_lock,
   input wire                             s0_debugaccess,

   output wire [UAV_DATA_W -1 : 0]        s0_readdata,
   output wire                            s0_readdatavalid,
   output wire                            s0_waitrequest,
   output wire [UAV_RESPONSE_W -1 : 0]    s0_response,
   output wire                            s0_writeresponsevalid,

   // Universal Avalon Master
   output wire                            m0_write,
   output wire                            m0_read,
   output wire [UAV_ADDRESS_W -1 : 0]     m0_address,
   output wire [UAV_BURSTCOUNT_W -1 : 0]  m0_burstcount,
   output wire [UAV_BYTEENABLE_W -1 : 0]  m0_byteenable,
   output wire [UAV_DATA_W -1 : 0]        m0_writedata,
   output wire                            m0_lock,
   output wire                            m0_debugaccess,

   input wire [UAV_DATA_W -1 : 0]         m0_readdata,
   input wire                             m0_readdatavalid,
   input wire                             m0_waitrequest,
   input wire [UAV_RESPONSE_W -1 : 0]     m0_response,
   input wire                             m0_writeresponsevalid
);

   // Local parameters
   localparam SYMBOL_W        = 8;
   localparam WRITE_W         = 1;
   localparam READ_W          = 1;
   localparam LOCK_W          = 1;
   localparam DEBUGACCESS_W   = 1;

   localparam PAYLOAD_W    = WRITE_W + READ_W + LOCK_W + DEBUGACCESS_W + 
                             UAV_ADDRESS_W + UAV_DATA_W + UAV_BYTEENABLE_W + UAV_BURSTCOUNT_W ;

   localparam LOG_IN_WAIT  = $clog2(S0_WAITREQUEST_ALLOWANCE);     
   localparam LOG_OUT_WAIT = $clog2(M0_WAITREQUEST_ALLOWANCE);
   localparam DIFF_WAITREQ = (S0_WAITREQUEST_ALLOWANCE > M0_WAITREQUEST_ALLOWANCE) ? 
                             (S0_WAITREQUEST_ALLOWANCE - M0_WAITREQUEST_ALLOWANCE) : 
                             (M0_WAITREQUEST_ALLOWANCE - S0_WAITREQUEST_ALLOWANCE);

   // For master_gt0_slave_eq0
   localparam USE_MEMORY = (S0_WAITREQUEST_ALLOWANCE > 2);
   // Add more buffer in FIFO so waitreq does not assert waitreq on very
   // first transaction - hence 2**(LOG_IN+WAIT+1)
   // so buffer is getting 2X here, but we dont want too deep buffer
   // dont do this if (2Xrequired buffer - new_buffer) >6
   localparam FIFO_DEPTH = (USE_MEMORY == 1) ? 2**LOG_IN_WAIT : S0_WAITREQUEST_ALLOWANCE + 2;
   localparam BUFFER_2X = 2*S0_WAITREQUEST_ALLOWANCE;
   localparam FIFO_DEPTH_DEEPER = 2**(LOG_IN_WAIT+1);
   localparam FIFO_SIZE = ((FIFO_DEPTH_DEEPER-BUFFER_2X)>6) ? 2**LOG_IN_WAIT : FIFO_DEPTH_DEEPER ;
   localparam FIFO_DEPTH_M20K = (USE_MEMORY == 1) ? FIFO_SIZE : S0_WAITREQUEST_ALLOWANCE + 2;
   localparam EMPTY_LATENCY = (USE_MEMORY == 1) ? 3 : 0;
   localparam ALMOST_FULL_THRESHOLD = (USE_MEMORY == 1) ? (((FIFO_DEPTH % S0_WAITREQUEST_ALLOWANCE) == 0) ? 1 : (FIFO_DEPTH % S0_WAITREQUEST_ALLOWANCE)) 
                                                        : 2;
   localparam ALMOST_FULL_THRESHOLD_M20K = (USE_MEMORY == 1) ?  (ALMOST_FULL_THRESHOLD+4) : ALMOST_FULL_THRESHOLD ;
   localparam IMPL = (USE_MEMORY == 1) ? "infer" : "reg";

   localparam NUM_128BIT_SLOTS = (PAYLOAD_W / 128) + (((PAYLOAD_W % 128) == 0) ? 0 : 1);
   localparam LAST_PAYLOAD_W = ((PAYLOAD_W % 128) == 0) ? 128 : (PAYLOAD_W % 128); 
   genvar i;  

   wire [PAYLOAD_W-1:0] m0_payload;
   wire [PAYLOAD_W-1:0] s0_payload;

   wire m0_valid;
   wire fifo_pop;
   wire s0_valid = s0_read | s0_write;

   wire m0_payload_read;
   wire m0_payload_write;

   assign m0_write = m0_payload_write & m0_valid;
   assign m0_read = m0_payload_read & m0_valid;

   // Response Signals
   // Pass-through
   assign s0_readdata = m0_readdata;
   assign s0_readdatavalid = m0_readdatavalid;
   assign s0_response = m0_response;
   assign s0_writeresponsevalid = m0_writeresponsevalid;

   // Slave payload
   assign s0_payload = {
                          s0_write,
                          s0_read,
                          s0_address,
                          s0_burstcount,
                          s0_byteenable,
                          s0_writedata,
                          s0_lock,
                          s0_debugaccess
                         };

   // Master payload
   assign {
           m0_payload_write,
           m0_payload_read,
           m0_address,
           m0_burstcount,
           m0_byteenable,
           m0_writedata,
           m0_lock,
           m0_debugaccess
          } = m0_payload;
 

   // Generation of internal reset synchronization
   reg internal_sclr;
   generate if (SYNC_RESET == 1) begin : rst_syncronizer
      always @ (posedge clk) begin
         internal_sclr <= reset;
      end
   end
   endgenerate


   // Adapter core logic
   generate
      if(S0_WAITREQUEST_ALLOWANCE == M0_WAITREQUEST_ALLOWANCE) begin : eq_wait_req
         assign m0_payload = s0_payload;
         assign m0_valid = s0_valid;
         assign s0_waitrequest = m0_waitrequest;
      end
      
      if(S0_WAITREQUEST_ALLOWANCE == 0 && M0_WAITREQUEST_ALLOWANCE != 0) begin : master_eq0_slave_gt0
         assign m0_payload = s0_payload;
         assign m0_valid = s0_valid & ~m0_waitrequest;
         assign s0_waitrequest = m0_waitrequest;
      end
      
      if(S0_WAITREQUEST_ALLOWANCE > 0 && (S0_WAITREQUEST_ALLOWANCE < M0_WAITREQUEST_ALLOWANCE)) begin : master_lt_slave_neq0
         assign m0_valid = s0_valid;
         assign m0_payload = s0_payload;
         assign s0_waitrequest = m0_waitrequest;
      end
      
      if(S0_WAITREQUEST_ALLOWANCE > 0 && (M0_WAITREQUEST_ALLOWANCE == 0)) begin : master_gt0_slave_eq0
         wire fifo_data_valid;
         
         assign fifo_pop = fifo_data_valid & ~m0_waitrequest;
         assign m0_valid = fifo_data_valid;


         for (i = 0; i < NUM_128BIT_SLOTS; i = i + 1) begin : gen_inst
            if (i == NUM_128BIT_SLOTS - 1) begin
               altera_avalon_sc_fifo # (
                  .SYMBOLS_PER_BEAT       (1),
                  .BITS_PER_SYMBOL        (LAST_PAYLOAD_W),
                  .FIFO_DEPTH             (FIFO_DEPTH_M20K),
                  .EMPTY_LATENCY          (EMPTY_LATENCY), 
                  .USE_FILL_LEVEL         (1),
                  .USE_MEMORY_BLOCKS      (USE_MEMORY),
                  .USE_ALMOST_FULL_IF     (1),
                  .ALMOST_FULL_THRESHOLD  (ALMOST_FULL_THRESHOLD_M20K),
                  .SYNC_RESET             (SYNC_RESET)
               ) adapter_fifo (
                  .clk(clk),
                  .reset(reset),
                  
                  .in_data          (s0_payload[(i*128)+LAST_PAYLOAD_W-1:i*128]),
                  .in_valid         (s0_valid), // Write   
                  .in_startofpacket (1'b0),
                  .in_endofpacket   (1'b0),
                  .in_empty         (1'b0),
                  .in_error         (1'b0),
                  .in_channel       (1'b0),
                  .in_ready         (),
                  
                  .out_data         (m0_payload[(i*128)+LAST_PAYLOAD_W-1:i*128]),
                  .out_valid        (fifo_data_valid),
                  .out_startofpacket(),
                  .out_endofpacket  (),
                  .out_empty        (),
                  .out_error        (),
                  .out_channel      (),
                  
                  .out_ready        (fifo_pop),   // Read
                  .almost_full_data (s0_waitrequest)
                  
               );
            end
            else begin
               altera_avalon_sc_fifo # (
                  .SYMBOLS_PER_BEAT       (1),
                  .BITS_PER_SYMBOL        (128),
                  .FIFO_DEPTH             (FIFO_DEPTH_M20K),
                  .EMPTY_LATENCY          (EMPTY_LATENCY), 
                  .USE_FILL_LEVEL         (1),
                  .USE_MEMORY_BLOCKS      (USE_MEMORY),
                  .USE_ALMOST_FULL_IF     (1),
                  .ALMOST_FULL_THRESHOLD  (ALMOST_FULL_THRESHOLD_M20K),
                  .SYNC_RESET             (SYNC_RESET)
               ) adapter_fifo (
                  .clk(clk),
                  .reset(reset),
                  
                  .in_data          (s0_payload[(i+1)*128-1:i*128]),
                  .in_valid         (s0_valid), // Write   
                  .in_startofpacket (1'b0),
                  .in_endofpacket   (1'b0),
                  .in_empty         (1'b0),
                  .in_error         (1'b0),
                  .in_channel       (1'b0),
                  .in_ready         (),
                  
                  .out_data         (m0_payload[(i+1)*128-1:i*128]),
                  .out_valid        (),
                  .out_startofpacket(),
                  .out_endofpacket  (),
                  .out_empty        (),
                  .out_error        (),
                  .out_channel      (),
                  
                  .out_ready        (fifo_pop),   // Read
                  .almost_full_data ()
                  
               );
            end
         end
      end
   
      if(M0_WAITREQUEST_ALLOWANCE > 0 && (S0_WAITREQUEST_ALLOWANCE > M0_WAITREQUEST_ALLOWANCE)) begin
      
         reg [LOG_OUT_WAIT:0] count;
         wire fifo_data_valid;
         reg [S0_WAITREQUEST_ALLOWANCE - M0_WAITREQUEST_ALLOWANCE - 1 : 0]m0_waitrequest_q;
         if (SYNC_RESET == 0 ) begin // aysnc_reg0

            always @ (posedge clk, posedge reset) begin
                 if(reset) begin
                    count <= 'b0;
                 end
                 else begin
                    if(m0_waitrequest) begin
                       if(fifo_data_valid & (count < M0_WAITREQUEST_ALLOWANCE)) begin
                          count <= count + 1'b1;
                       end
                    end
                    else begin
                       count <= 'b0;
                    end
                 end
            end
         end // async_reg0
         else begin // sync_reg0
            always @ (posedge clk) begin
                 if(internal_sclr) begin
                    count <= 'b0;
                 end
                 else begin
                    if(m0_waitrequest) begin
                       if(fifo_data_valid & (count < M0_WAITREQUEST_ALLOWANCE)) begin
                          count <= count + 1'b1;
                       end
                    end
                    else begin
                       count <= 'b0;
                    end
                 end
            end
         end // sync_reg0


         if (SYNC_RESET == 0) begin // async_reg1   
            if(DIFF_WAITREQ == 1) begin
               always @ (posedge clk, posedge  reset) begin
                  if(reset) begin
                     m0_waitrequest_q <= m0_waitrequest;
                  end
                  else begin
                     m0_waitrequest_q <= m0_waitrequest;
                  end
               end
            end
            else if(DIFF_WAITREQ >= 2) begin
               always @ (posedge clk, posedge  reset) begin
                  if(reset) begin
                     m0_waitrequest_q <= m0_waitrequest;
                  end
                  else begin
                     m0_waitrequest_q <= {m0_waitrequest_q[DIFF_WAITREQ - 2 : 0], m0_waitrequest};
                  end
               end
            end

         end // async_reg1
         else begin //sync_reg1
            if(DIFF_WAITREQ == 1) begin
               always @ (posedge clk) begin
                  if(internal_sclr) begin
                     m0_waitrequest_q <= m0_waitrequest;
                  end
                  else begin
                     m0_waitrequest_q <= m0_waitrequest;
                  end
               end
            end
            else if(DIFF_WAITREQ >= 2) begin
               always @ (posedge clk) begin
                  if(internal_sclr) begin
                     m0_waitrequest_q <= m0_waitrequest;
                  end
                  else begin
                     m0_waitrequest_q <= {m0_waitrequest_q[DIFF_WAITREQ - 2 : 0], m0_waitrequest};
                  end
               end
            end
         end // sync_reg1
         
         assign m0_valid = fifo_data_valid & (~m0_waitrequest | (count < M0_WAITREQUEST_ALLOWANCE));
         assign fifo_pop = m0_valid;
         assign s0_waitrequest = m0_waitrequest | (|m0_waitrequest_q);

            if (S0_WAITREQUEST_ALLOWANCE-M0_WAITREQUEST_ALLOWANCE == 1) begin
            altera_avalon_st_pipeline_base # (
               .SYMBOLS_PER_BEAT       (1),
               .BITS_PER_SYMBOL        (PAYLOAD_W),
               .PIPELINE_READY         (0),
               .SYNC_RESET             (SYNC_RESET)
            ) adapter_single_stage_pipeline (

              .clk                    (clk),
              .reset                  (reset),

              .in_ready               (),
              .in_valid               (s0_valid),
              .in_data                (s0_payload),
              .out_ready              (fifo_pop),
              .out_valid              (fifo_data_valid),
              .out_data               (m0_payload)
              );
            end
            else begin
            altera_avalon_sc_fifo # (
               .SYMBOLS_PER_BEAT       (1),
               .BITS_PER_SYMBOL        (PAYLOAD_W),
               .FIFO_DEPTH             (S0_WAITREQUEST_ALLOWANCE - M0_WAITREQUEST_ALLOWANCE),
               .EMPTY_LATENCY          (0),   // Lookahead
               .USE_FILL_LEVEL         (1),
               .USE_MEMORY_BLOCKS      (0),
               .SYNC_RESET             (SYNC_RESET)
            ) adapter_fifo (
               .clk(clk),
               .reset(reset),
               
               .in_data          (s0_payload),
               .in_valid         (s0_valid), // Write   
               .in_startofpacket (1'b0),
               .in_endofpacket   (1'b0),
               .in_empty         (1'b0),
               .in_error         (1'b0),
               .in_channel       (1'b0),
               .in_ready         (),
               
               .out_data         (m0_payload),
               .out_valid        (fifo_data_valid),
               .out_startofpacket(),
               .out_endofpacket  (),
               .out_empty        (),
               .out_error        (),
               .out_channel      (),
               
               .out_ready        (fifo_pop)   // Read
               
               );
               end
      end
   endgenerate
endmodule

`default_nettype wire

