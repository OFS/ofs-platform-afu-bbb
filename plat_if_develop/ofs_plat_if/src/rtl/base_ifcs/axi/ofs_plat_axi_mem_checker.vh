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
// This file is typically included inside AXI memory interface definitions.
// It holds logic for checking AXI signalling.
//

// synthesis translate_off

// Validate signals
always_ff @(negedge clk)
begin
    if (reset_n && (DISABLE_CHECKER == 0))
    begin
        if (awvalid === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: awvalid is uninitialized!");
        end
        if (wvalid === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: wvalid is uninitialized!");
        end
        if (bvalid === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: bvalid is uninitialized!");
        end

        if (arvalid === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: arvalid is uninitialized!");
        end
        if (rvalid === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: rvalid is uninitialized!");
        end

        if (awready === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: awready is uninitialized!");
        end
        if (wready === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: wready is uninitialized!");
        end
        if (bready === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: bready is uninitialized!");
        end

        if (arready === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: arready is uninitialized!");
        end
        if (rready === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: rready is uninitialized!");
        end

        if (awvalid)
        begin
            if (^aw.id === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: aw.id undefined, currently 0x%x", aw.id);
            end

            if (^aw.addr === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: aw.addr undefined, currently 0x%x", aw.addr);
            end

            if (^aw.size === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: aw.size undefined, currently 0x%x", aw.size);
            end

            if (^aw.prot === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: aw.prot undefined, currently 0x%x", aw.prot);
            end

            if (^aw.user === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: aw.user undefined, currently 0x%x", aw.user);
            end
        end

        if (wvalid)
        begin
            if (^w.strb === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: w.strb undefined, currently 0x%x", w.strb);
            end

            if (^w.user === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: w.user undefined, currently 0x%x", w.user);
            end
        end

        if (bvalid)
        begin
            if (^b.id === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: b.id undefined, currently 0x%x", b.id);
            end

            if (^b.resp === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: b.resp undefined, currently 0x%x", b.resp);
            end

            if (^b.user === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: b.user undefined, currently 0x%x", b.user);
            end
        end

        if (arvalid)
        begin
            if (^ar.id === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: ar.id undefined, currently 0x%x", ar.id);
            end

            if (^ar.addr === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: ar.addr undefined, currently 0x%x", ar.addr);
            end

            if (^ar.size === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: ar.size undefined, currently 0x%x", ar.size);
            end

            if (^ar.prot === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: ar.prot undefined, currently 0x%x", ar.prot);
            end

            if (^ar.user === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: ar.user undefined, currently 0x%x", ar.user);
            end
        end

        if (rvalid)
        begin
            if (^r.id === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: r.id undefined, currently 0x%x", r.id);
            end

            if (^r.resp === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: r.resp undefined, currently 0x%x", r.resp);
            end

            if (^r.user === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: r.user undefined, currently 0x%x", r.user);
            end
        end
    end // if (reset_n && (DISABLE_CHECKER == 0))
end

// synthesis translate_on
