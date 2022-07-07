# PIM Sideband (other) Extension

"Other" is a simple wrapper class in the PIM around a type that must be provided by a platform implementation. It is a mechanism for passing state through the PIM, allowing the platform to define the data type and tie-off module.

## Purpose

Some platforms may have ports flowing into afu\_main\(\) that are not universal and apply only to a specific configuration. The mechanism defined here allows for extension of the PIM interface without having to modify the core PIM sources. You might choose to use this method for cases such as:

- Nonstandard clock or reset.
- Power or temperature control signals.
- Sideband flow control that does not fit into a normal AXI-S protocol, such as HSSI XON/XOFF.

## Mechanism

The "other" type is added to the PIM by adding the following to a platform's PIM .ini file:

```ini
[other]
native_class=extern
import=<relative path from .ini file to this extend_pim directory>
```

The keywords "other" and "extern" load a wrapper class that is predefined as a template here: [ofs\_plat\_other\_GROUP\_fiu\_if.sv](ofs_plat_other_GROUP_fiu_if.sv). The wrapper class instantiates an fs\_plat\_other\_extern\_if interface that must be provided by the FIM. This class may be modified as needed without requiring any changes to the PIM. It will be added to the PIM's top-level plat\_ifc as:

```SystemVerilog
plat_ifc.other.ports[0]
```

The vector of ports is used because all PIM interfaces are vectors.

A tie-off module ofs\_plat\_other\_fiu\_if\_tie\_off\(\) must also be provided. The PIM instantiates the tie-off automatically unless it is explicitly disabled with the usual mechanism of setting the "OTHER\_IN\_USE\_MASK" to 1 in ofs\_plat\_if\_tie\_off\_unused.
