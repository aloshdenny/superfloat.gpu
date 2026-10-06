# Platform bring-up: ORFS's gcd (as designs/gt2n/gcd) through to finish.
export DESIGN_NICKNAME = gcd
export DESIGN_NAME     = gcd
export PLATFORM        = gt3

export VERILOG_FILES = $(DESIGN_HOME)/src/$(DESIGN_NAME)/gcd.v
export SDC_FILE      = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NAME)/constraint.sdc

export CORE_UTILIZATION   = 25
export CORE_MARGIN        = 0.5
export PLACE_DENSITY      = 0.35
export TNS_END_PERCENT    = 100
export MAX_ROUTING_LAYER  = M7
