// Copyright 2020 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// Description
//-----------------------------------------------------------------------------
//
// AXIS pipeline register 
//
//-----------------------------------------------------------------------------

module ase_emul_pcie_ss_axis_register 
#( 
    parameter MODE                 = 0, // 0: skid buffer 1: simple buffer 2: simple buffer (bubble) 3: bypass
    parameter TREADY_RST_VAL       = 0, // 0: tready deasserted during reset 
                                        // 1: tready asserted during reset
    parameter ENABLE_TKEEP         = 1,
    parameter ENABLE_TLAST         = 1,
    parameter ENABLE_TID           = 0,
    parameter ENABLE_TDEST         = 0,
    parameter ENABLE_TUSER         = 0,
   
    parameter TDATA_WIDTH          = 32,
    parameter TID_WIDTH            = 8,
    parameter TDEST_WIDTH          = 8,
    parameter TUSER_WIDTH          = 1,

    // --------------------------------------
    // Derived parameters
    // --------------------------------------
    parameter TKEEP_WIDTH = TDATA_WIDTH / 8
)(
    input  logic                       clk,
    input  logic                       rst_n,

    output logic                       s_tready,
    input  logic                       s_tvalid,
    input  logic [TDATA_WIDTH-1:0]     s_tdata,
    input  logic [TKEEP_WIDTH-1:0]     s_tkeep, 
    input  logic                       s_tlast, 
    input  logic [TID_WIDTH-1:0]       s_tid, 
    input  logic [TDEST_WIDTH-1:0]     s_tdest, 
    input  logic [TUSER_WIDTH-1:0]     s_tuser, 
    
    input  logic                       m_tready,
    output logic                       m_tvalid,
    output logic [TDATA_WIDTH-1:0]     m_tdata,
    output logic [TKEEP_WIDTH-1:0]     m_tkeep, 
    output logic                       m_tlast, 
    output logic [TID_WIDTH-1:0]       m_tid, 
    output logic [TDEST_WIDTH-1:0]     m_tdest, 
    output logic [TUSER_WIDTH-1:0]     m_tuser 
);

generate 
if (MODE == 0) begin 
    // --------------------------------------
    // skid buffer
    // --------------------------------------
    
    // Registers & signals
    logic                          s_tvalid_reg; 
    logic [TDATA_WIDTH-1:0]        s_tdata_reg;
    logic [TKEEP_WIDTH-1:0]        s_tkeep_reg;
    logic                          s_tlast_reg; 
    logic [TID_WIDTH-1:0]          s_tid_reg;  
    logic [TDEST_WIDTH-1:0]        s_tdest_reg;  
    logic [TUSER_WIDTH-1:0]        s_tuser_reg;

    logic                          s_tready_pre;
    logic                          s_tready_reg;
    logic                          s_tready_reg_dup;
    logic                          use_reg;

    logic                          m_tvalid_pre; 
    logic [TDATA_WIDTH-1:0]        m_tdata_pre;
    logic [TKEEP_WIDTH-1:0]        m_tkeep_pre;
    logic                          m_tlast_pre; 
    logic [TID_WIDTH-1:0]          m_tid_pre;  
    logic [TDEST_WIDTH-1:0]        m_tdest_pre;  
    logic [TUSER_WIDTH-1:0]        m_tuser_pre;

    logic                          m_tvalid_reg;
    logic [TDATA_WIDTH-1:0]        m_tdata_reg;
    logic [TKEEP_WIDTH-1:0]        m_tkeep_reg;
    logic                          m_tlast_reg; 
    logic [TID_WIDTH-1:0]          m_tid_reg;  
    logic [TDEST_WIDTH-1:0]        m_tdest_reg;  
    logic [TUSER_WIDTH-1:0]        m_tuser_reg;

    // --------------------------------------
    // Pipeline stage
    //
    // s_tready is delayed by one cycle, master will see tready assertions one cycle later.
    // Buffer the data when tready transitions from high->low
    //
    // This implementation buffers idle cycles should tready transition on such cycles. 
    //     i.e. It doesn't take in new data from s_* even though m_tvalid=0 or when m_tready=0
    // This is a potential cause for throughput loss.
    // Not buffering idle cycles costs logic on the tready path.
    // --------------------------------------
    assign s_tready_pre = (m_tready || ~m_tvalid);
 
    always_ff @(posedge clk) begin
      if (~rst_n) begin
        s_tready_reg     <= (TREADY_RST_VAL == 0) ? 1'b0 : 1'b1;
        s_tready_reg_dup <= (TREADY_RST_VAL == 0) ? 1'b0 : 1'b1;
      end else begin
        s_tready_reg     <= s_tready_pre;
        s_tready_reg_dup <= s_tready_pre;
      end
    end
    
    // --------------------------------------
    // On the first cycle after reset, the pass-through
    // must not be used or downstream logic may sample
    // the same command twice because of the delay in
    // transmitting a rising tready.
    // --------------------------------------			    
    always_ff @(posedge clk) begin
       if (~rst_n) begin
          use_reg <= 1'b1;
       end else if (s_tready_pre) begin
          // stop using the buffer when s_tready_pre is high (m_tready=1 or m_tvalid=0)
          use_reg <= 1'b0;
       end else if (~s_tready_pre && s_tready_reg) begin
          use_reg <= 1'b1;
       end
    end
    
    always_ff @(posedge clk) begin
       if (~rst_n) begin
          s_tvalid_reg <= 1'b0;
       end else if (s_tready_reg_dup) begin
          s_tvalid_reg <= s_tvalid;
       end
    end

    always_ff @(posedge clk) begin
       if (s_tready_reg_dup) begin
          s_tdata_reg  <= s_tdata;
          s_tkeep_reg  <= s_tkeep;
          s_tlast_reg  <= s_tlast;
          s_tid_reg    <= s_tid;
          s_tdest_reg  <= s_tdest;
          s_tuser_reg  <= s_tuser;
       end
    end
     
    always_comb begin
       if (use_reg) begin
          m_tvalid_pre = s_tvalid_reg;
          m_tdata_pre  = s_tdata_reg;
          m_tkeep_pre  = s_tkeep_reg;
          m_tlast_pre  = s_tlast_reg;
          m_tid_pre    = s_tid_reg; 
          m_tdest_pre  = s_tdest_reg;
          m_tuser_pre  = s_tuser_reg;
       end else begin
          m_tvalid_pre = s_tvalid;
          m_tdata_pre  = s_tdata;
          m_tkeep_pre  = s_tkeep;
          m_tlast_pre  = s_tlast;
          m_tid_pre    = s_tid;
          m_tdest_pre  = s_tdest;
          m_tuser_pre  = s_tuser;
       end
    end
     
    // --------------------------------------
    // Master-Slave Signal Pipeline Stage 
    // --------------------------------------
    always_ff @(posedge clk) begin
       if (~rst_n) begin
          m_tvalid_reg <= 1'b0;
       end else if (s_tready_pre) begin
          m_tvalid_reg <= m_tvalid_pre;
       end
    end
    
    always_ff @(posedge clk) begin
       if (s_tready_pre) begin
          m_tdata_reg  <= m_tdata_pre;
          m_tkeep_reg  <= m_tkeep_pre;
          m_tlast_reg  <= m_tlast_pre;
          m_tid_reg    <= m_tid_pre;
          m_tdest_reg  <= m_tdest_pre;
          m_tuser_reg  <= m_tuser_pre;
       end
    end

    // Output assignment
    assign m_tvalid = m_tvalid_reg;
    assign m_tdata  = m_tdata_reg;
    assign m_tkeep  = ENABLE_TKEEP ? m_tkeep_reg : '0;
    assign m_tlast  = ENABLE_TLAST ? m_tlast_reg : 1'b0;
    assign m_tid    = ENABLE_TID   ? m_tid_reg   : '0;
    assign m_tdest  = ENABLE_TDEST ? m_tdest_reg : '0;
    assign m_tuser  = ENABLE_TUSER ? m_tuser_reg : '0;
    assign s_tready = s_tready_reg;

end else if (MODE == 1) begin 
   // --------------------------------------
   // Simple pipeline register 
   // --------------------------------------
   logic                          s_tready_pre;
   logic                          m_tvalid_reg;
   logic [TDATA_WIDTH-1:0]        m_tdata_reg;
   logic [TKEEP_WIDTH-1:0]        m_tkeep_reg;
   logic                          m_tlast_reg; 
   logic [TID_WIDTH-1:0]          m_tid_reg;  
   logic [TDEST_WIDTH-1:0]        m_tdest_reg;  
   logic [TUSER_WIDTH-1:0]        m_tuser_reg;

   assign s_tready_pre = (~m_tvalid || m_tready);

   always_ff @(posedge clk) begin
      if (s_tready_pre) begin
         m_tvalid_reg <= s_tvalid;
         m_tdata_reg  <= s_tdata;
         m_tkeep_reg  <= s_tkeep;
         m_tlast_reg  <= s_tlast;
         m_tid_reg    <= s_tid;
         m_tdest_reg  <= s_tdest;
         m_tuser_reg  <= s_tuser;
      end

      if (~rst_n) begin
         m_tvalid_reg <= 1'b0;
      end
   end

   // Output assignment
   assign m_tvalid = m_tvalid_reg;
   assign m_tdata  = m_tdata_reg;
   assign m_tkeep  = ENABLE_TKEEP ? m_tkeep_reg : '0;
   assign m_tlast  = ENABLE_TLAST ? m_tlast_reg : 1'b0;
   assign m_tid    = ENABLE_TID   ? m_tid_reg   : '0;
   assign m_tdest  = ENABLE_TDEST ? m_tdest_reg : '0;
   assign m_tuser  = ENABLE_TUSER ? m_tuser_reg : '0;
   assign s_tready = s_tready_pre;

end else if (MODE == 2) begin 
   // --------------------------------------
   // Simple pipeline register with bubble cycle
   // --------------------------------------
   logic                          s_tready_reg;
   logic                          m_tvalid_reg;
   logic [TDATA_WIDTH-1:0]        m_tdata_reg;
   logic [TKEEP_WIDTH-1:0]        m_tkeep_reg;
   logic                          m_tlast_reg; 
   logic [TID_WIDTH-1:0]          m_tid_reg;  
   logic [TDEST_WIDTH-1:0]        m_tdest_reg;  
   logic [TUSER_WIDTH-1:0]        m_tuser_reg;


   always_ff @(posedge clk) begin
      if (~rst_n) begin
         s_tready_reg <= 1'b0;
         m_tvalid_reg <= 1'b0;
      end else begin
        if (s_tready_reg && s_tvalid) begin
           s_tready_reg <= 1'b0;
           m_tvalid_reg <= 1'b1;
        end else if (~s_tready_reg && (m_tready || ~m_tvalid)) begin
           s_tready_reg <= 1'b1;
           m_tvalid_reg <= 1'b0;
        end
      end
   end

   always_ff @(posedge clk) begin
      if (s_tready_reg) begin
         m_tdata_reg  <= s_tdata;
         m_tkeep_reg  <= s_tkeep;
         m_tlast_reg  <= s_tlast;
         m_tid_reg    <= s_tid;
         m_tdest_reg  <= s_tdest;
         m_tuser_reg  <= s_tuser;
      end
   end
 
    // Output assignment
    assign m_tvalid = m_tvalid_reg;
    assign m_tdata  = m_tdata_reg;
    assign m_tkeep  = ENABLE_TKEEP ? m_tkeep_reg : '0;
    assign m_tlast  = ENABLE_TLAST ? m_tlast_reg : 1'b0;
    assign m_tid    = ENABLE_TID   ? m_tid_reg   : '0;
    assign m_tdest  = ENABLE_TDEST ? m_tdest_reg : '0;
    assign m_tuser  = ENABLE_TUSER ? m_tuser_reg : '0;
    assign s_tready = s_tready_reg;

end else begin 

   // --------------------------------------
   // bypass mode
   // --------------------------------------
   assign m_tvalid = s_tvalid;
   assign m_tdata  = s_tdata;
   assign m_tkeep  = ENABLE_TKEEP ? s_tkeep : '0;
   assign m_tlast  = ENABLE_TLAST ? s_tlast : 1'b0;
   assign m_tid    = ENABLE_TID   ? s_tid   : '0;
   assign m_tdest  = ENABLE_TDEST ? s_tdest : '0;
   assign m_tuser  = ENABLE_TUSER ? s_tuser : '0;
   assign s_tready = m_tready;
end
endgenerate

endmodule
