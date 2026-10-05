#!/usr/bin/env python3
"""LibreLane for the chip, with the tiles abstract in LVS extraction.

The chip is extracted for LVS from GDS, because ChipFoundry's vccd1/vssd1
connection macros exist only as GDS metal (their LEF is an obstruction).
Extracting the whole GDS also expands the four tiles, and the top-level
extraction then resolves the chip's straps and routing against every tile's
contents: more than 2.5 hours at 8.7 GB, against 75 s at 0.9 GB with the
tiles abstract. Each tile's own LVS is part of its signoff.

Magic.WriteLEFAbstractMacros likewise reads those cells from their LEF when
it writes the chip's LEF (lef_abstract.tcl). The chip LEF is abstract, so it
is the same; reading the tiles' GDS took the single-wide chip's LEF write to
22 GiB.

Magic.SpiceExtractionAbstractMacros reads the cells matched by
MAGIC_EXT_ABSTRACT_CELLS from their LEF (pins and power ports) and keeps them
when the GDS is read (extract_spice_abstract.tcl). The chip config puts both
steps in place of LibreLane's through meta.substituting_steps, so the chip
must be run through this script, which takes the same arguments as
`python3 -m librelane`:
    ./chip_flow.py --pdk-root ~/.ciel config.json --run-tag chip_21

OpenROAD.GlobalPlacementStrip (gpl_strip.tcl) replaces LibreLane's global
placement: it places the standard cells in the strip between the tile rows,
where every format's chip has room for them. Odb.PlacePortTies
(port_ties.py) then moves the pads' configuration ties next to their ports,
and the pin bus's output registers, cloning those the bus logic also reads.

The chip config also excludes the weakest cells (EXTRA_EXCLUDED_CELLS): at
ss their output reaches design repair's 0.5 ns slew target below 8 fF. On
such a driver repair_design's wire repair cannot split the net (the buffer
it inserts alone exceeds the driver's load budget) and inserts buffers at
the load until memory runs out: a2111oi_1 (2.2 fF) on a 33 um net took the
v2 chip's repair to 28 GB in 14 minutes, against 0.6 GB without it.

Clock tree synthesis places buffers at most 150 um apart
(CTS_DISTANCE_BETWEEN_BUFFERS). The H-tree's levels 4 to 6 split the
strip's 167 um height, too short a run for a buffer at 300 um, so a level-3
buffer drove 16 leaf buffers (signoff fanout limit 10). At 150 um none drives
more than 10, for 46 more buffers and 0.1 ns of post-CTS setup slack.

Detailed placement may move a cell up to 2,500 um vertically
(PL_MAX_DISPLACEMENT_Y). FP16's tiles reach the core's top edge, which
leaves few rows there; once the hold repair after global routing had
filled them, two wire buffers driving pads in the top-right corner had no
site within 1,500 um and detailed placement failed (chip_fp16_1). The
nearest rows are the strip's, about 2,250 um down.
"""
import os

from librelane.__main__ import cli
from librelane.steps import Magic, Odb, OpenROAD, Step

HERE = os.path.dirname(os.path.abspath(__file__))


@Step.factory.register()
class GlobalPlacementStrip(OpenROAD.GlobalPlacement):
    id = "OpenROAD.GlobalPlacementStrip"
    name = "Global placement in the strip"

    def get_script_path(self):
        return os.path.join(HERE, "gpl_strip.tcl")


@Step.factory.register()
class PlacePortTies(Odb.OdbpyStep):
    id = "Odb.PlacePortTies"
    name = "Move port tie cells next to their ports"

    def get_script_path(self):
        return os.path.join(HERE, "port_ties.py")


@Step.factory.register()
class SpiceExtractionAbstractMacros(Magic.SpiceExtraction):
    id = "Magic.SpiceExtractionAbstractMacros"
    name = "SPICE Extraction (abstract macros)"

    def get_script_path(self):
        return os.path.join(HERE, "extract_spice_abstract.tcl")


@Step.factory.register()
class WriteLEFAbstractMacros(Magic.WriteLEF):
    id = "Magic.WriteLEFAbstractMacros"
    name = "Write LEF (Magic, abstract macros)"

    # LibreLane only passes a step the variables it declares.
    config_vars = Magic.WriteLEF.config_vars + [
        v for v in Magic.SpiceExtraction.config_vars if v.name == "MAGIC_EXT_ABSTRACT_CELLS"
    ]

    def get_script_path(self):
        return os.path.join(HERE, "lef_abstract.tcl")


if __name__ == "__main__":
    cli()
