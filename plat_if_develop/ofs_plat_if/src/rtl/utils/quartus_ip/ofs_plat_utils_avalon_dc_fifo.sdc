## Copyright (C) 2024 Intel Corporation
## SPDX-License-Identifier: MIT

# $File: //acds/rel/24.1/ip/iconnect/avalon_st/ofs_plat_utils_avalon_dc_fifo/ofs_plat_utils_avalon_dc_fifo.sdc $
# $Revision: #1 $
# $Date: 2024/02/01 $
# $Author: psgswbuild $

#-------------------------------------------------------------------------------
# TimeQuest constraints to constrain the timing across asynchronous clock domain crossings.
# The idea is to minimize skew to less than one launch clock period to keep the gray encoding, 
# and to minimize latency on the pointer crossings.
#
# The paths are from the Gray Code read and write pointers to their respective synchronizer banks.
#
# *** Important note *** 
#
# Do not declare the FIFO clocks as asynchronous at the top level, or false path these crossings,
# because that will override these constraints.
#-------------------------------------------------------------------------------
set all_dc_fifo [get_entity_instances -nowarn ofs_plat_utils_avalon_dc_fifo]

set_max_delay -from [get_registers {*|in_wr_ptr_gray[*]}] -to [get_registers {*|ofs_plat_utils_dcfifo_synchronizer_bundle:write_crosser|ofs_plat_utils_std_synchronizer_nocut:sync[*].u|din_s1}] 200
set_min_delay -from [get_registers {*|in_wr_ptr_gray[*]}] -to [get_registers {*|ofs_plat_utils_dcfifo_synchronizer_bundle:write_crosser|ofs_plat_utils_std_synchronizer_nocut:sync[*].u|din_s1}] -200

set_max_delay -from [get_registers {*|out_rd_ptr_gray[*]}] -to [get_registers {*|ofs_plat_utils_dcfifo_synchronizer_bundle:read_crosser|ofs_plat_utils_std_synchronizer_nocut:sync[*].u|din_s1}] 200
set_min_delay -from [get_registers {*|out_rd_ptr_gray[*]}] -to [get_registers {*|ofs_plat_utils_dcfifo_synchronizer_bundle:read_crosser|ofs_plat_utils_std_synchronizer_nocut:sync[*].u|din_s1}] -200

set_net_delay -max -get_value_from_clock_period dst_clock_period -value_multiplier 0.8 -from [get_pins -compatibility_mode {*|in_wr_ptr_gray[*]*}] -to [get_registers {*|ofs_plat_utils_dcfifo_synchronizer_bundle:write_crosser|ofs_plat_utils_std_synchronizer_nocut:sync[*].u|din_s1}] 
set_net_delay -max -get_value_from_clock_period dst_clock_period -value_multiplier 0.8 -from [get_pins -compatibility_mode {*|out_rd_ptr_gray[*]*}] -to [get_registers {*|ofs_plat_utils_dcfifo_synchronizer_bundle:read_crosser|ofs_plat_utils_std_synchronizer_nocut:sync[*].u|din_s1}]


foreach dc_fifo_inst $all_dc_fifo {
   if { [ llength [query_collection -report -all [get_registers $dc_fifo_inst|in_wr_ptr_gray[*]]]] > 0  } {
      set_max_skew -get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8  -from [get_registers $dc_fifo_inst|in_wr_ptr_gray[*]] -to [get_registers $dc_fifo_inst|write_crosser|sync[*].u|din_s1] 
   }

   if { [ llength [query_collection -report -all [get_registers $dc_fifo_inst|out_rd_ptr_gray[*]]]] > 0 } {
      set_max_skew -get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8  -from [get_registers $dc_fifo_inst|out_rd_ptr_gray[*]] -to [get_registers $dc_fifo_inst|read_crosser|sync[*].u|din_s1] 
   }
}

set aclr_collection_wr [get_pins -compatibility_mode -nocase -nowarn *|write_reset_sync|ofs_plat_utils_reset_synchronizer_int_chain*|aclr]
set clrn_collection_wr [get_pins -compatibility_mode -nocase -nowarn *|write_reset_sync|ofs_plat_utils_reset_synchronizer_int_chain*|clrn]
set aclr_counter_wr [get_collection_size $aclr_collection_wr]
set clrn_counter_wr [get_collection_size $clrn_collection_wr]



if {$aclr_counter_wr > 0} {
set_false_path -to [get_pins -compatibility_mode -nocase *|write_reset_sync|ofs_plat_utils_reset_synchronizer_int_chain*|aclr]
}



if {$clrn_counter_wr > 0} {
set_false_path -to [get_pins -compatibility_mode -nocase *|write_reset_sync|ofs_plat_utils_reset_synchronizer_int_chain*|clrn]
}




set aclr_collection_rd [get_pins -compatibility_mode -nocase -nowarn *|read_reset_sync|ofs_plat_utils_reset_synchronizer_int_chain*|aclr]
set clrn_collection_rd [get_pins -compatibility_mode -nocase -nowarn *|read_reset_sync|ofs_plat_utils_reset_synchronizer_int_chain*|clrn]
set aclr_counter_rd [get_collection_size $aclr_collection_rd]
set clrn_counter_rd [get_collection_size $clrn_collection_rd]



if {$aclr_counter_rd > 0} {
set_false_path -to [get_pins -compatibility_mode -nocase *|read_reset_sync|ofs_plat_utils_reset_synchronizer_int_chain*|aclr]
}



if {$clrn_counter_rd > 0} {
set_false_path -to [get_pins -compatibility_mode -nocase *|read_reset_sync|ofs_plat_utils_reset_synchronizer_int_chain*|clrn]
}

# add in timing constraints across asynchronous clock domain crossings for simple dual clock memory inference

# -----------------------------------------------------------------------------
# This procedure constrains the skew between the pointer bits, and should
# be called from the top level SDC, once per instance of the FIFO.
#
# The hierarchy path to the FIFO instance is required as an 
# argument.
# -----------------------------------------------------------------------------
proc constrain_ofs_plat_utils_avalon_dc_fifo_ptr_skew { path } {

    set_max_skew -get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8 -from [ get_registers $path|in_wr_ptr_gray\[*\] ] -to [ get_registers $path|write_crosser|sync\[*\].u|din_s1 ]
    set_max_skew -get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8 -from [ get_registers $path|out_rd_ptr_gray\[*\] ] -to [ get_registers $path|read_crosser|sync\[*\].u|din_s1 ]

}
