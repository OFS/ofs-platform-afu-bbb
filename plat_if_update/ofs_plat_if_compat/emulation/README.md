Updates here modify existing platforms to emulate configurations not
available on real hardware. The emulated platforms are generally used for
testing features of the PIM. Typically, the emulated platforms have extra
ports, often implemented by multiplexing multiple emulated ports on top of
a single physical port.

* __d5005\_ias\_em\_hc2cx2c__
  + Two groups of CCI-P host channels. Each group has two CCI-P ports.
  + MMIO and interrupts are supported only on group 0 port 0.
