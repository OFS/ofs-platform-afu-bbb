##
## Avalon interface shim timing constraints.
##

## Reset for clock crossing
set_false_path -from [get_keepers *|ofs_plat_avalon_mem_rdwr_slave_reset]
