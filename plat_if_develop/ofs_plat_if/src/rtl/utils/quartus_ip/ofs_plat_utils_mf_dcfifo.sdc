## Copyright (C) 2024 Intel Corporation
## SPDX-License-Identifier: MIT

# constraints for DCFIFO sdc
#
# top-level sdc
# convention for module sdc apply_sdc_<module_name>
#
proc apply_sdc_dcfifo {hier_path} {
# gray_rdptr
apply_sdc_dcfifo_rdptr $hier_path
# gray_wrptr
apply_sdc_dcfifo_wrptr $hier_path
}
#
# common constraint setting proc
#
proc apply_sdc_dcfifo_for_ptrs {from_node_list to_node_list} {
# control skew for bits
set_max_skew -from $from_node_list -to $to_node_list -get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8
# path delay (exception for net delay)
if { ![string equal "quartus_syn" $::TimeQuestInfo(nameofexecutable)] } {
set_net_delay -from $from_node_list -to $to_node_list -max -get_value_from_clock_period dst_clock_period -value_multiplier 0.8
}
#relax setup and hold calculation
set_max_delay -from $from_node_list -to $to_node_list 100
set_min_delay -from $from_node_list -to $to_node_list -100
}
#
# mstable propgation delay
#
proc apply_sdc_dcfifo_mstable_delay {from_node_list to_node_list} {
# mstable delay
if { ![string equal "quartus_syn" $::TimeQuestInfo(nameofexecutable)] } {
set_net_delay -from $from_node_list -to $to_node_list -max -get_value_from_clock_period dst_clock_period -value_multiplier 0.8
}
}
#
# rdptr constraints
#
proc apply_sdc_dcfifo_rdptr {hier_path} {
# get from and to list
set from_node_list [get_keepers $hier_path|dcfifo_component|auto_generated|*rdptr_g*]
set to_node_list [get_keepers $hier_path|dcfifo_component|auto_generated|ws_dgrp|dffpipe*|dffe*]
apply_sdc_dcfifo_for_ptrs $from_node_list $to_node_list
# mstable
set from_node_mstable_list [get_keepers $hier_path|dcfifo_component|auto_generated|ws_dgrp|dffpipe*|dffe*]
set to_node_mstable_list [get_keepers $hier_path|dcfifo_component|auto_generated|ws_dgrp|dffpipe*|dffe*]
apply_sdc_dcfifo_mstable_delay $from_node_mstable_list $to_node_mstable_list
}
#
# wrptr constraints
#
proc apply_sdc_dcfifo_wrptr {hier_path} {
# control skew for bits
set from_node_list [get_keepers $hier_path|dcfifo_component|auto_generated|delayed_wrptr_g*]
set to_node_list [get_keepers $hier_path|dcfifo_component|auto_generated|rs_dgwp|dffpipe*|dffe*]
apply_sdc_dcfifo_for_ptrs $from_node_list $to_node_list
# mstable
set from_node_mstable_list [get_keepers $hier_path|dcfifo_component|auto_generated|rs_dgwp|dffpipe*|dffe*]
set to_node_mstable_list [get_keepers $hier_path|dcfifo_component|auto_generated|rs_dgwp|dffpipe*|dffe*]
apply_sdc_dcfifo_mstable_delay $from_node_mstable_list $to_node_mstable_list
}

proc apply_sdc_pre_dcfifo {entity_name} {

set inst_list [get_entity_instances -nowarn $entity_name]

foreach each_inst $inst_list {

        apply_sdc_dcfifo ${each_inst} 

    }
}

## Apply the constraints
apply_sdc_pre_dcfifo "ofs_plat_utils_mf_dcfifo"
