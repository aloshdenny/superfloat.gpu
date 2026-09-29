"""
NUMBER_FORMAT of the design under test: 0 SF16, 1 FP16, 2 BF16.

Read from the top-level parameter when the simulator exposes it, else from
the NUMBER_FORMAT environment variable (the Makefile exports the value it
compiled with).
"""
import os

from .fp16fmt import BY_ID

NAMES = {0: "sf16", 1: "fp16", 2: "bf16"}


def number_format(dut) -> int:
    try:
        return int(dut.NUMBER_FORMAT.value)
    except (AttributeError, ValueError, TypeError):
        return int(os.environ.get("NUMBER_FORMAT", "0"))


def fp_format(fmt_id: int):
    """The Fmt model for FP16/BF16, or None for SF16."""
    return BY_ID.get(fmt_id)
