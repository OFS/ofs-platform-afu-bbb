// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
