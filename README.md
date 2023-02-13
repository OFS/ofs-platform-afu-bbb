# OFS Platform Components #

The Platform Interface Manager (PIM) is an abstraction layer between an AFU and the system layer — the FPGA Interface Manager (FIM). The FIM is the base system layer, typically provided by board vendors. The FIM interface is specific to a particular physical platform. The PIM enables the construction of portable AFUs.

The Platform Interface Manager (PIM) code in this repository has components aimed at two classes of developers: board vendors providing FIMs and accelerator developers writing RTL-based AFUs. Board vendors configure the PIM's platform-specific FIM interface and AFU developers attach to the PIM's platform-independent interface.

Contents:

* [PIM Core Concepts](plat_if_develop/ofs_plat_if/docs/PIM_core_concepts.md)
* [Board Vendors: Generating a Release and Configuring the PIM](plat_if_develop/ofs_plat_if/docs/PIM_board_vendors.md)
* [AFU Developers: Connecting an AFU to a Platform](plat_if_develop/ofs_plat_if/docs/PIM_AFU_interface.md)
  * [Host channel interfaces](plat_if_develop/ofs_plat_if/docs/PIM_ifc_host_channel.md)

Whatever your role, you may find that reading both the board vendor and AFU developer sections makes it easier to understand how all the components fit together.
