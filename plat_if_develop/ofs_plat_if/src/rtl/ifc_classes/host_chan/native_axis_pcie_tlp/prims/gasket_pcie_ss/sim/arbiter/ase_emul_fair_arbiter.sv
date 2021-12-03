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
// Creation Date :	11-08-2014
// Last Modified :	Thu 05 Mar 2015 07:38:52 PM PST
// Module Name :	fair_arbiter.sv
// Project :             
// Description :    
//
// ***************************************************************************

module ase_emul_fair_arbiter #(
    parameter NUM_INPUTS=2'h2,
    LNUM_INPUTS=(NUM_INPUTS == 1) ? 1 : $clog2(NUM_INPUTS))
(
    input   logic                    clk,
    input   logic                    reset_n,
    input   logic [NUM_INPUTS-1:0]   in_valid,
    input   logic [NUM_INPUTS-1:0]   hold_priority,     // do not shift the priority
    output  logic [LNUM_INPUTS-1:0]  out_select,
    output  logic [NUM_INPUTS-1:0]   out_select_1hot,
    output  logic                    out_valid
);
generate if(NUM_INPUTS==1)
begin   : gen_1way_arbiter
// Handle the simple degenerate case
ase_emul_fair_arbiter_1way
inst_fair_arbiter_1way
(   .clk(clk),
    .reset_n(reset_n),
    .in_valid(in_valid),
    .hold_priority(hold_priority),
    .out_select(out_select),
    .out_select_1hot(out_select_1hot),
    .out_valid(out_valid)
);
end
else if(NUM_INPUTS<=4)  
begin   : gen_4way_arbiter
ase_emul_fair_arbiter_4way #(.NUM_INPUTS(NUM_INPUTS), 
                    .LNUM_INPUTS(LNUM_INPUTS)
                    )
inst_fair_arbiter_4way
(   .clk(clk),
    .reset_n(reset_n),
    .in_valid(in_valid),
    .hold_priority(hold_priority),
    .out_select(out_select),
    .out_select_1hot(out_select_1hot),
    .out_valid(out_valid)
);
end
else
begin : gen_mask_arb
ase_emul_fair_arbiter_w_mask #(.NUM_INPUTS(NUM_INPUTS),
                      .LNUM_INPUTS(LNUM_INPUTS)
                    )
inst_fair_arbiter_w_mask
(   .clk(clk),
    .reset_n(reset_n),
    .in_valid(in_valid),
    .hold_priority(hold_priority),
    .out_select(out_select),
    .out_select_1hot(out_select_1hot),
    .out_valid(out_valid)
);
end
endgenerate
endmodule

// For generality, implement the 1 way arbiter.
module ase_emul_fair_arbiter_1way
(
    input   logic                    clk,
    input   logic                    reset_n,
    input   logic                    in_valid,
    input   logic                    hold_priority,     // do not shift the priority
    output  logic                    out_select,
    output  logic                    out_select_1hot,
    output  logic                    out_valid
);
    assign out_select = 1'b0;
    assign out_select_1hot = 1'b1;
    assign out_valid = in_valid;
endmodule

module ase_emul_fair_arbiter_4way #(parameter NUM_INPUTS=2'h2, LNUM_INPUTS=$clog2(NUM_INPUTS))
(
    input   logic                    clk,
    input   logic                    reset_n,
    input   logic [NUM_INPUTS-1:0]   in_valid,
    input   logic [NUM_INPUTS-1:0]   hold_priority,     // do not shift the priority
    output  logic [LNUM_INPUTS-1:0]  out_select,
    output  logic [NUM_INPUTS-1:0]   out_select_1hot,
    output  logic                    out_valid
);
reg [3:0]   fixed_width_in_valid;
reg [1:0]   fixed_width_last_select;

always @(*)
begin
    fixed_width_in_valid=0;
    fixed_width_in_valid[NUM_INPUTS-1:0]=in_valid;
	
    out_valid = |in_valid;
    casez({fixed_width_last_select, fixed_width_in_valid})
                       {2'h0, 4'b??1?}  : begin  out_select  = 2'h1;
                                                 out_select_1hot = 4'b0010;
                       end
                       {2'h0, 4'b?1??}  : begin  out_select  = 2'h2;
                                                 out_select_1hot = 4'b0100;
                       end
                       {2'h0, 4'b1???}  : begin  out_select  = 2'h3;
                                                 out_select_1hot = 4'b1000;
                       end
                       {2'h0, 4'b???1}  : begin  out_select  = 2'h0;
                                                 out_select_1hot = 4'b0001;
                       end

                       {2'h1, 4'b?1??}  : begin  out_select  = 2'h2;
                                                 out_select_1hot = 4'b0100;
                       end
                       {2'h1, 4'b1???}  : begin  out_select  = 2'h3;
                                                 out_select_1hot = 4'b1000;
                       end
                       {2'h1, 4'b???1}  :begin   out_select  = 2'h0;
                                                 out_select_1hot = 4'b0001;
                       end
                       {2'h1, 4'b??1?}  :begin   out_select  = 2'h1;
                                                 out_select_1hot = 4'b0010;
                       end

                       {2'h2, 4'b1???}  :begin   out_select  = 2'h3;
                                                 out_select_1hot = 4'b1000;
                       end
                       {2'h2, 4'b???1}  :begin   out_select  = 2'h0;
                                                 out_select_1hot = 4'b0001;
                       end
                       {2'h2, 4'b??1?}  :begin   out_select  = 2'h1;
                                                 out_select_1hot = 4'b0010;
                       end
                       {2'h2, 4'b?1??}  :begin   out_select  = 2'h2;
                                                 out_select_1hot = 4'b0100;
                       end

                       {2'h3, 4'b???1}  :begin   out_select  = 2'h0;
                                                 out_select_1hot = 4'b0001;
                       end
                       {2'h3, 4'b??1?}  :begin   out_select  = 2'h1;
                                                 out_select_1hot = 4'b0010;
                       end
                       {2'h3, 4'b?1??}  :begin   out_select  = 2'h2;
                                                 out_select_1hot = 4'b0100;
                       end
                       {2'h3, 4'b1???}  :begin   out_select  = 2'h3;
                                                 out_select_1hot = 4'b1000;
                       end
                       default          :begin   out_select  = 2'h0;
                                                 out_select_1hot = 4'b0000;
                       end
    endcase
end

always@(posedge clk)
begin
    if(out_valid && hold_priority[out_select]==0)
        fixed_width_last_select[LNUM_INPUTS-1:0] <= out_select;

	 if(!reset_n)
	 begin
		fixed_width_last_select <= 0;
	 end
end

endmodule

module ase_emul_fair_arbiter_w_mask #(parameter NUM_INPUTS=2'h2, LNUM_INPUTS=$clog2(NUM_INPUTS))

(
    input   logic                    clk,
    input   logic                    reset_n,
    input   logic [NUM_INPUTS-1:0]   in_valid,
    input   logic [NUM_INPUTS-1:0]   hold_priority,     // do not shift the priority
    output  logic [LNUM_INPUTS-1:0]  out_select,
    output  logic [NUM_INPUTS-1:0]   out_select_1hot,
    output  logic                    out_valid
);
    logic [LNUM_INPUTS-1:0] lsb_select, msb_select;
    logic [NUM_INPUTS-1:0]  lsb_mask;                       // bits [out_select-1:0]='0
    logic [NUM_INPUTS-1:0]  msb_mask;                       // bits [NUM_INPUTS-1:out_select]='0
    logic                   msb_in_notEmpty;

    always @(posedge clk)
    begin
        if(out_valid && hold_priority[out_select]==0)
        begin
            msb_mask    <= ~({{NUM_INPUTS-1{1'b1}}, 1'b0}<<out_select); 
            lsb_mask    <=   {{NUM_INPUTS-1{1'b1}}, 1'b0}<<out_select;
        end

        if(!reset_n)
        begin
            msb_mask <= '1;
            lsb_mask <= '0;
        end
    end

    wire    [NUM_INPUTS-1:0]    msb_in = in_valid & lsb_mask;
    wire    [NUM_INPUTS-1:0]    lsb_in = in_valid & msb_mask;
    
    always_comb
    begin
        msb_in_notEmpty = |msb_in;
        out_valid       = |in_valid;
        lsb_select = 0;
        msb_select = 0;
        // search from lsb to msb
        for(int i=NUM_INPUTS-1'b1; i>=0; i--)
        begin
            if(lsb_in[i])
                lsb_select = i;
            if(msb_in[i])
                msb_select = i;
        end
        out_select = msb_in_notEmpty ? msb_select : lsb_select;
        out_select_1hot = 0;
        out_select_1hot[out_select] = 1'b1;
    end
endmodule

