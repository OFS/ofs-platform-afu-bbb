##
## Platform interface local memory as Avalon timing constraints.
##

##
## Reset path to local memory clock after clock crossing.
##
set_false_path -to [get_keepers *|ofs_plat_clock_crossing.local_mem_reset_pipe[0]]
