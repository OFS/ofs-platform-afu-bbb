//
// Copyright (c) 2021, Intel Corporation
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

//
// The PIM's internal definition of PCIe TLP headers. The encoding here is not
// the bit-level format expected by PCIe hardware or by any FIM. It is a simplified
// data structure used only inside the PIM. The types here are mapped to FIM
// types using FIM-specific gaskets.
//

package ofs_plat_pcie_tlp_hdr_pkg;

    // PCIe FMTTYPE - the command
    typedef logic [7:0] t_ofs_plat_pcie_hdr_fmttype;

    localparam OFS_PLAT_PCIE_FMTTYPE_MEM_READ32   = 8'b0000_0000;
    localparam OFS_PLAT_PCIE_FMTTYPE_MEM_READ64   = 8'b0010_0000;
    localparam OFS_PLAT_PCIE_FMTTYPE_MEM_WRITE32  = 8'b0100_0000;
    localparam OFS_PLAT_PCIE_FMTTYPE_MEM_WRITE64  = 8'b0110_0000;
    localparam OFS_PLAT_PCIE_FMTTYPE_CFG_WRITE    = 8'b0100_0100;
    localparam OFS_PLAT_PCIE_FMTTYPE_CPL          = 8'b0000_1010;
    localparam OFS_PLAT_PCIE_FMTTYPE_CPLD         = 8'b0100_1010;
    localparam OFS_PLAT_PCIE_FMTTYPE_FETCH_ADD32  = 8'b0100_1100;
    localparam OFS_PLAT_PCIE_FMTTYPE_FETCH_ADD64  = 8'b0110_1100;
    localparam OFS_PLAT_PCIE_FMTTYPE_SWAP32       = 8'b0100_1101;
    localparam OFS_PLAT_PCIE_FMTTYPE_SWAP64       = 8'b0110_1101;
    localparam OFS_PLAT_PCIE_FMTTYPE_CAS32        = 8'b0100_1110;
    localparam OFS_PLAT_PCIE_FMTTYPE_CAS64        = 8'b0110_1110;

    localparam OFS_PLAT_PCIE_TYPE_CPL = 5'b01010;
    localparam OFS_PLAT_PCIE_TYPE_MEM_RW = 5'b00000;

    typedef logic [9:0] t_ofs_plat_pcie_hdr_tag;
    typedef logic [15:0] t_ofs_plat_pcie_hdr_id;
    typedef logic [63:0] t_ofs_plat_pcie_hdr_addr;
    typedef logic [9:0] t_ofs_plat_pcie_hdr_length;
    typedef logic [11:0] t_ofs_plat_pcie_hdr_byte_count;
    typedef logic [6:0] t_ofs_plat_pcie_hdr_lower_addr;
    typedef logic [15:0] t_ofs_plat_pcie_hdr_irq_id;


    //
    // Header encodings, associated with the FMTTYPE commands above.
    // These packed structs will be bound together in a packed union,
    // so must all be the same size. Hence the count of bits, in
    // comments on the right, and padding.
    //

    // Header fields specific to memory requests
    typedef struct packed
    {
        t_ofs_plat_pcie_hdr_id requester_id;            // 16
        logic [2:0] tc;                                 // 3
        t_ofs_plat_pcie_hdr_tag tag;                    // 10
        logic [3:0] last_be;                            // 4
        logic [3:0] first_be;                           // 4
        t_ofs_plat_pcie_hdr_addr addr;                  // 64
                                                        // = 101
    }
    t_ofs_plat_pcie_hdr_mem_req;

    // Header fields specific to read completions
    typedef struct packed
    {
        t_ofs_plat_pcie_hdr_id requester_id;            // 16
        logic [2:0] tc;                                 // 3
        t_ofs_plat_pcie_hdr_tag tag;                    // 10
        t_ofs_plat_pcie_hdr_id completer_id;            // 16
        t_ofs_plat_pcie_hdr_byte_count byte_count;      // 12
        t_ofs_plat_pcie_hdr_lower_addr lower_addr;      // 7
        // Final completion. For DM encoded reads, the completion has
        // no byte_count. Instead, the FC bit is set.
        logic fc;                                       // 1
        // DM encoding provides no byte count. Instead, it has more
        // lower address bits. Store more lower address bits here in
        // order to compute the completions offset from the start address.
        logic [4:0] lower_addr_h;                       // 5
        logic dm_encoded;                               // 1
                                                        // = 71
        logic [29:0] pad; // All union entries must be the same size
    }
    t_ofs_plat_pcie_hdr_cpl;

    // Interrupt request
    typedef struct packed
    {
        t_ofs_plat_pcie_hdr_id requester_id;            // 16
        t_ofs_plat_pcie_hdr_irq_id irq_id;              // 16
                                                        // = 32
        logic [68:0] pad; // All union entries must be the same size
    }
    t_ofs_plat_pcie_hdr_irq;

    // Generic message (interrupts)
    typedef struct packed
    {
        t_ofs_plat_pcie_hdr_id requester_id;            // 16
        logic [2:0] tc;                                 // 3
        t_ofs_plat_pcie_hdr_tag tag;                    // 10
        logic [7:0] msg_code;                           // 8
        logic [63:0] msg;                               // 64
                                                        // = 101
    }
    t_ofs_plat_pcie_hdr_msg;

    typedef struct packed
    {
        // Header fields for all PIM-supported TLP message types.
        // SystemVerilog requires that all packed union entries be
        // the same size, so they are padded carefully above.
        union packed
        {
            t_ofs_plat_pcie_hdr_mem_req mem_req;
            t_ofs_plat_pcie_hdr_cpl cpl;
            t_ofs_plat_pcie_hdr_irq irq;
            t_ofs_plat_pcie_hdr_msg msg;
        } u;

        logic is_irq;
        t_ofs_plat_pcie_hdr_length length;
        t_ofs_plat_pcie_hdr_fmttype fmttype;
    }
    t_ofs_plat_pcie_hdr;


    //
    // Format decoder functions
    //

    function automatic bit ofs_plat_pcie_func_is_addr32(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (fmttype[5] == 1'b0);
    endfunction

    function automatic bit ofs_plat_pcie_func_is_addr64(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (fmttype[5] == 1'b1);
    endfunction

    function automatic bit ofs_plat_pcie_func_has_data(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (fmttype[6] == 1'b1);
    endfunction

    function automatic bit ofs_plat_pcie_func_is_completion(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (fmttype[4:0] == OFS_PLAT_PCIE_TYPE_CPL);
    endfunction

    function automatic bit ofs_plat_pcie_func_is_mem_req(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (fmttype[4:0] == OFS_PLAT_PCIE_TYPE_MEM_RW);
    endfunction

    function automatic bit ofs_plat_pcie_func_is_mem_req64(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (ofs_plat_pcie_func_is_mem_req(fmttype) && ofs_plat_pcie_func_is_addr64(fmttype));
    endfunction

    function automatic bit ofs_plat_pcie_func_is_mem_req32(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (ofs_plat_pcie_func_is_mem_req(fmttype) && ofs_plat_pcie_func_is_addr32(fmttype));
    endfunction

    function automatic bit ofs_plat_pcie_func_is_mwr_req(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (ofs_plat_pcie_func_is_mem_req(fmttype) && fmttype[6]) ? 1'b1 : 1'b0;
    endfunction

    function automatic bit ofs_plat_pcie_func_is_mrd_req(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        return (ofs_plat_pcie_func_is_mem_req(fmttype) && ~fmttype[6]) ? 1'b1 : 1'b0;
    endfunction


    // synthesis translate_off

    function automatic string ofs_plat_pcie_func_fmttype_to_string(input t_ofs_plat_pcie_hdr_fmttype fmttype);
        string t;

        casex (fmttype)
            8'b00x0_0000:  t = "MRd";
            8'b00x0_0001:  t = "MRdLk";
            8'b01x0_0000:  t = "MWr";
            8'b0000_0010:  t = "IORd";
            8'b0100_0010:  t = "IOWr";
            8'b0000_0100:  t = "CfgRd0";
            8'b0100_0100:  t = "CfgWr0";
            8'b0000_0101:  t = "CfgRd1";
            8'b0100_0101:  t = "CfgWr1";
            8'b0011_0xxx:  t = "Msg";
            8'b0111_0xxx:  t = "MsgD";
            8'b0000_1010:  t = "Cpl";
            8'b0100_1010:  t = "CplD";
            8'b0000_1011:  t = "CplLk";
            8'b0100_1011:  t = "CplDLk";
            8'b01x0_1100:  t = "FetAdd";
            8'b01x0_1101:  t = "Swap";
            8'b01x0_1110:  t = "CAS";
            8'b1000_xxxx:  t = "LPrfx";
            8'b1001_xxxx:  t = "EPrfx";
            default:       t = "XXXXX";
        endcase

        if (ofs_plat_pcie_func_is_mem_req32(fmttype)) t = { t, "32" };
        if (ofs_plat_pcie_func_is_mem_req64(fmttype)) t = { t, "64" };

        return t;
    endfunction

    function automatic string ofs_plat_pcie_func_base_to_string(input t_ofs_plat_pcie_hdr hdr);
        return $sformatf("%6s len 0x%x",
                         ofs_plat_pcie_func_fmttype_to_string(hdr.fmttype),
                         hdr.length);
    endfunction

    function automatic string ofs_plat_pcie_func_mem_req_to_string(input t_ofs_plat_pcie_hdr hdr);
        return $sformatf("%s req_id 0x%h tag 0x%h lbe 0x%h fbe 0x%h addr 0x%h",
                         ofs_plat_pcie_func_base_to_string(hdr),
                         hdr.u.mem_req.requester_id, hdr.u.mem_req.tag,
                         hdr.u.mem_req.last_be, hdr.u.mem_req.first_be,
                         hdr.u.mem_req.addr);
    endfunction

    function automatic string ofs_plat_pcie_func_cpl_to_string(input t_ofs_plat_pcie_hdr hdr);
        return $sformatf("%s %s cpl_id 0x%h bytes 0x%h req_id 0x%h tag 0x%h low_addr 0x%h fc 0x%h",
                         ofs_plat_pcie_func_base_to_string(hdr),
                         (hdr.u.cpl.dm_encoded ? "DM" : "PU"),
                         hdr.u.cpl.completer_id, hdr.u.cpl.byte_count,
                         hdr.u.cpl.requester_id, hdr.u.cpl.tag,
                         { hdr.u.cpl.lower_addr_h, hdr.u.cpl.lower_addr_h },
                         hdr.u.cpl.fc);
    endfunction

    function automatic string ofs_plat_pcie_func_msg_to_string(input t_ofs_plat_pcie_hdr hdr);
        return $sformatf("%s req_id 0x%h tag 0x%h code 0x%h msg 0x%h",
                         ofs_plat_pcie_func_base_to_string(hdr),
                         hdr.u.msg.requester_id, hdr.u.msg.tag, hdr.u.msg.msg_code,
                         hdr.u.msg.msg);
    endfunction

    function automatic string ofs_plat_pcie_func_irq_to_string(input t_ofs_plat_pcie_hdr hdr);
        return $sformatf("IRQ req_id 0x%h irq 0x%h",
                         hdr.u.irq.requester_id, hdr.u.irq.irq_id);
    endfunction

    function automatic string ofs_plat_pcie_func_hdr_to_string(input t_ofs_plat_pcie_hdr hdr);
        string s;
        if (hdr.is_irq) begin
            s = ofs_plat_pcie_func_irq_to_string(hdr);
        end
        else if (ofs_plat_pcie_func_is_mem_req(hdr.fmttype)) begin
            s = ofs_plat_pcie_func_mem_req_to_string(hdr);
        end
        else if (ofs_plat_pcie_func_is_completion(hdr.fmttype)) begin
            s = ofs_plat_pcie_func_cpl_to_string(hdr);
        end
        else begin
            s = ofs_plat_pcie_func_msg_to_string(hdr);
        end

        return s;
    endfunction

    // synthesis translate_on

endpackage // ofs_plat_pcie_tlp_hdr_pkg
