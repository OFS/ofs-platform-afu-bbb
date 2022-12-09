// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

//
// Tie off unused ports in the ofs_plat_if interface.
//

module ofs_plat_if_tie_off_unused
  #(
    // Masks are bit masks, with bit 0 corresponding to port/bank zero.
    // Set a bit in the mask when a port is IN USE by the design.
    // This way, the AFU does not need to know about every available
    // device. By default, devices are tied off.
    @OFS_PLAT_IF_TEMPLATE@
    parameter bit [31:0] @CLASS@@GROUP@_IN_USE_MASK = 0,
    @OFS_PLAT_IF_TEMPLATE@

    // Emit debugging messages in simulation for tie-offs?
    parameter QUIET = 0
    )
   (
    ofs_plat_if plat_ifc
    );

    genvar i;
    @OFS_PLAT_IF_TEMPLATE@
    //==
    //== Tie-offs for top-level interface classes will be emitted here, using
    //== the template between instances of @OFS_PLAT_IF_TEMPLATE@ for each class
    //== and group number.
    //==

    generate
        for (i = 0; i < plat_ifc.@class@@group@.NUM_@NOUN@; i = i + 1)
        begin : tie_@class@@group@
            if (~@CLASS@@GROUP@_IN_USE_MASK[i])
            begin : m
                ofs_plat_@class@@group@_fiu_if_tie_off tie_off(plat_ifc.@class@@group@.@noun@[i]);

                // synthesis translate_off
                initial
                begin
                    if (QUIET == 0) $display("%m: Tied off plat_ifc.@class@@group@.@noun@[%0d]", i);
                end
                // synthesis translate_on
            end
        end
    endgenerate
    @OFS_PLAT_IF_TEMPLATE@

endmodule // ofs_plat_if_tie_off_unused
