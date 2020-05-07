# Platform Release Updates #

This tree contains scripts that AFU developers may use to update older release trees to the latest Platform Interface Manager, configuring sources from the [../plat\_if\_develop](../plat_if_develop) tree to specific platforms. The majority of OPAE-supported boards and integrated FPGA systems shipped by Intel can be updated.

Updates leave the FIM unchanged. A release-specific PIM is added, along with a new instance of the green_bs() module that maps PR wires to PIM interfaces. Once updated, a release can be used both to synthesize older designs and to synthesize AFUs with the new PIM interface.

All updates provide an install.sh script that typically takes a single argument: the root of the release tree to update.
