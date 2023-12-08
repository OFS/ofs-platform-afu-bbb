# Board Vendors: Configuring a Release #

## Platform Interface Classes ##

As discussed in [PIM Core Concepts](PIM_core_concepts.md), the portability of PIM interfaces relies on mapping physical ports to bus-independent abstract groups. Major PIM groups are:

### Host Channels ###

A host channel is a port offering DMA to host memory and, optionally, a CSR space managed by the AFU. Typical boards provide PCIe as the primary host channel, with the OPAE SDK and driver depending on PCIe MMIO to implement the CSRs used by OPAE to manage the FIM and AFU. Boards may have more than one host channel, often of different types. PCIe, CXL and UPI are all considered host channels.

### Local Memory ###

Local memory is off-chip storage, such as DDR or HBM, attached directly to the FPGA and not managed by the FIM as part of host memory.

### HSSI ###

HSSI ports are high speed serial interconnects, such as Ethernet.

### Other Classes ###

Board vendors may define non-standard classes. The PIM provides templates for writing new SystemVerilog interfaces and for writing device-specific tie-offs that are instantiated automatically by the PIM when a device is not used by an AFU.

## Native Interface Types ##

A physical interface exposed by the FIM to an AFU is called a *native type*. Every FIM interface declares a native type. This type defines the physical wires. The PIM may provide a collection of shims on top of the native type that map to one or more type abstractions offered to AFUs. This is the primary PIM portability mechanism. For example, the PIM can import both native CCI-P and native PCIe TLP AXI streams. In both cases, AFUs may instantiate a shim named *ofs\_plat\_host\_chan\_as\_avalon\_mem\_rdwr* as a wrapper around the native interface instance. The implementations are quite different but both provide a mapping from the native interface to Avalon memory interfaces. The PIM source tree has several implementations of *ofs\_plat\_host\_chan\_as\_avalon\_mem\_rdwr*. The PIM generation scripts pick the shims appropriate to a particular platform when generating a platform's ofs\_plat\_if tree.

The PIM may offer several shims on top of the same native type, thus offering different AFU interfaces to the same device. For example, an AFU may select either AXI memory, Avalon memory or CCI-P connections to the same FIM PCIe host channel.

## Defining a Platform Interface ##

The PIM is instantiated in a build environment from the following:

* An .ini file describing the platform
* A collection of [RTL interfaces and modules](../src)
* The [gen\_ofs\_plat\_if](../scripts/gen_ofs_plat_if) script

```sh
mkdir -p <release tree root>/hw/lib/build/platform/ofs_plat_if
gen_ofs_plat_if -c <.ini file path> -t <release tree root>/hw/lib/build/platform/ofs_plat_if
```

This script is run automatically by the standard OFS FIM build flow as long as a board compilation environment specifies the .ini file. The generated PIM sources are included in both FIM and PR build trees.

### Platform .ini Files ###

Each major section in a platform .ini file corresponds to one or more devices of the same type. Same-sized banks of local memory share a single .ini section, with the number of banks as a parameter in the section. The same is true of HSSI ports and, on some multi-PCIe systems, of host channels. All devices in a section must share the same properties. If there are two types of local memory on a board with different address or data widths, they must have their own local memory sections. Separate sections of the same type must be named either with a unique tag, such as *local\_memory.hbm* or with monotonically increasing numeric suffixes, e.g. *local\_memory.0* and *local\_memory.1*. The trailing *.0* is optional. *host\_channel.0* and *host\_channel* are equivalent.

Some sections are required in order to guarantee AFU portability across platforms:

* **[define]** — A list of preprocessor macros that the PIM will export into all builds. At least one macro should uniquely identify the platform. Others may be used to identify features, used by AFUs for conditional compilation.
* **[clocks]** — The frequency of the primary pClk.
* **[host\_chan]** — Typical platforms will have at least one host channel port. By convention, host\_chan.0, port 0 is mapped to the primary MMIO-based CSR space used by OPAE when probing AFUs.

Sections typically represent vectors of ports or banks, all of the same type. The values *num\_ports* and *num\_banks* within a section cause gen\_ofs\_plat\_if to name vectors as *ports* or *banks*.

All properties in a platform's .ini file are exported as preprocessor macros in the generated PIM. In out-of-tree partial reconfiguration (PR) build environments, macros are in:

```
$OPAE_PLATFORM_ROOT/hw/lib/build/platform/ofs_plat_if/rtl/ofs_plat_if_top_config.vh
```

Within the FIM build itself, a file of the same name is stored and loaded from the build tree. The naming convention is a straight mapping of sections and properties to macros, e.g.:

```SystemVerilog
`define OFS_PLAT_PARAM_LOCAL_MEM_NUM_BANKS 2
`define OFS_PLAT_PARAM_LOCAL_MEM_ADDR_WIDTH 27
`define OFS_PLAT_PARAM_LOCAL_MEM_DATA_WIDTH 512
`define OFS_PLAT_PARAM_LOCAL_MEM_BURST_CNT_WIDTH 7
```

### Defaults ###

Within a section, some properties are mandatory. For example, local memories must define address and data widths. The [defaults.ini](../../../plat_if_develop/ofs_plat_if/src/config/defaults.ini) file holds the required values for all standard section classes. It also documents the semantics of each property. Sections in defaults.ini may be universal across all native interfaces, such as **[host\_chan]** for all host channels, or specific to a particular native interface, e.g. **[host\_chan.native\_axis\_pcie\_tlp]**.

Platform-specific .ini files may override properties from defaults.ini and may add new properties. All properties are written to the generated ofs\_plat\_if\_top\_config.vh.

The defaults.ini has a section for each OFS PIM standard class:

* **[clocks]** — Top-level clocks, typically pClk, pClkDiv2, pClkDiv4, uClk\_usr and uClk\_usrDiv2.
* **[host\_chan]** — Connections to host memory (e.g. PCIe or CXL) and/or MMIO slaves, with a host as master.
* **[local\_mem]** — Local memory, connected to the FPGA directly outside of the host's coherence domains.
* **[hssi]** — Ethernet ports.

### Multiple Instances of a Class ###

Complex platforms may have multiple devices that are similar, but not identical. A board could have a host channel to an embedded SoC CPU and an external PCIe connection to a host. These can be represented as multiple sections in an .ini file, the primary port named **[host\_chan]** and the secondary group named **[host\_chan.1]**. As noted earlier, **[host\_chan]** and **[host\_chan.0]** are synonymous. The pair of channels, **[host\_chan]** and **[host\_chan.1]**, are logically separate. In addition to having different address or data widths, they may even have different native types.

The PIM tree has some emulated test platforms as examples. [d5005\_pac\_ias\_v2\_0\_1\_em\_hc1cx2a.ini](../src/config/emulation/d5005_pac_ias_v2_0_1_em_hc1cx2a.ini) describes a FIM with two host channel groups, with group one using native CCI-P and group two using a pair of native Avalon memory interfaces.

### Native Interface ###

Within a class, the *native_class* keyword specifies the FIM's interface. For example:

```ini
[host_chan]
num_ports=2
native_class=native_axis_pcie_tlp
gasket=pcie_ss
```

The native class maps to a directory during PIM construction. In this case, [host\_chan/native\_axis\_pcie\_tlp](../src/rtl/ifc_classes/host_chan/native_axis_pcie_tlp/). The PIM construction script will instantiate the specified native class and ignore all other native class implementations.

The *gasket* keyword further refines the FIM interface. Platforms may have subtle implementation variations for the same basic native class. When *gasket* is specified, the PIM setup script looks for directories within the class named *gasket\_\** and keeps only those matching the gasket name, e.g. *gasket\_pcie\_ss*.

### Conditional Compilation ###

Some devices are enabled and disabled in FIM builds using macros in the Quartus project. For example, HSSI support is often enabled with INCLUDE\_HSSI. Each section in a PIM .ini files may contain an *enabled\_by* field. When present, the section is instantiated only when one of the listed macro names is set. Multiple macro names may be listed, separated by the \| (or) character. The PIM setup scripts automatically look for project macros in a file with the same path and name as the PIM .ini file but with the suffix *.macros*. FIM builds generate the PIM .macros automatically, early in the FIM setup stage.

A PIM instance with conditionally enabled local memory might look like:

```ini
[local_mem]
enabled_by=INCLUDE_DDR4|INCLUDE_DDR5
native_class=native_axi
num_banks=ofs_fim_mem_if_pkg::NUM_MEM_CHANNELS
...
```

PIM memory interfaces and configuration will be generated only if INCLUDE_DDR4 or INCLUDE_DDR5 is defined. Similarly, the HSSI section is often predicated with:

```ini
[hssi]
enabled_by=INCLUDE_HSSI
native_class=native_axis_with_fc
num_channels=ofs_fim_eth_plat_if_pkg::MAX_NUM_ETH_CHANNELS
...
```

### Platform-Specific Extensions ###

FIM developers may require non-standard AFU interfaces such as power management, extra clocks or HSSI sideband flow control. The PIM provides a mechanism for extending a platform's *ofs\_plat\_if* top-level interface without having to modify the core PIM sources.

Extending the interface begins by creating a new named section in the PIM .ini file. As shown in the example below, set *template\_class* to *generic\_templates* and *native\_class* to one of *banks*, *ports* or *channels*. The PIM provides generic templates as starting points for adding non-standard native interfaces. They will be copied to the generated *ofs\_plat\_if* and must be completed by platform implementers. The source templates are in [ifc\_classes/generic\_templates](../../../plat_if_develop/ofs_plat_if/src/rtl/ifc_classes/generic_templates/), one for collections of ports and others for collections of banks and channels.

The section name becomes the wrapper's name in the PIM's top-level interface. The following settings, which are present in OFS FIM builds by default as an example, create a top-level name *other* as *plat\_ifc.other.ports\[0\]:*

```ini
[other]
;; Generic wrapper around a vector of ports
template_class=generic_templates
native_class=ports
num_ports=1
;; Type of the interface (provided by import)
type=ofs_plat_fim_other_if
;; Sources to import into the PIM that define the type and tie-off module
import=<relative path from .ini file to this extend_pim directory>
;; Other values, which become macros in the generated PIM
req_width=8
rsp_width=16
```

A variation of the above configuration is present, including sample data types, and compiled into base OFS FIM platforms.

Files in the imported directory must define the named platform-specific type, *ofs\_plat\_fim\_other\_if*. The *import* keyword within any section causes the PIM setup script to copy the sources into the build environment. The standard group and class template substitution rules described in the PIM implementation below apply to these files. The usual dot notation applies for multiple variations of the same class. Adding *\[other.1\]* and filling out all the required values would instantiate a second top-level name, *plat\_ifc.other_g1.ports\[0\]*.

Any values may be set within the .ini file's extension section. In the case above, *OFS\_PLAT\_PARAM\_OTHER_REQ\_WIDTH* and *OFS\_PLAT\_PARAM\_OTHER_RSP\_WIDTH* are defined as macros in the generated PIM. So are all the other fields, such as *OFS\_PLAT\_PARAM\_OTHER\_TYPE*.

The tutorials written for AFU developers demonstrate the use of the *other* extension.

## PIM Implementation ##

The gen\_ofs\_plat\_if script, which composes a platform-specific PIM given an .ini file, uses the [ofs\_plat\_if/src/rtl/](../src/rtl/) tree as a template. The script copies sources into the target ofs\_plat\_if tree within a release, generates some top-level wrapper files and emits rules that import the generated tree for simulation or synthesis. SystemVerilog requires that packages be loaded in dependence order. A simple parser reads all generated source files during setup, looking for regular expressions that look like package imports, and emits source file lists in the required order.

Some directories within the rtl tree are imported unchanged:

* **base\_ifcs** — A collection of generic interface definitions (e.g. Avalon and AXI) and helper modules (e.g. clock crossing and pipeline stage insertion).
* **compat** — Compatibility wrapper for the original implementation of the PIM, originally found in the OPAE SDK. Unlike the OFS PIM, to which an AFU connects using SystemVerilog, the original PIM specified an AFU's requirement using JSON and Python. The new PIM remains backward compatible with the original implementation.
* **utils** — Primitive shims, such as FIFOs, memories, and reorder buffers.

### Templates ###

The core sources for PIM interfaces are in the [ofs\_plat\_if/src/rtl/ifc\_classes/](../src/rtl/ifc_classes/) tree. The tree is organized by top-level PIM classes (host\_chan, local\_mem, etc.) and, below those, by native interfaces. The PIM generator script copies only the top-level class and native interface pairs specified by a platform-specific .ini file. From an AFU's perspective, multiple native interfaces under a given top-level class are functionally equivalent mappings to the same module names and semantics. This selection of the proper, platform-specific, shim is the core PIM mechanism for achieving AFU portability.

Another key to portability is a shim naming convention. All shims are named:

```
module ofs_plat_<top-level class instance>_as_<interface type>()
```

For example:

```
module ofs_plat_host_chan_as_avalon_mem_rdwr()
module ofs_plat_host_chan_as_ccip()
```

Both modules connect to the same physical device. It is up to the AFU to select an implementation from the available options.

When multiple instances of a top-level class are present, e.g. when banks with different widths of local memory are available, a *group* tag is added to the top-level class instance. The raw top-level class name is always used for group 0. Special naming for groups begins with group 1, e.g.:

```
module ofs_plat_host_chan_as_avalon_mem_rdwr()
module ofs_plat_host_chan_as_ccip()

module ofs_plat_host_chan_g1_as_avalon_mem_rdwr()
module ofs_plat_host_chan_g1_as_ccip()
```

The implementation of a shim is independent of platform-specific group numbering. As a platform developer, it would be tedious to replicate equivalent sources that differ only by group name. The gen\_ofs\_plat\_if script treats source files as templates, with replacement rules:

* File names containing *\_GROUP\_* are renamed with the group number. *local\_mem\_GROUP\_cfg\_pkg.sv* becomes *local\_mem\_g1\_cfg\_pkg.sv*. The tag is eliminated for group 0: *local\_mem\_cfg\_pkg.sv*.
* There are also substitution rules for the contents of files with names containing *\_GROUP\_*. The pattern *@GROUP@* becomes *G1* and *@group@* becomes *g1*. The pattern is simply eliminated for group 0.
* *\_CLASS\_* in file names and *@CLASS@* or *@class@* inside these files are replaced with the interface class name — the name of the section in the .ini file.
* Comments of the form *//=* are eliminated. This makes it possible to have a comment in a template file about the template itself that is not replicated to the platform's release.

All of the PIM's interface shims apply these templates. For a simple example, see the generic template that is copied when an .ini file specifies *template_class=generic\_templates* and *native\_class=ports*: [ofs\_plat\_CLASS\_GROUP\_fiu\_if.sv](../src/rtl/ifc_classes/generic_templates/ports/ofs_plat_CLASS_GROUP_fiu_if.sv).

### Top-Level Templates ###

The top-level [rtl directory](../src/rtl/) holds files that become the root of a release's PIM. Files with names containing *.template* are copied with *.template* and the contents processed as follows:

When the keyword *@OFS\_PLAT\_IF\_TEMPLATE@* is encountered, gen\_ofs\_plat\_if loops through the region beginning and ending with the keyword, replicating the text for each of the platform's interface groups. Inside these regions, the following patterns are substituted:

* *@class@* is replaced with the interface major class, such as *host\_chan* or *local\_memory*.
* *@group@* is replaced with the group name within a class. It is eliminated for group 0.
* *@noun@* is replaced with the collection name for a class, typically *ports* or *banks*.
* *@CONFIG_DEFS@* (uppercase only) is replaced with all preprocessor macros associated with a class's properties. This is primarily used in [ofs\_plat\_if\_top\_config.template.vh](../src/rtl/ofs_plat_if_top_config.template.vh) to generate ofs\_plat\_if\_top\_config.vh.

The case of the pattern determines the case of the substitution.

The keyword *@OFS\_PLAT\_IF\_TEMPLATE@* skips sections with no ports or banks, such as *[clocks]*. To apply the template to all sections, use the keyword *@OFS\_PLAT\_IF\_TEMPLATE\_ALL@*.

With these rules, a template such as [ofs\_plat\_if\_tie\_off\_unused.template.sv](../src/rtl/ofs_plat_if_tie_off_unused.template.sv):

```SystemVerilog
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
```

can become the platform-specific ofs\_plat\_if\_tie\_off\_unused.sv:

```SystemVerilog
module ofs_plat_if_tie_off_unused
  #(
    // Masks are bit masks, with bit 0 corresponding to port/bank zero.
    // Set a bit in the mask when a port is IN USE by the design.
    // This way, the AFU does not need to know about every available
    // device. By default, devices are tied off.
    parameter bit [31:0] HOST_CHAN_IN_USE_MASK = 0,
    parameter bit [31:0] LOCAL_MEM_IN_USE_MASK = 0,
    parameter bit [31:0] HSSI_IN_USE_MASK = 0,

    // Emit debugging messages in simulation for tie-offs?
    parameter QUIET = 0
    )
   (
    ofs_plat_if plat_ifc
    );

    genvar i;

    generate
        for (i = 0; i < plat_ifc.host_chan.NUM_PORTS; i = i + 1)
        begin : tie_host_chan
            if (~HOST_CHAN_IN_USE_MASK[i])
            begin : m
                ofs_plat_host_chan_fiu_if_tie_off tie_off(plat_ifc.host_chan.ports[i]);

                // synthesis translate_off
                initial
                begin
                    if (QUIET == 0) $display("%m: Tied off plat_ifc.host_chan.ports[%0d]", i);
                end
                // synthesis translate_on
            end
        end
    endgenerate

    generate
        for (i = 0; i < plat_ifc.local_mem.NUM_BANKS; i = i + 1)
        begin : tie_local_mem
            if (~LOCAL_MEM_IN_USE_MASK[i])
            begin : m
                ofs_plat_local_mem_fiu_if_tie_off tie_off(plat_ifc.local_mem.banks[i]);

                // synthesis translate_off
                initial
                begin
                    if (QUIET == 0) $display("%m: Tied off plat_ifc.local_mem.banks[%0d]", i);
                end
                // synthesis translate_on
            end
        end
    endgenerate

    generate
        for (i = 0; i < plat_ifc.hssi.NUM_PORTS; i = i + 1)
        begin : tie_hssi
            if (~HSSI_IN_USE_MASK[i])
            begin : m
                ofs_plat_hssi_fiu_if_tie_off tie_off(plat_ifc.hssi.ports[i]);

                // synthesis translate_off
                initial
                begin
                    if (QUIET == 0) $display("%m: Tied off plat_ifc.hssi.ports[%0d]", i);
                end
                // synthesis translate_on
            end
        end
    endgenerate

endmodule // ofs_plat_if_tie_off_unused
```

## Sample .ini File ###

This sample .ini file is the FIM's default configuration for the n6001 board. All fields are documented in [defaults.ini](../../../plat_if_develop/ofs_plat_if/src/config/defaults.ini).

* Parameters imported from FIM packages are used whenever possible instead of numeric constants to avoid mismatches between the FIM and PIM interfaces.
* Field values may include arithmetic, such as local\_mem.addr\_width.
* The FPGA\_FAMILY definition is required by the PIM and the simulation environment.
* The *other* section is not required. It is provided with the FIM as an example to board vendors for writing board-specific interfaces. See [Platform-Specific Extensions](#platform-specific-extensions) above.

```ini
;; Platform Interface Manager configuration
;;
;; Intel® Agilex OFS FIM
;;

[define]
PLATFORM_FPGA_FAMILY_AGILEX=1
PLATFORM_FPGA_FAMILY_AGILEX7=1
;; Indicates that ASE emulation of the afu_main interface is offered
ASE_AFU_MAIN_IF_OFFERED=1
native_class=none
;; Early versions of afu_main checked INCLUDE_HSSI_AND_NOT_CVL. When
;; this macro is set, the presence of HSSI ports in afu_main() is
;; controlled by INCLUDE_HSSI.
AFU_MAIN_API_USES_INCLUDE_HSSI=1

[clocks]
pclk_freq=int'(ofs_fim_cfg_pkg::MAIN_CLK_MHZ)
;; Newer parameter, more accurate when pclk is not an integer MHz
pclk_freq_mhz_real=ofs_fim_cfg_pkg::MAIN_CLK_MHZ
native_class=none

[host_chan]
num_ports=top_cfg_pkg::PG_AFU_NUM_PORTS
native_class=native_axis_pcie_tlp
gasket=pcie_ss
data_width=ofs_pcie_ss_cfg_pkg::TDATA_WIDTH
mmio_addr_width=ofs_fim_cfg_pkg::MMIO_ADDR_WIDTH_PG
num_intr_vecs=ofs_fim_cfg_pkg::NUM_AFU_INTERRUPTS

;; Minimum number of outstanding flits that must be in flight to
;; saturate bandwidth. Maximum bandwidth is typically a function
;; of the number flits in flight, indepent of burst sizes.
max_bw_active_flits_rd=1024
max_bw_active_flits_wr=128

;; Recommended number of times an AFU should register host channel
;; signals before use in order to make successful timing closure likely.
suggested_timing_reg_stages=0

[local_mem]
enabled_by=INCLUDE_DDR4
native_class=native_axi
gasket=fim_emif_axi_mm
num_banks=ofs_fim_mem_if_pkg::NUM_MEM_CHANNELS
;; Address width (line-based, ignoring the byte offset within a line)
addr_width=ofs_fim_mem_if_pkg::AXI_MEM_ADDR_WIDTH-$clog2(ofs_fim_mem_if_pkg::AXI_MEM_WDATA_WIDTH/8)
data_width=ofs_fim_mem_if_pkg::AXI_MEM_WDATA_WIDTH
ecc_width=0
;; For consistency, the PIM always encodes burst width as if the bus were
;; Avalon. Add 1 bit: Avalon burst length is 1-based, AXI is 0-based.
burst_cnt_width=8+1
user_width=ofs_fim_mem_if_pkg::AXI_MEM_USER_WIDTH
rid_width=ofs_fim_mem_if_pkg::AXI_MEM_ID_WIDTH
wid_width=ofs_fim_mem_if_pkg::AXI_MEM_ID_WIDTH
suggested_timing_reg_stages=2

[hssi]
enabled_by=INCLUDE_HSSI
native_class=native_axis_with_fc
num_channels=ofs_fim_eth_plat_if_pkg::MAX_NUM_ETH_CHANNELS

;; Sideband interface specific to this platform. It is used for passing
;; state through plat_ifc.other.ports[] that the PIM does not manage.
[other]
;; Use the PIM's "generic" extension class. The PIM provides the top-level
;; generic wrapper around ports and the implementation of the type is set below.
template_class=generic_templates
native_class=ports
;; All PIM wrappers are vectors. Depending on the data being passed through
;; the interface, FIMs may either use more ports or put vectors inside the
;; port's type.
num_ports=1
;; Data type of the sideband interface
type=ofs_plat_fim_other_if
;; Import the "other" SystemVerilog definitions into the PIM (relative path)
import=../../ofs-common/src/fpga_family/agilex/port_gasket/afu_main_pim/extend_pim/
```