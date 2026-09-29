# model.sdc - Constraints for the core tile's timing model, the LIB views the
# chip is timed with (see timing_model.sh). Same as tile.sdc, except that
# hold at the ports stays timed, so write_timing_model gives every input a
# hold arc and the chip checks hold into the tile.
#
# Tile signoff keeps tile.sdc: the tile's clock insertion delay (1.6 ns at
# ff to 4.5 ns at ss) exceeds its 3 ns I/O delay, so port hold only means
# something against the chip's clock tree, which CTS balances to it.
source [file join [file dirname [info script]] tile.sdc]
unset_path_exceptions -hold -from [all_inputs]
unset_path_exceptions -hold -to [all_outputs]
