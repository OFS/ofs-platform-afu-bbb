##
## Platform interface CCI-P timing constraints.
##

##
## These signals in ccip_async_shim are in the pClk domain as the last stage
## before clock crossing.
##
set_false_path -from [get_keepers *|ofs_plat_clock_crossing.ccip_async_shim|reset[0]]
set_false_path -from [get_keepers *|ofs_plat_clock_crossing.ccip_async_shim|error[0]]
set_false_path -from [get_keepers *|ofs_plat_clock_crossing.ccip_async_shim|pwrState[0]*]
set_false_path -from [get_keepers *|ofs_plat_clock_crossing.ccip_async_shim|async_shim_error_fiu*]

## CCI-P to Avalon MMIO bridge clock crossing
set_false_path -from [get_keepers *|ofs_av_mmio_impl|reset_fclk]
set_false_path -from [get_keepers *|ofs_plat_avalon_host_mem_afu_reset[0]]
set_false_path -from [get_keepers *|ofs_plat_avalon_host_mem_afu_pwrState[0]*]
