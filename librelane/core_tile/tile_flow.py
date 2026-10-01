#!/usr/bin/env python3
"""LibreLane for the core tile, with the step that splits clock buffers over
the fanout limit (clock_split.py). eco_fix.py runs tile ECOs through this
script; it takes the same arguments as `python3 -m librelane`:
    ./tile_flow.py --pdk-root ~/.ciel eco_<run>.json --with-initial-state ... --run-tag <run>_eco
"""
import os

from librelane.__main__ import cli
from librelane.steps import Odb, Step

HERE = os.path.dirname(os.path.abspath(__file__))


@Step.factory.register()
class SplitClockFanout(Odb.InsertECOBuffers):
    id = "Odb.SplitClockFanout"
    name = "Split clock buffers over the fanout limit"

    def get_script_path(self):
        return os.path.join(HERE, "clock_split.py")


if __name__ == "__main__":
    cli()
