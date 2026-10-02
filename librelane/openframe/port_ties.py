# Move the tie cells that drive ports to the row nearest their ports (odbpy
# script, run by chip_flow.py's Odb.PlacePortTies step after global
# placement).
#
# The ports are the pads' configuration inputs, on the die edge. Global
# placement in the strip (gpl_strip.tcl) leaves their tie cells there: 572
# constant nets of ~1.5 mm, which design repair would buffer before it
# splits the ties.
from reader import click_odb, click


def center(box):
    return (box.xMin() + box.xMax()) / 2.0, (box.yMin() + box.yMax()) / 2.0


@click.command()
@click_odb
def cli(reader):
    blk = reader.block
    rows = list(blk.getRows())
    site_w = rows[0].getSite().getWidth()
    moved = 0
    for inst in blk.getInsts():
        if inst.isFixed() or "conb" not in inst.getMaster().getName():
            continue
        ports = [center(bt.getBBox()) for it in inst.getITerms() if it.getNet() is not None
                 for bt in it.getNet().getBTerms()]
        if not ports:
            continue
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
        moved += 1
    print(f"[INFO] moved {moved} port tie cells next to their ports")


if __name__ == "__main__":
    cli()
