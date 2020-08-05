//
// Copyright (c) 2020, Intel Corporation
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
// Standard clock types
//

`ifndef __OFS_PLAT_CLOCKS_VH__
`define __OFS_PLAT_CLOCKS_VH__

typedef struct packed
{
    logic clk;
    logic reset_n;
}
t_ofs_plat_clock_reset_pair;

//
// Clocks provided to the AFU. All conforming platforms provide at least
// 5 primary clocks: pClk, pClkDiv2, pClkDiv4, uClk_usr and uClk_usrDiv2.
// Divided clocks are all aligned to their primary clocks.
//
// Each clock has an associated reset that is synchronous in the clock's
// domain. While an AFU could generate these resets, the platform provides
// them so that FIM designers can choose whether to bind particular resets
// to global wires or whether to provide resets on local logic. Resets
// are active low.
//
typedef struct packed
{
    t_ofs_plat_clock_reset_pair pClk;
    t_ofs_plat_clock_reset_pair pClkDiv2;
    t_ofs_plat_clock_reset_pair pClkDiv4;
    t_ofs_plat_clock_reset_pair uClk_usr;
    t_ofs_plat_clock_reset_pair uClk_usrDiv2;
}
t_ofs_plat_std_clocks;

`endif // __OFS_PLAT_CLOCKS_VH__
