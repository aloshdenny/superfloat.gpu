# Split clock buffers whose fanout exceeds MAX_FANOUT (odbpy script, run by
# tile_flow.py's Odb.SplitClockFanout step).
#
# Clock tree synthesis has no fanout limit, and on a short tile it left
# buffers driving 16 sinks against the signoff limit of 10. Each such buffer
# gets ceil(n / MAX_FANOUT) - 1 siblings: the same cell on the same input net,
# each driving its share of the sinks, split by position along the axis they
# spread most on, and placed at its share's centroid. Placement is then
# legalized and the global routes of the touched nets updated, as
# eco_buffer.py does.
import math
import sys

from reader import click_odb, click, odb
import grt as GRT

MAX_FANOUT = 8          # the place-and-route fanout target (signoff limit: 10)


def centroid(iterms):
    xs = [it.getInst().getLocation()[0] for it in iterms]
    ys = [it.getInst().getLocation()[1] for it in iterms]
    return sum(xs) // len(xs), sum(ys) // len(ys)


@click.command()
@click_odb
def cli(reader):
    grt = reader.design.getGlobalRouter()
    dpl = reader.design.getOpendp()

    locked = []
    for inst in reader.block.getInsts():
        if inst.getPlacementStatus() != "LOCKED":
            locked.append((inst, inst.getPlacementStatus()))
            inst.setPlacementStatus("LOCKED")

    reader._grt_setup(grt)
    grt_inc = GRT.IncrementalGRoute(grt, reader.block)

    targets = []
    for inst in reader.block.getInsts():
        if "clkbuf" not in inst.getMaster().getName():
            continue
        out = [it for it in inst.getITerms() if it.isOutputSignal() and it.getNet() is not None]
        inp = [it for it in inst.getITerms() if it.isInputSignal() and it.getNet() is not None]
        if not out or not inp:
            continue
        sinks = [it for it in out[0].getNet().getITerms() if it.isInputSignal()]
        if len(sinks) > MAX_FANOUT:
            targets.append((inst, inp[0], out[0], sinks))

    added = 0
    for inst, inp, out, sinks in targets:
        k = math.ceil(len(sinks) / MAX_FANOUT)
        xs = [it.getInst().getLocation()[0] for it in sinks]
        ys = [it.getInst().getLocation()[1] for it in sinks]
        axis = 0 if (max(xs) - min(xs)) >= (max(ys) - min(ys)) else 1
        sinks = sorted(sinks, key=lambda it: it.getInst().getLocation()[axis])
        groups = [sinks[i * len(sinks) // k:(i + 1) * len(sinks) // k] for i in range(k)]
        in_net, out_net = inp.getNet(), out.getNet()
        master = inst.getMaster()
        for gi, group in enumerate(groups[1:], start=1):
            name = f"{inst.getName()}_split{gi}"
            sib = odb.dbInst.create(reader.block, master, name)
            net = odb.dbNet.create(reader.block, f"{out_net.getName()}_split{gi}")
            net.setSigType("CLOCK")
            for it in sib.getITerms():
                if it.isInputSignal():
                    it.connect(in_net)
                elif it.isOutputSignal():
                    it.connect(net)
            for it in group:
                it.disconnect()
                it.connect(net)
            sib.setOrient("R0")
            sib.setLocation(*centroid(group))
            sib.setPlacementStatus("PLACED")
            grt.addDirtyNet(net)
            added += 1
        grt.addDirtyNet(in_net)
        grt.addDirtyNet(out_net)
        print(f"{inst.getName()}: fanout {len(sinks)} split into {k}")

    print(f"[INFO] {len(targets)} clock buffers over fanout {MAX_FANOUT}, {added} siblings added")
    if added:
        site = reader.rows[0].getSite()
        max_disp_x = int(reader.design.micronToDBU(reader.config["PL_MAX_DISPLACEMENT_X"]) / site.getWidth())
        max_disp_y = int(reader.design.micronToDBU(reader.config["PL_MAX_DISPLACEMENT_Y"]) / site.getHeight())
        dpl.detailedPlacement(max_disp_x, max_disp_y)
        grt_inc.updateRoutes(True)

    for inst, status in locked:
        inst.setPlacementStatus(status)


if __name__ == "__main__":
    cli()
