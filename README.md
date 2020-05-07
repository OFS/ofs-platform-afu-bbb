# OFS Platform Components #

The Platform Interface Manager (PIM) is an abstraction layer between an AFU and the system layer — the FPGA Interface Manager (FIM). The FIM is the base system layer, typically provided by board vendors. The FIM interface is specific to a particular physical platform. The PIM enables the construction of portable AFUs.

The Platform Interface Manager (PIM) code in this repository has components aimed at two classes of developers: board vendors providing FIMs and accelerator developers writing RTL-based AFUs. Board vendors configure the FIM-side, platform-specific, PIM interface and AFU developers attach to the PIM's platform-independent interface.

Contents:

* [Board Vendors: Generating a Release and Configuring the PIM](plat_if_develop/ofs_plat_if/docs/PIM_board_vendors.md)
* [AFU Developers: Connecting an AFU to a Platform](plat_if_develop/ofs_plat_if/docs/PIM_AFU_interface.md)

Whatever your role, you may find that reading both sections makes it easier to understand how all the components fit together.

This repository holds interface components and Basic Building Blocks (BBBs)
that are specific either to an FPGA architecture or a particular physical
platform. The repository is the sibling of the [platform-independent BBB
repository](https://github.com/OPAE/intel-fpga-bbb).
