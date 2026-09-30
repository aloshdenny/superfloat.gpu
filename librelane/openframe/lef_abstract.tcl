# Copyright 2025 LibreLane Contributors
#
# Adapted from OpenLane
#
# Copyright 2020-2023 Efabless Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Modified for superfloat.gpu (librelane/openframe/chip_flow.py): cells
# matched by MAGIC_EXT_ABSTRACT_CELLS are read from their LEF abstracts
# rather than from their GDS. The chip's LEF is an abstract view, so the
# tiles' contents do not change it, and reading their GDS took the step to
# 22 GiB.

# Macros matched by MAGIC_EXT_ABSTRACT_CELLS from their LEF (matched by file
# name: core_tile.lef defines core_tile), every other macro from its GDS.
proc read_macro_views {} {
    set abstract [list]
    if { [info exists ::env(MAGIC_EXT_ABSTRACT_CELLS)] } {
        foreach lef $::env(MACRO_LEFS) {
            set cell [file rootname [file tail $lef]]
            foreach expression $::env(MAGIC_EXT_ABSTRACT_CELLS) {
                if { [regexp $expression $cell] } {
                    puts "> lef read $lef"
                    lef read $lef
                    lappend abstract $cell
                    break
                }
            }
        }
    }
    if { ![info exists ::env(MACRO_GDS_FILES)] } {
        return
    }
    set old [list [gds rescale] [gds readonly]]
    gds rescale false
    gds readonly true
    foreach gds_file $::env(MACRO_GDS_FILES) {
        if { [lsearch -exact $abstract [file rootname [file tail $gds_file]]] < 0 } {
            puts "> gds read $gds_file"
            gds read $gds_file
        }
    }
    gds rescale [lindex $old 0]
    gds readonly [lindex $old 1]
}

drc off
crashbackups disable
locking disable

if { $::env(MAGIC_LEF_WRITE_USE_GDS) } {
    gds read $::env(CURRENT_GDS)
} else {
    source $::env(SCRIPTS_DIR)/magic/common/read.tcl
    read_tech_lef
    read_pdk_gds
    read_macro_views
    read_extra_gds
    read_pad_gds
    load (REFRESHLAYOUT?)
    read_def
}

if { [info exists ::env(VDD_NETS)] || [info exists ::env(GND_NETS)] } {
    # they both must exist and be equal in length
    # current assumption: they cannot have a common ground
    if { ! [info exists ::env(VDD_NETS)] || ! [info exists ::env(GND_NETS)] } {
        puts stderr "\[ERROR\] VDD_NETS and GND_NETS must *both* either be defined or undefined"
        exit -1
    }
} else {
    set ::env(VDD_NETS) $::env(VDD_PIN)
    set ::env(GND_NETS) $::env(GND_PIN)
}

puts "\[INFO\] Ignoring '$::env(VDD_NETS) $::env(GND_NETS)'"
lef nocheck $::env(VDD_NETS) $::env(GND_NETS)

# Write LEF
set lefwrite_opts [list]
if { $::env(MAGIC_WRITE_FULL_LEF) } {
    puts "\[INFO\] Writing non-abstract (full) LEF…"
} else {
    lappend lefwrite_opts -hide
    puts "\[INFO\] Writing abstract LEF…"
}
if { $::env(MAGIC_WRITE_LEF_PINONLY) } {
    puts "\[INFO\] Specifying -pinonly (nets connected to pins on the same layer are declared as obstructions)…"
    lappend lefwrite_opts -pinonly
} else {
    puts "\[INFO\] Not specifiying -pinonly (nets connected to pins on the same layer are declared as part of the pin)…"
}
lef write $::env(STEP_DIR)/$::env(DESIGN_NAME).lef {*}$lefwrite_opts
puts "\[INFO\] LEF Write Complete."
