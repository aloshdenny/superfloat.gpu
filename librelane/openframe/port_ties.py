# Move the tie cells and the output registers that drive ports to the row
# nearest their ports (odbpy script, run by chip_flow.py's Odb.PlacePortTies
# step after global placement).
#
# The ports are on the die edge. Global placement in the strip
# (gpl_strip.tcl) leaves their drivers there:
#   - Tie cells, for the pads' configuration inputs: 572 constant nets of
#     ~1.5 mm, which design repair would buffer before it splits the ties.
#   - The pin bus's output registers. Their clock comes about 8.5 ns into
#     the cycle (the clock tree matches the tiles' insertion delay), so a
#     register-to-pad path has about 7 ns for the wire to the pad, and FP16's
#     full-height tiles leave no rows to buffer it over them (chip_fp16_2:
#     gpio_out[17] -1.93 ns at max_ss). Beside its pad, the register's input
#     takes the long wire, with the whole cycle for it. A register that also
#     feeds the bus logic (the FSM reads bus_we, bus_req, ...) is cloned:
#     the copy shares its D, clock and reset and drives only the pad's
#     buffer, so both hold the same value every cycle.
import odb
from reader import click_odb, click


def center(box):
    return (box.xMin() + box.xMax()) / 2.0, (box.yMin() + box.yMax()) / 2.0


@click.command()
@click_odb
def cli(reader):
    blk = reader.block
    rows = list(blk.getRows())
    site_w = rows[0].getSite().getWidth()
    def place_near(inst, ports):
        tx = sum(p[0] for p in ports) / len(ports)
        ty = sum(p[1] for p in ports) / len(ports)
        w = inst.getMaster().getWidth()
        best = None
        for row in rows:
            b = row.getBBox()
            if b.xMax() - b.xMin() < w:
                continue
            x = min(max(tx - w / 2.0, b.xMin()), b.xMax() - w)
            d = abs(x + w / 2.0 - tx) + abs(b.yMin() - ty)
            if best is None or d < best[0]:
                best = (d, x, row)
        _, x, row = best
        b = row.getBBox()
        inst.setOrient(row.getOrient())
        inst.setLocation(int(b.xMin() + (int(x) - b.xMin()) // site_w * site_w), b.yMin())
        inst.setPlacementStatus("PLACED")   # a new clone starts unplaced

    ties = 0
    for inst in blk.getInsts():
        if inst.isFixed() or "conb" not in inst.getMaster().getName():
            continue
        ports = [center(bt.getBBox()) for it in inst.getITerms() if it.getNet() is not None
                 for bt in it.getNet().getBTerms()]
        if ports:
            place_near(inst, ports)
            ties += 1
    # Output ports driven by a register, directly or through one buffer
    # (synthesis buffers every output).
    def only(its):
        return its[0] if len(its) == 1 else None

    regs = clones = 0
    for bt in blk.getBTerms():
        net = bt.getNet()
        if net is None or bt.getIoType() != "OUTPUT" or len(net.getBTerms()) != 1:
            continue
        drv = only([it for it in net.getITerms() if it.isOutputSignal()])
        if drv is None or [it for it in net.getITerms() if it.isInputSignal()]:
            continue
        port = [center(bt.getBBox())]
        buf, reg_out = None, drv
        if not drv.getInst().getMaster().isSequential():
            buf = drv.getInst()
            a = only([it for it in buf.getITerms() if it.isInputSignal()])
            if a is None or a.getNet() is None:
                continue
            reg_out = only([it for it in a.getNet().getITerms() if it.isOutputSignal()])
            if reg_out is None or not reg_out.getInst().getMaster().isSequential():
                continue
        reg = reg_out.getInst()
        if reg.isFixed():
            continue
        shared = [it for it in reg_out.getNet().getITerms()
                  if it.isInputSignal() and (buf is None or it.getInst() != buf)]
        if shared or reg_out.getNet().getBTerms() and buf is not None:
            if buf is None:
                continue
            # Clone the register for the pad: same inputs, its own output net.
            copy = odb.dbInst.create(blk, reg.getMaster(), reg.getName() + "_pad")
            qnet = odb.dbNet.create(blk, reg.getName() + "_pad_q")
            for it in reg.getITerms():
                if it.getNet() is None:
                    continue
                ci = copy.findITerm(it.getMTerm().getName())
                ci.connect(qnet if it.isOutputSignal() else it.getNet())
            a = only([it for it in buf.getITerms() if it.isInputSignal()])
            a.disconnect()
            a.connect(qnet)
            reg = copy
            clones += 1
        place_near(reg, port)
        if buf is not None:
            place_near(buf, port)
        regs += 1
    print(f"[INFO] moved {ties} port tie cells and {regs} output registers ({clones} cloned) next to their ports")


if __name__ == "__main__":
    cli()
