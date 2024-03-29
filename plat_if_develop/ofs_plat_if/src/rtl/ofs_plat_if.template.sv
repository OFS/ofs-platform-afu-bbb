// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

`include "ofs_plat_if.vh"

//
// ofs_plat_if is the top-level wrapper around all interfaces coming into the
// AFU PR region.
//
// Note that ofs_plat_if and the sub-interfaces it contains instantiate
// properly configured types with their default parameters. This behavior
// is crucial in order to enable platform-independent AFUs.
//

interface ofs_plat_if
  #(
    parameter ENABLE_LOG = 0
    );

    // Required: platform top-level clocks
    wire t_ofs_plat_std_clocks clocks;

    // Required: active low soft reset (clocked by pClk). This reset
    // is identical to clocks.pClk.reset_n.
    logic softReset_n;
    // Required: AFU power state (clocked by pClk)
    t_ofs_plat_power_state pwrState;

    // Each sub-interface is a wrapper around a single vector of ports or banks.
    // Each port or bank in a vector must be the same configuration. Namely,
    // multiple banks within a local memory interface must all have the same
    // width and depth. If a platform has more than one configuration of a
    // class, e.g. both DDR and static RAM, those should be instantiated here
    // as separate interfaces.
    //==
    //== Top-level interface classes will be emitted here, using the template
    //== between instances of @OFS_PLAT_IF_TEMPLATE@ for each class and group
    //== number.
    //==
    @OFS_PLAT_IF_TEMPLATE@

    ofs_plat_@class@@group@_fiu_if
      #(
        .ENABLE_LOG(ENABLE_LOG)
        )
        @class@@group@();
    @OFS_PLAT_IF_TEMPLATE@

endinterface // ofs_plat_if
