# Platform Release Updates #

This tree contains scripts for adding PIM support to legacy systems, such as PAC cards and the Broadwell integrated CPU+FPGA. It is not relevant for OFS FIMs. The scripts update older release trees to the latest Platform Interface Manager, configuring sources from the [../plat\_if\_develop](../plat_if_develop) tree for specific platforms. The majority of OPAE-supported boards and integrated FPGA systems shipped by Intel can be updated.

Before using these scripts, check whether your release tree provides its own update script in \$OPAE\_PLATFORM\_ROOT/bin/update\_pim. If present, set the OFS\_PLATFORM\_AFU\_BBB environment variable to the root of a clone of [this PIM repository](../) and run the release's update\_pim. If not, use the scripts in the tree here.

Updates leave the FIM unchanged. A release-specific PIM is added, along with a new instance of the green_bs() module that maps PR wires to PIM interfaces. Once updated, a release can be used both to synthesize older designs and to synthesize AFUs with the new PIM interface.

All updates provide an install.sh script that typically takes a single argument: the root of the release tree to update.
