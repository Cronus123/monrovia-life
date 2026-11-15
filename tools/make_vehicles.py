"""
Monrovia Life - builds the game's vehicles (proto3d/models/veh_<kind>.glb).

Cars, trucks and vans come from Kenney's Car Kit (CC0 1.0, third_party/kenney-car-kit),
re-worked for the game:
  - turned to face +X (the game rotates them to drive along -Z), scaled to real size,
    wheels sitting at z = 0, each wheel a separate object with its origin at its hub
  - the body split into materials: "Glass" (see-through windows), "Paint" (the main
    body colour, recoloured per car in the game), "colormap" (everything else)
  - a simple interior behind the glass (cabin lining, seats, dashboard, steering wheel)
  - light objects the game switches: light_head, light_tail (tail/brake), light_ind_l /
    light_ind_r (indicators), plus number plates
  - liveries: TAXI and POLICE lettering, an armoured cash van with plates and window bars
The keke (tricycle taxi), which no pack has, is modelled here in the same style.

Run:  blender -b -P tools/make_vehicles.py            (all)
      blender -b -P tools/make_vehicles.py -- keke    (some)
"""
import bmesh
import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
KIT = os.path.join(ROOT, "third_party", "kenney-car-kit", "Models", "GLB format")
OUT = os.path.join(ROOT, "proto3d", "models")

# kind: source model, length (m), livery, paint colour (sRGB hex; None = keep the model's)
SPECS = {
    "car": ("sedan", 4.5, None, None),
    "taxi": ("taxi", 4.5, "TAXI", "#f5c518"),
    "police": ("police", 4.7, "POLICE", None),
    "suv": ("suv", 4.8, None, None),
    "sport": ("sedan-sports", 4.4, None, None),
    "pickup": ("truck", 5.2, None, None),
    "minibus": ("van", 5.0, None, None),
    "truck": ("delivery", 7.0, None, None),
    "van": ("van", 5.2, "ARMOURED", "#3e4a3d"),
}


def srgb_lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)


def material(name, color, emission=None, rough=0.6, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    if b is not None:
        b.inputs["Base Color"].default_value = color
        b.inputs["Roughness"].default_value = rough
        if emission is not None:
            b.inputs["Emission Color"].default_value = emission
            b.inputs["Emission Strength"].default_value = 1.0
        if alpha < 1.0:
            b.inputs["Alpha"].default_value = alpha
    m.diffuse_color = color
    m.use_backface_culling = True
    return m


def new_obj(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def box(name, center, size, mat, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(center) @ Matrix.Diagonal(Vector(size + (1,))))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=2, affect="EDGES")
    return new_obj(name, bm, mat)


def cylinder(name, center, radius, depth, mat, axis="Y", segs=16):
    bm = bmesh.new()
    rot = {"Y": Matrix.Rotation(math.pi / 2, 4, "X"), "X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Z": Matrix.Identity(4)}[axis]
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=radius, depth=depth,
                          matrix=Matrix.Translation(center) @ rot)
    return new_obj(name, bm, mat)


def text(name, s, center, size, mat, side):
    """Lettering on a side of the car (side = +1 left / -1 right, facing outwards)."""
    bpy.ops.object.text_add(location=(0, 0, 0))
    ob = bpy.context.object
    ob.data.body = s
    ob.data.size = size
    ob.data.extrude = 0.003
    ob.data.align_x = "CENTER"
    ob.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.object
    ob.name = name
    if side < 0:
        ob.rotation_euler = (math.pi / 2, 0, 0)          # faces -Y, reads toward +X
    else:
        ob.rotation_euler = (math.pi / 2, 0, math.pi)     # faces +Y, reads toward the rear (left to right from that side)
    ob.location = center
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def apply_all(obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def bounds(obs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in obs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def colormap_pixels(mat):
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            img = n.image
            return img.size[0], img.size[1], list(img.pixels)
    return None


def hsv(c):
    r, g, b = c
    mx, mn = max(c), min(c)
    s = 0 if mx == 0 else (mx - mn) / mx
    if mx == mn:
        h = 0
    elif mx == r:
        h = ((g - b) / (mx - mn)) % 6
    elif mx == g:
        h = (b - r) / (mx - mn) + 2
    else:
        h = (r - g) / (mx - mn) + 4
    return h * 60, s, mx


def split_materials(body, paint_hex):
    """Windows -> Glass, the dominant body colour -> Paint, by sampling the palette texture."""
    me = body.data
    src = me.materials[0]
    px = colormap_pixels(src)
    if px is None:
        return None
    W, H, P = px
    uv = me.uv_layers.active.data
    glass = material("Glass", (0.35, 0.45, 0.55, 0.35), rough=0.05, alpha=0.35)
    paint = material("Paint", (0.8, 0.1, 0.1, 1.0), rough=0.3)
    me.materials.append(glass)
    me.materials.append(paint)
    cols = []
    area = {}
    for p in me.polygons:
        u = sum(uv[i].uv[0] for i in p.loop_indices) / p.loop_total
        v = sum(uv[i].uv[1] for i in p.loop_indices) / p.loop_total
        x = min(W - 1, max(0, int(u * W)))
        y = min(H - 1, max(0, int(v * H)))
        k = (y * W + x) * 4
        c = (P[k], P[k + 1], P[k + 2])
        cols.append(c)
        h, s, val = hsv(c)
        if not (s > 0.4 and val > 0.25):
            continue
        key = int(h // 20)
        area[key] = area.get(key, 0.0) + p.area
    # windows: the pale sky-blue palette cells (grey-blue = sills, lavender-white = white paint)
    for p, c in zip(me.polygons, cols):
        h, s, val = hsv(c)
        if 195 <= h <= 215 and 0.04 <= s <= 0.2 and val >= 0.9:
            p.material_index = 1
    dominant = max(area, key=area.get) if area else None
    base = None
    if dominant is not None and paint_hex != "keep":
        for p, c in zip(me.polygons, cols):
            if p.material_index != 0:
                continue
            h, s, val = hsv(c)
            if s > 0.4 and val > 0.25 and int(h // 20) == dominant:
                p.material_index = 2
                base = c
    if base is not None:
        paint.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = base + (1.0,)
    return [p.material_index == 1 for p in me.polygons]


def kenney(kind, src, length, livery, paint_hex):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(KIT, src + ".glb"))
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            continue
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.context.scene.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    apply_all(obs)
    # face +X, real size, wheels on z = 0, centred
    rot = Matrix.Rotation(math.pi / 2, 4, "Z")
    for o in obs:
        o.data.transform(rot)
    lo, hi = bounds(obs)
    s = length / (hi.x - lo.x)
    for o in obs:
        o.data.transform(Matrix.Scale(s, 4))
    lo, hi = bounds(obs)
    off = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    for o in obs:
        o.data.transform(Matrix.Translation(off))
    body = next(o for o in obs if o.name.startswith("body"))
    wheels = []
    for o in obs:
        n = o.name
        if n.startswith("wheel"):
            if n.startswith("wheel-back") and not ("left" in n or "right" in n):
                o.name = "spare"
                continue
            lo_w, hi_w = bounds([o])
            c = (lo_w + hi_w) / 2
            o.data.transform(Matrix.Translation(-c))
            o.location = c
            o.name = "wheel_%s%s" % ("f" if c.x > 0 else "r", "l" if c.y > 0 else "r")
            wheels.append(o)
        elif o is not body and o.name not in ("spare",):
            o.name = "trim_" + o.name
    body.name = "body"
    split_materials(body, "keep" if kind == "police" else paint_hex)
    lo, hi = bounds([body])
    L, Wd, Ht = hi.x - lo.x, hi.y - lo.y, hi.z - lo.z
    # side windows -> the cabin (front/back, floor to window top) for a simple interior
    side = []
    for p in body.data.polygons:
        if p.material_index == 1 and abs(p.normal.y) > 0.6:
            side.extend(body.matrix_world @ body.data.vertices[i].co for i in p.vertices)
    interior = material("Interior", srgb_lin("#2a2a2e"), rough=0.9)
    if len(side) > 3:
        x0 = max(min(v.x for v in side), lo.x + 0.15 * L) + 0.05
        x1 = min(max(v.x for v in side), hi.x - 0.15 * L) - 0.05
        z1 = max(v.z for v in side) - 0.04
        z0 = min(v.z for v in side) - 0.45
        y1 = max(abs(v.y) for v in side) - 0.1
        c = Vector(((x0 + x1) / 2, 0, (z0 + z1) / 2))
        sz = Vector((x1 - x0, y1 * 2, z1 - z0))
        liner = box("interior", c, tuple(sz), interior)
        for f in liner.data.polygons:
            f.flip()                                       # seen from inside, through the glass
        seat = material("Seat", srgb_lin("#4a3b30"), rough=0.8)
        sx = min(0.45, sz.x * 0.2)
        for sy in (1, -1):
            box("interior_seat_%d" % sy, (c.x + sz.x * 0.12, sy * sz.y * 0.22, z0 + 0.2), (sx, min(0.42, sz.y * 0.3), 0.4), seat)
        box("interior_bench", (c.x - sz.x * 0.25, 0, z0 + 0.2), (sx, sz.y * 0.8, 0.4), seat)
        box("interior_dash", (x1 - 0.12, 0, z0 + 0.42), (0.2, sz.y * 0.9, 0.18), interior)
        cylinder("interior_steer", (x1 - 0.3, sz.y * 0.22, z0 + 0.55), 0.15, 0.04, interior, axis="X", segs=12)
    # lights (the game switches them): head, tail/brake, indicators, plates
    head = material("LightHead", srgb_lin("#fff6d8"), emission=srgb_lin("#fff6d8"))
    tail = material("LightTail", srgb_lin("#a01010"), emission=srgb_lin("#ff2020"))
    ind = material("LightInd", srgb_lin("#c87810"), emission=srgb_lin("#ffa020"))
    plate = material("Plate", srgb_lin("#f2f2ee"), rough=0.5)
    zl = lo.z + Ht * 0.42
    lamps_h, lamps_t, ind_l, ind_r = [], [], [], []
    for sy in (1, -1):
        lamps_h.append(box("lh%d" % sy, (hi.x + 0.005, sy * Wd * 0.33, zl), (0.04, Wd * 0.18, 0.12), head))
        lamps_t.append(box("lt%d" % sy, (lo.x - 0.005, sy * Wd * 0.36, zl + 0.05), (0.04, Wd * 0.14, 0.12), tail))
        for x in (hi.x + 0.006, lo.x - 0.006):
            (ind_l if sy > 0 else ind_r).append(box("li", (x, sy * Wd * 0.46, zl - 0.06), (0.04, 0.08, 0.06), ind))
    join(lamps_h, "light_head")
    join(lamps_t, "light_tail")
    join(ind_l, "light_ind_l")
    join(ind_r, "light_ind_r")
    box("plate_front", (hi.x + 0.01, 0, lo.z + Ht * 0.22), (0.02, 0.5, 0.12), plate)
    box("plate_rear", (lo.x - 0.01, 0, lo.z + Ht * 0.3), (0.02, 0.5, 0.12), plate)
    # liveries
    if livery == "TAXI":
        ink = material("Decal", srgb_lin("#111111"))
        for sy in (1, -1):
            text("decal_taxi_%d" % sy, "TAXI", (0.2, sy * (hi.y + 0.004), lo.z + Ht * 0.5), 0.32, ink, sy)
            box("decal_check_%d" % sy, (0.2, sy * (hi.y + 0.002), lo.z + Ht * 0.36), (L * 0.75, 0.01, 0.06), ink)
    elif livery == "POLICE":
        ink = material("Decal", srgb_lin("#14306e"))
        for sy in (1, -1):
            text("decal_police_%d" % sy, "POLICE", (0.1, sy * (hi.y + 0.004), lo.z + Ht * 0.47), 0.26, ink, sy)
            box("decal_stripe_%d" % sy, (0.0, sy * (hi.y + 0.002), lo.z + Ht * 0.34), (L * 0.85, 0.01, 0.07), ink)
    elif livery == "ARMOURED":
        steel = material("Armour", srgb_lin("#5b6168"), rough=0.4)
        for sy in (1, -1):
            box("armour_side_%d" % sy, (-0.3, sy * (hi.y + 0.02), lo.z + Ht * 0.35), (L * 0.7, 0.03, Ht * 0.3), steel)
            for k in range(5):
                box("armour_bar_%d_%d" % (sy, k), (-0.9 + k * 0.4, sy * (hi.y + 0.03), lo.z + Ht * 0.72), (0.04, 0.03, Ht * 0.25), steel)
        ink = material("Decal", srgb_lin("#e8e2c8"))
        for sy in (1, -1):
            text("decal_cash_%d" % sy, "SECURE CASH", (-0.3, sy * (hi.y + 0.04), lo.z + Ht * 0.35), 0.22, ink, sy)
    if paint_hex and paint_hex != "keep":
        p = bpy.data.materials.get("Paint")
        if p is not None:
            p.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = srgb_lin(paint_hex)
    export(kind)


def join(obs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    bpy.context.object.name = name
    return bpy.context.object


def keke():
    """Tricycle taxi: one front wheel, two rear, open sides, a canopy on four posts."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    paint = material("Paint", srgb_lin("#f5c518"), rough=0.35)
    dark = material("colormap", srgb_lin("#26272c"), rough=0.7)
    metal = material("Metal", srgb_lin("#9aa0a8"), rough=0.35)
    canvas = material("Canopy", srgb_lin("#1d6e3a"), rough=0.8)
    seat = material("Seat", srgb_lin("#4a3b30"), rough=0.8)
    glass = material("Glass", (0.35, 0.45, 0.55, 0.35), rough=0.05, alpha=0.35)
    tyre = material("Tyre", srgb_lin("#1b1b1b"), rough=0.9)
    rim = material("Rim", srgb_lin("#c8c8c8"), rough=0.3)
    R = 0.27
    # wheels (separate, origin at the hub)
    for name, pos in (("wheel_f", (1.0, 0.0, R)), ("wheel_rl", (-0.6, 0.58, R)), ("wheel_rr", (-0.6, -0.58, R))):
        w = cylinder(name, (0, 0, 0), R, 0.16, tyre, axis="Y", segs=18)
        hub = cylinder(name + "_hub", (0, 0, 0), R * 0.55, 0.17, rim, axis="Y", segs=12)
        join([w, hub], name)
        bpy.context.object.location = pos
    parts = []
    parts.append(box("floor", (-0.15, 0, 0.42), (1.8, 1.15, 0.12), dark, 0.02))
    parts.append(box("tub_rear", (-0.62, 0, 0.62), (0.75, 1.2, 0.42), paint, 0.06))              # rear body over the axle
    parts.append(box("side_l", (0.05, 0.6, 0.58), (1.2, 0.05, 0.3), paint, 0.02))
    parts.append(box("side_r", (0.05, -0.6, 0.58), (1.2, 0.05, 0.3), paint, 0.02))
    parts.append(box("nose", (0.86, 0, 0.78), (0.34, 0.62, 0.62), paint, 0.1))                   # front cowl
    parts.append(box("fork", (1.0, 0, 0.52), (0.08, 0.16, 0.5), metal))
    parts.append(box("mudguard", (1.0, 0, 0.6), (0.44, 0.22, 0.05), paint, 0.02))
    parts.append(box("bench_driver", (0.45, 0, 0.72), (0.32, 0.4, 0.14), seat, 0.03))
    parts.append(box("bench_rear", (-0.55, 0, 0.92), (0.45, 1.05, 0.16), seat, 0.03))
    parts.append(box("backrest", (-0.82, 0, 1.2), (0.08, 1.05, 0.45), seat, 0.03))
    parts.append(box("handlebar", (0.7, 0, 1.12), (0.05, 0.58, 0.05), metal))
    parts.append(box("dash", (0.83, 0, 1.06), (0.12, 0.6, 0.12), dark, 0.02))
    for x, y in ((0.82, 0.55), (0.82, -0.55), (-0.9, 0.58), (-0.9, -0.58)):
        parts.append(box("post", (x, y, 1.35), (0.04, 0.04, 1.05), metal))
    parts.append(box("roof", (-0.04, 0, 1.9), (2.0, 1.32, 0.08), canvas, 0.03))
    parts.append(box("roof_lip", (0.92, 0, 1.84), (0.12, 1.32, 0.12), canvas, 0.02))
    parts.append(box("back_canvas", (-0.93, 0, 1.55), (0.03, 1.2, 0.6), canvas))
    parts.append(box("mirror_l", (0.85, 0.42, 1.25), (0.03, 0.12, 0.08), metal))
    parts.append(box("mirror_r", (0.85, -0.42, 1.25), (0.03, 0.12, 0.08), metal))
    body = join(parts, "body")
    box("windscreen", (0.86, 0, 1.4), (0.03, 1.0, 0.5), glass).name = "glass_front"
    head = material("LightHead", srgb_lin("#fff6d8"), emission=srgb_lin("#fff6d8"))
    tail = material("LightTail", srgb_lin("#a01010"), emission=srgb_lin("#ff2020"))
    ind = material("LightInd", srgb_lin("#c87810"), emission=srgb_lin("#ffa020"))
    cylinder("light_head", (1.04, 0, 0.92), 0.08, 0.04, head, axis="X", segs=12)
    lt = [box("lt", (-1.0, y, 0.7), (0.03, 0.12, 0.08), tail) for y in (0.45, -0.45)]
    join(lt, "light_tail")
    join([box("li", (1.03, 0.2, 0.82), (0.03, 0.06, 0.05), ind), box("li", (-1.0, 0.56, 0.7), (0.03, 0.06, 0.05), ind)], "light_ind_l")
    join([box("li", (1.03, -0.2, 0.82), (0.03, 0.06, 0.05), ind), box("li", (-1.0, -0.56, 0.7), (0.03, 0.06, 0.05), ind)], "light_ind_r")
    box("plate_rear", (-1.0, 0, 0.5), (0.02, 0.3, 0.1), material("Plate", srgb_lin("#f2f2ee")))
    export("keke")


def export(kind):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "veh_%s.glb" % kind)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_cameras=False, export_lights=False, export_animations=False)
    n = len([o for o in bpy.context.scene.objects if o.type == "MESH"])
    print("exported %-8s %3d objects  %.0f KB" % (kind, n, os.path.getsize(path) / 1024))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    kinds = argv or list(SPECS) + ["keke"]
    for k in kinds:
        if k == "keke":
            keke()
        else:
            kenney(k, *SPECS[k])


main()
