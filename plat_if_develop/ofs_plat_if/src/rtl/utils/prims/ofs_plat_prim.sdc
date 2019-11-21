##
## Platform interface primitives timing constraints.
##

##
## Generic, simple register clock crossing (ofs_plat_prim_clock_crossing_reg)
##
set_false_path -from [get_keepers *|ofs_plat_cc_reg_vec[0]*]
set_false_path -from [get_keepers *|ofs_plat_cc_reg_async]
