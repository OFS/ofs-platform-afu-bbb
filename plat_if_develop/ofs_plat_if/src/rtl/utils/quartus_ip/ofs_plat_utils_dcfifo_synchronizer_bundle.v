// $File: //acds/rel/20.2/ip/sopc/components/altera_avalon_dc_fifo/altera_dcfifo_synchronizer_bundle.v $
// $Revision: #1 $
// $Date: 2020/04/03 $
// $Author: psgswbuild $
//-------------------------------------------------------------------------------

`timescale 1 ns / 1 ns
module ofs_plat_utils_dcfifo_synchronizer_bundle(
                                     clk,
                                     reset_n,
                                     din,
                                     dout
                                     );
   parameter WIDTH = 1;
   parameter DEPTH = 3;   
   
   input clk;
   input reset_n;
   input [WIDTH-1:0] din;
   output [WIDTH-1:0] dout;
   
   genvar i;
   
   generate
      for (i=0; i<WIDTH; i=i+1)
        begin : sync
           ofs_plat_utils_std_synchronizer_nocut #(.depth(DEPTH))
                                   u (
                                      .clk(clk), 
                                      .reset_n(reset_n), 
                                      .din(din[i]), 
                                      .dout(dout[i])
                                      );
        end
   endgenerate
   
endmodule 

