# OFS Platform Components #

This repository holds interface components and Basic Building Blocks (BBBs)
that are specific either to an FPGA architecture or a particular physical
platform. The repository is the sibling of the [platform-independent BBB
repository](https://github.com/OPAE/intel-fpga-bbb).

## [plat_if_develop](plat_if_develop) ##

The Platform Interface Manager (PIM) is an abstraction layer between an AFU
and the partial-reconfiguration boundary to the FPGA Interface Manager
(FIM). The FIM is the base system layer, typically provided by board
vendors. The FIM interface is specific to a particular physical
platform. The PIM enables the construction of portable AFUs.

The plat_if_develop tree is typically used by a board vendor to construct a
PIM for a particular platform release. The constructed PIM ships as part of
a platform release, along with a board. The plat_if_develop tree is not
aimed at developers of individual AFUs.

## [plat_if_update](plat_if_update) ##

The plat_if_update tree contains scripts that AFU developers may use to
update older release trees to the latest Platform Interface Manager from
the plat_if_develop tree. The majority of OPAE-supported boards and
integrated FPGA systems shipped by Intel can be updated.
