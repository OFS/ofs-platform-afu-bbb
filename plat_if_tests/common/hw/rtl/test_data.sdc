##
## Multi-cycle hashing.
##
## The output of the XOR tree is consumed many cycles after the inputs stabilize.
##
set_multicycle_path -setup -to [get_registers {*|ofs_plat_afu|*|test_data_hash_reduce_regs*}] 8
set_multicycle_path -hold  -to [get_registers {*|ofs_plat_afu|*|test_data_hash_reduce_regs*}] 7
