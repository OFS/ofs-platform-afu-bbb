# PIM Configuration .ini Files

The Platform Interface Manager instance for a board is configured by a single .ini file. This board configuration is described [here](../../docs/PIM_board_vendors.md). For recent OFS systems, only [defaults.ini](defaults.ini) is relevant since OFS FIMs provide a PIM configuration .ini file along with OFS sources. The other .ini files here describe legacy cards that predate OFS.

A board's .ini file is consumed by [PIM scripts](../../scripts/), written in Python. [Defaults.ini](defaults.ini) is loaded automatically by these scripts in order to define the base environment. The file also serves as documentation, with comments describing configuration choices.
