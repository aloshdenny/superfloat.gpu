# KLayout batch render of a GDS for the shuttle-plan figures:
#   klayout -b -r render_gds.py -rd gds=<file> -rd lyp=<file> -rd out=<png> -rd w=<px>
#           [-rd show=<l/d,...>] [-rd hide=<l/d,...>]
# With `show`, only those layers are drawn; otherwise all but fill shapes
# (datatype 28 on SKY130) and `hide`.
import pya

lv = pya.LayoutView()
lv.set_config("background-color", "#000000")
lv.set_config("grid-visible", "false")
lv.set_config("text-visible", "false")
lv.load_layout(gds, True)
lv.load_layer_props(lyp)
lv.max_hier()
def pairs(name):
    v = globals().get(name)
    return {tuple(int(x) for x in s.split("/")) for s in v.split(",")} if v else set()


hidden, shown = pairs("hide"), pairs("show")
it = lv.begin_layers()
while not it.at_end():
    p = it.current()
    key = (p.source_layer, p.source_datatype)
    if (shown and key not in shown) or (not shown and (p.source_datatype == 28 or key in hidden)):
        p.visible = False
    it.next()
lv.zoom_fit()
cv = lv.active_cellview()
box = cv.cell.dbbox()
W = int(w)
H = int(W * box.height() / box.width())
lv.save_image(out, W, H)
print(f"rendered {out} {W}x{H}, die {box.width():.1f} x {box.height():.1f} um")
