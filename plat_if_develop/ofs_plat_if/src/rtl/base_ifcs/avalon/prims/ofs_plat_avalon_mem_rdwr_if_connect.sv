//
// Copyright (c) 2019, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
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

`include "ofs_plat_if.vh"

//
// Wire together two Avalon split bus memory instances.
//
module ofs_plat_avalon_mem_rdwr_if_connect
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source
    );

    always_comb
    begin
        `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
        `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_sink);
    end

endmodule // ofs_plat_avalon_mem_rdwr_if_connect


// Same as standard connection, but pass clk and reset_n from sink to source
module ofs_plat_avalon_mem_rdwr_if_connect_sink_clk
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source_clk mem_source
    );

    assign mem_source.clk = mem_sink.clk;
    assign mem_source.reset_n = mem_sink.reset_n;

    // Debugging signal
    assign mem_source.instance_number = mem_sink.instance_number;

    always_comb
    begin
        `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
        `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_sink);
    end

endmodule // ofs_plat_avalon_mem_rdwr_if_connect_sink_clk


// Same as standard connection, but pass clk and reset_n from source to sink
module ofs_plat_avalon_mem_rdwr_if_connect_source_clk
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink_clk mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source
    );

    assign mem_sink.clk = mem_source.clk;
    assign mem_sink.reset_n = mem_source.reset_n;

    // Debugging signal
    assign mem_sink.instance_number = mem_source.instance_number;

    always_comb
    begin
        `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
        `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_sink);
    end

endmodule // ofs_plat_avalon_mem_rdwr_if_connect_source_clk
