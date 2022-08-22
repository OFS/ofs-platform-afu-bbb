# PIM Scripts

The scripts here are key to building the Platform Interface Manager. The PIM source tree holds multiple implementations of the same interfaces, typically varying by the underlying physical interface of a particular device. Scripts choose the proper subset of PIM sources to map from standard PIM AFU interfaces to physical hardware.

OFS FIM build scripts invoke these scripts in order to generate board-specific PIM instances.

## gen\_ofs\_plat\_if

gen\_ofs\_plat\_if is the primary PIM construction script. Given an .ini file describing a platform, the script consumes [templatized RTL sources](../src/rtl/) and produces a FIM-specific PIM instance. Templates make it possible for the source tree to support multiple devices of similar types, such as both DDR and HBM, on a single board.

## gen\_platform\_src\_cfg

gen\_platform\_src\_cfg walks an RTL tree and builds wrappers that load all sources found within the tree into Quartus or an RTL simulator. SystemVerilog requires that packages be specified in dependence order. The script includes a simple parser that detects package references, constructs a dependence tree for all discovered packages, and emits package imports in a legal order.

The main gen\_ofs\_plat\_if template mapping script depends on gen\_platform\_src\_cfg to build the files that import the generated PIM.

## gen\_ofs\_plat\_json

Given an input .ini configuration file, gen\_ofs\_plat\_json constructs a JSON file that describes the PIM interfaces available on a specific platform. The generated JSON file describing the platform was more important in older versions of the PIM, in which an AFU's JSON file described exactly which interfaces are required and the [afu\_platform\_config](https://github.com/OPAE/opae-sdk/blob/master/platforms/scripts/afu_platform_config) script from the [OPAE SDK](https://github.com/OPAE/opae-sdk/) generated RTL. The current PIM simply expects a single ofs\_plat\_afu class in the platform-description JSON, leaving interface mapping to RTL macros and parameters. This leaves the majority of the tables emitted by this module important only for legacy support.

The output of gen\_ofs\_plat\_json is typically written to an out-of-tree PR release tree in \$OPAE\_PLATFORM\_ROOT/hw/lib/platform/platform\_db.
