"""
Monrovia Life - 3D city builder for Blender (4.2+ / 5.x).

Builds a stylized 3D Monrovia from the game's map (blender/monrovia_map.json):
terrain and water, roads with markings, bridges on pillars, extruded buildings
with windows and rooftop water tanks, landmarks, market stalls, palm trees and
traffic (vehicles come from make_sprites.py). Saves blender/monrovia_city.blend
and renders two preview shots.

Run:  blender -b -P tools/build_city.py
      (add  -- --no-render  to skip the preview renders)
"""
import bpy
import bmesh
import json
import math
import os
import random
import sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUTDIR = os.path.join(ROOT, "blender")
sys.path.insert(0, HERE)
import make_sprites as ms  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
T = 4.0  # metres per map tile
rng = random.Random(1847)

with open(os.path.join(OUTDIR, "monrovia_map.json")) as f:
    D = json.load(f)
W, H, TILES, ROADS = D["W"], D["H"], D["tiles"], D["roads"]
OCEAN, RIVER, SAND, GRASS, ROAD, BLD, MANG, GROUND, BRIDGE, MARKET, LMK, TREE, TARMAC = range(13)

LANDMARKS = [
    ("Ducor Hotel", 17, 57, 4, 2), ("Centennial Pavilion", 32, 62, 3, 2), ("Waterside Market", 43, 51, 11, 2),
    ("Capitol Building", 64, 57, 5, 2), ("Executive Mansion", 65, 64, 5, 3), ("University of Liberia", 50, 62, 5, 3),
    ("Police HQ", 59, 63, 4, 2), ("Freeport of Monrovia", 17, 16, 14, 5), ("JFK Medical Center", 88, 60, 5, 3),
    ("Spriggs Payne Airfield", 103, 60, 24, 3), ("Ministerial Complex", 150, 66, 5, 3),
    ("SKD Sports Complex", 192, 75, 8, 6), ("Red Light Market", 230, 56, 9, 5),
]


def tile(x, y):
    if 0 <= x < W and 0 <= y < H:
        return TILES[y * W + x]
    return OCEAN


def P(x, y, z=0.0):
    """map tile coords -> Blender metres (north is +Y)"""
    return Vector((x * T, -y * T, z))


def h01(*a):
    return random.Random(hash(a)).random()


# ------------------------------------------------------------------ materials
def lin(hexs):
    return ms.srgb(hexs)


def mat(name, hexs, rough=0.8, metal=0.0, emit=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    c = lin(hexs)
    m.diffuse_color = c
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = c
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        key = "Emission Color" if "Emission Color" in b.inputs else "Emission"
        b.inputs[key].default_value = lin(emit)
        b.inputs["Emission Strength"].default_value = 2.0
    return m


def mat_noise(name, hex_a, hex_b, scale=0.05, rough=0.9):
    m = mat(name, hex_a, rough)
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = lin(hex_a)
    ramp.color_ramp.elements[1].color = lin(hex_b)
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def mat_walls(name, hexs):
    """painted concrete walls with a procedural grid of dark windows"""
    m = mat(name, hexs, 0.85)
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])

    def band(sock, period, lo, hi):
        div = nt.nodes.new("ShaderNodeMath"); div.operation = "DIVIDE"; div.inputs[1].default_value = period
        fr = nt.nodes.new("ShaderNodeMath"); fr.operation = "FRACT"
        g = nt.nodes.new("ShaderNodeMath"); g.operation = "GREATER_THAN"; g.inputs[1].default_value = lo
        l = nt.nodes.new("ShaderNodeMath"); l.operation = "LESS_THAN"; l.inputs[1].default_value = hi
        mu = nt.nodes.new("ShaderNodeMath"); mu.operation = "MULTIPLY"
        nt.links.new(sock, div.inputs[0]); nt.links.new(div.outputs[0], fr.inputs[0])
        nt.links.new(fr.outputs[0], g.inputs[0]); nt.links.new(fr.outputs[0], l.inputs[0])
        nt.links.new(g.outputs[0], mu.inputs[0]); nt.links.new(l.outputs[0], mu.inputs[1])
        return mu.outputs[0]

    add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"
    nt.links.new(sep.outputs[0], add.inputs[0]); nt.links.new(sep.outputs[1], add.inputs[1])
    zb = band(sep.outputs[2], 3.2, 0.38, 0.78)
    xb = band(add.outputs[0], 2.6, 0.25, 0.75)
    above = nt.nodes.new("ShaderNodeMath"); above.operation = "GREATER_THAN"; above.inputs[1].default_value = 1.2
    nt.links.new(sep.outputs[2], above.inputs[0])
    m1 = nt.nodes.new("ShaderNodeMath"); m1.operation = "MULTIPLY"
    m2 = nt.nodes.new("ShaderNodeMath"); m2.operation = "MULTIPLY"
    nt.links.new(zb, m1.inputs[0]); nt.links.new(xb, m1.inputs[1])
    nt.links.new(m1.outputs[0], m2.inputs[0]); nt.links.new(above.outputs[0], m2.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs[6].default_value = lin(hexs)
    mix.inputs[7].default_value = lin("#1c2733")
    nt.links.new(m2.outputs[0], mix.inputs[0])
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    return m


# ------------------------------------------------------------------ mesh helpers
def mesh_obj(name, bm, mats, coll=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def add_box(bm, cx, cy, z0, sx, sy, sz, side, top, ang=0.0):
    c, s = math.cos(ang), math.sin(ang)
    pts = [(-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2)]
    Q = [(cx + px * c - py * s, cy + px * s + py * c) for px, py in pts]
    vb = [bm.verts.new((x, y, z0)) for x, y in Q]
    vt = [bm.verts.new((x, y, z0 + sz)) for x, y in Q]
    bm.faces.new(vt).material_index = top
    bm.faces.new(list(reversed(vb))).material_index = side
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((vb[i], vb[j], vt[j], vt[i])).material_index = side


def add_cyl(bm, cx, cy, z0, r, h, mi, n=8, r2=None):
    r2 = r if r2 is None else r2
    vb = [bm.verts.new((cx + r * math.cos(a), cy + r * math.sin(a), z0)) for a in [i * math.tau / n for i in range(n)]]
    vt = [bm.verts.new((cx + r2 * math.cos(a), cy + r2 * math.sin(a), z0 + h)) for a in [i * math.tau / n for i in range(n)]]
    bm.faces.new(vt).material_index = mi
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((vb[i], vb[j], vt[j], vt[i])).material_index = mi


def add_matrix_cube(bm, M, mi):
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=M)
    faces = set()
    for v in res["verts"]:
        faces.update(v.link_faces)
    for f in faces:
        f.material_index = mi


def add_blob(bm, center, radius, mi, sub=1, squash=1.0):
    M = Matrix.Translation(center) @ Matrix.Diagonal((1, 1, squash, 1))
    res = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=radius, matrix=M)
    faces = set()
    for v in res["verts"]:
        faces.update(v.link_faces)
    for f in faces:
        f.material_index = mi
        f.smooth = True


# ------------------------------------------------------------------ build
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    return sc


def ground_z(t):
    return {OCEAN: -0.9, RIVER: -0.8, MANG: -0.8, BRIDGE: -0.8, SAND: 0.0, GRASS: 0.1, TREE: 0.1,
            GROUND: 0.12, MARKET: 0.12, ROAD: 0.12, BLD: 0.12, LMK: 0.12, TARMAC: 0.15}[t]


def build_terrain(coll):
    M = {
        "ocean": mat("Ocean", "#1d6e9e", 0.08), "river": mat("River", "#3c7f7a", 0.1),
        "sand": mat_noise("Sand", "#e5d1a0", "#d4bd86", 0.08), "grass": mat_noise("Grass", "#5d9842", "#4a7f34", 0.04),
        "laterite": mat_noise("Laterite", "#b9774f", "#a5653f", 0.06), "concrete": mat_noise("Concrete", "#aaa59a", "#9a958a", 0.1),
        "asphalt": mat("Asphalt", "#3f434a", 0.7), "tarmac": mat("Tarmac", "#5a5d63", 0.7),
    }
    order = ["ocean", "river", "sand", "grass", "laterite", "concrete", "asphalt", "tarmac"]
    idx = {k: i for i, k in enumerate(order)}

    def slot(t, x, y):
        if t == OCEAN: return idx["ocean"]
        if t in (RIVER, MANG, BRIDGE): return idx["river"]
        if t == SAND: return idx["sand"]
        if t in (GRASS, TREE): return idx["grass"]
        if t == TARMAC: return idx["tarmac"]
        if t == ROAD: return idx["asphalt"]
        if (t in (GROUND, BLD, LMK, MARKET)) and x < 62 and 50 < y < 72: return idx["concrete"]
        return idx["laterite"]

    def terrain_tile(x, y):
        # The Saint Paul River band (open water along the top rows, east of x=99) runs
        # into the map edge. Built as river-coloured tiles 0.1 m above the ocean, it showed
        # up as a stray green-blue strip with a hard edge at the north-east of the city.
        # Leave it to the ocean plane, like the open water west of it.
        t = tile(x, y)
        if t == RIVER and y < 16 and x >= 99 and 0 <= x < W and 0 <= y < H:
            return OCEAN
        return t

    bm = bmesh.new()
    for y in range(H):
        for x in range(W):
            t = terrain_tile(x, y)
            if t == OCEAN:
                continue  # the big ocean plane covers it
            z = ground_z(t)
            mi = slot(t, x, y)
            v = [bm.verts.new(P(x, y, z)), bm.verts.new(P(x + 1, y, z)), bm.verts.new(P(x + 1, y + 1, z)), bm.verts.new(P(x, y + 1, z))]
            bm.faces.new(list(reversed(v))).material_index = mi
            # banks / skirts down to lower neighbours
            for dx, dy, a, b in ((1, 0, (1, 0), (1, 1)), (-1, 0, (0, 1), (0, 0)), (0, 1, (1, 1), (0, 1)), (0, -1, (0, 0), (1, 0))):
                zn = ground_z(terrain_tile(x + dx, y + dy))
                if zn < z - 0.01:
                    p1 = P(x + a[0], y + a[1], z); p2 = P(x + b[0], y + b[1], z)
                    q = [bm.verts.new(p1), bm.verts.new(p2), bm.verts.new((p2.x, p2.y, zn)), bm.verts.new((p1.x, p1.y, zn))]
                    bm.faces.new(q).material_index = idx["sand"] if mi != idx["asphalt"] else idx["concrete"]
    mesh_obj("Terrain", bm, [M[k] for k in order], coll)
    # ocean plane
    bm = bmesh.new()
    pad = 600
    v = [bm.verts.new((-pad, pad, -0.9)), bm.verts.new((W * T + pad, pad, -0.9)),
         bm.verts.new((W * T + pad, -H * T - pad, -0.9)), bm.verts.new((-pad, -H * T - pad, -0.9))]
    bm.faces.new(list(reversed(v)))
    mesh_obj("Atlantic", bm, [M["ocean"]], coll)


def road_samples(r):
    pts = [Vector((p[0], p[1])) for p in r["p"]]
    out = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        n = max(1, int((b - a).length / 0.5))
        for k in range(n):
            out.append(a.lerp(b, k / n))
    out.append(pts[-1])
    return out


def build_roads(coll):
    asphalt = bpy.data.materials["Asphalt"]
    yellow = mat("LineYellow", "#f5c518", 0.6)
    white = mat("LineWhite", "#eeeeee", 0.6)
    conc = mat("BridgeConcrete", "#9a9ca1", 0.85)
    bm = bmesh.new()
    car_spots = []
    for ri, r in enumerate(ROADS):
        S = road_samples(r)
        raw = []
        for p in S:
            t = tile(int(p.x), int(p.y))
            raw.append(2.6 if t in (BRIDGE, OCEAN, RIVER, MANG) else 0.2 + ri * 0.004)
        Z = []
        for i in range(len(raw)):  # ramps onto bridges
            win = raw[max(0, i - 8): i + 9]
            Z.append(max(raw[i], sum(win) / len(win)) if max(win) > 1 else raw[i])
        half = r["w"] / 2 * T
        left, right = [], []
        for i, p in enumerate(S):
            a = S[max(0, i - 1)]; b = S[min(len(S) - 1, i + 1)]
            d = (b - a).normalized() if (b - a).length > 0 else Vector((1, 0))
            nrm = Vector((-d.y, d.x))
            base = P(p.x, p.y, Z[i])
            off = Vector((nrm.x * half, -nrm.y * half, 0))
            left.append(bm.verts.new(base + off)); right.append(bm.verts.new(base - off))
            if i < len(S) - 1:
                if r["w"] >= 2 and i % 6 == 0:
                    car_spots.append((ri, i, p.copy(), d.copy(), Z[i]))
                if Z[i] > 1.0:
                    for sgn in (1, -1):
                        q = base + Vector((nrm.x * (half + 0.15) * sgn, -nrm.y * (half + 0.15) * sgn, 0))
                        add_box(bm, q.x, q.y, Z[i], 0.3, 0.3, 1.0, 1, 1)
                    if i % 8 == 0:
                        add_cyl(bm, base.x, base.y, -4.0, 0.9, Z[i] + 4.0, 1, 10)
        for i in range(len(S) - 1):
            bm.faces.new((left[i], right[i], right[i + 1], left[i + 1])).material_index = 0
        # markings
        if r["w"] >= 2:
            acc = 0.0
            for i in range(len(S) - 1):
                a = P(S[i].x, S[i].y, Z[i] + 0.03); b = P(S[i + 1].x, S[i + 1].y, Z[i + 1] + 0.03)
                seg = b - a
                if seg.length == 0:
                    continue
                acc += seg.length
                solid = r["w"] >= 3
                if solid or (acc % 6.0) < 3.0:
                    mid = (a + b) / 2
                    add_box(bm, mid.x, mid.y, mid.z, seg.length + 0.05, 0.22, 0.02, 2 if solid else 3, 2 if solid else 3, math.atan2(seg.y, seg.x))
    mesh_obj("Roads", bm, [asphalt, conc, yellow, white], coll)
    return car_spots


def in_landmark(x, y):
    for _, lx, ly, lw, lh in LANDMARKS:
        if lx <= x < lx + lw and ly <= y < ly + lh:
            return True
    return False


def build_buildings(coll):
    palette = ["#e3d3ad", "#d9a5a5", "#9cc3d5", "#c6dcae", "#e8e2d0", "#d8c06a", "#b0b8bf", "#c27c5a", "#f0e6c8", "#a7c4a0"]
    walls = [mat_walls("Wall_%d" % i, h) for i, h in enumerate(palette)]
    roofs = [mat("RoofZinc", "#9aa3ad", 0.35, 0.6), mat("RoofRust", "#a0522d", 0.6, 0.3), mat("RoofConcrete", "#b8b4aa", 0.9)]
    tank = mat("WaterTank", "#1b1d22", 0.5)
    nw = len(walls)
    blocks = {}
    for y in range(H):
        for x in range(W):
            if tile(x, y) == BLD and not in_landmark(x, y):
                blocks.setdefault((x >> 2, y >> 2), []).append((x, y))
    bm = bmesh.new()
    for (bx, by), cells in blocks.items():
        r = random.Random(bx * 7919 + by * 104729)
        x0 = min(c[0] for c in cells); x1 = max(c[0] for c in cells) + 1
        y0 = min(c[1] for c in cells); y1 = max(c[1] for c in cells) + 1
        if x0 < 62 and y0 > 50:
            floors = r.choice([2, 3, 3, 4, 5, 6, 8])
        elif x0 < 95 and y0 < 41:
            floors = r.choice([1, 2, 2, 3, 4])
        elif x0 < 135:
            floors = r.choice([1, 2, 2, 3, 4, 5])
        else:
            floors = r.choice([1, 1, 2, 2, 3])
        h = floors * 3.2 + 0.4
        wi = r.randrange(nw)
        ri_ = nw + (r.randrange(2) if floors <= 2 else 2)
        rects = [(x0, y0, x1, y1)] if len(cells) >= 0.8 * (x1 - x0) * (y1 - y0) else [(c[0], c[1], c[0] + 1, c[1] + 1) for c in cells]
        for (a0, b0, a1, b1) in rects:
            c0 = P(a0, b0); c1 = P(a1, b1)
            add_box(bm, (c0.x + c1.x) / 2, (c0.y + c1.y) / 2, 0.12, abs(c1.x - c0.x) - 0.8, abs(c1.y - c0.y) - 0.8, h, wi, ri_)
        if floors >= 2 and r.random() < 0.45:
            c0 = P(x0, y0); c1 = P(x1, y1)
            add_cyl(bm, (c0.x + c1.x) / 2 + r.uniform(-2, 2), (c0.y + c1.y) / 2 + r.uniform(-2, 2), h + 0.12, 0.8, 1.6, nw + 3, 10)
    mesh_obj("Buildings", bm, walls + roofs + [tank], coll)


def build_landmarks(coll):
    m = {
        "cream": mat_walls("LM_Cream", "#d8cdb4"), "white": mat_walls("LM_White", "#f1efe8"), "brick": mat_walls("LM_Brick", "#b5654a"),
        "navy": mat_walls("LM_Navy", "#2b4a7a"), "grey": mat_walls("LM_Grey", "#a9b4bd"), "roof": mat("LM_Roof", "#c9c9c4", 0.8),
        "dome": mat("LM_Dome", "#dfe3e6", 0.3, 0.2), "red": mat("LM_Red", "#c8173a", 0.6), "teal": mat("LM_Teal", "#1aa39e", 0.6),
        "pitch": mat_noise("LM_Pitch", "#3f8f3a", "#367d31", 0.2), "stand": mat("LM_Stand", "#b4bac0", 0.8),
        "crane": mat("LM_Crane", "#f5c518", 0.5, 0.3), "yard": mat("LM_Yard", "#6d7882", 0.9),
    }
    keys = list(m.keys())
    K = {k: i for i, k in enumerate(keys)}
    cont = [mat("Cont_%d" % i, h, 0.6, 0.3) for i, h in enumerate(["#c8173a", "#1aa39e", "#2b5fb3", "#ef7d22", "#f5c518", "#5c7d3a"])]
    bm = bmesh.new()

    def rect(lx, ly, lw, lh, inset=0.6):
        a = P(lx, ly); b = P(lx + lw, ly + lh)
        return (a.x + b.x) / 2, (a.y + b.y) / 2, lw * T - inset * 2, lh * T - inset * 2

    for name, lx, ly, lw, lh in LANDMARKS:
        cx, cy, sx, sy = rect(lx, ly, lw, lh)
        if name == "Ducor Hotel":
            add_box(bm, cx, cy, 0.12, sx, sy, 9 * 3.2, K["cream"], K["roof"])
        elif name == "Centennial Pavilion":
            add_box(bm, cx, cy, 0.12, sx, sy, 0.6, K["roof"], K["roof"])
            for i in range(6):
                add_cyl(bm, cx - sx / 2 + 1 + i * (sx - 2) / 5, cy - sy / 2 + 0.6, 0.7, 0.35, 5, K["white"], 10)
            add_box(bm, cx, cy, 5.7, sx, sy, 1.2, K["white"], K["roof"])
        elif name == "Capitol Building":
            add_box(bm, cx, cy, 0.12, sx, sy, 3 * 3.2, K["white"], K["roof"])
            add_blob(bm, Vector((cx, cy, 9.7)), 3.4, K["dome"], 2, 0.8)
        elif name == "Executive Mansion":
            add_box(bm, cx, cy, 0.12, sx, sy, 4 * 3.2, K["white"], K["roof"])
            add_box(bm, cx, cy, 0.12, sx + 6, sy + 6, 1.5, K["teal"], K["teal"])
        elif name == "University of Liberia":
            add_box(bm, cx, cy, 0.12, sx, sy, 3 * 3.2, K["brick"], K["roof"])
        elif name == "Police HQ":
            add_box(bm, cx, cy, 0.12, sx, sy, 3 * 3.2, K["navy"], K["roof"])
        elif name == "Ministerial Complex":
            add_box(bm, cx, cy, 0.12, sx, sy, 6 * 3.2, K["grey"], K["roof"])
        elif name == "JFK Medical Center":
            add_box(bm, cx, cy, 0.12, sx, sy, 5 * 3.2, K["white"], K["roof"])
            add_box(bm, cx, cy, 16.2, 6, 1.6, 0.1, K["red"], K["red"])
            add_box(bm, cx, cy, 16.2, 1.6, 6, 0.1, K["red"], K["red"])
        elif name == "Freeport of Monrovia":
            add_box(bm, cx, cy, 0.12, sx, sy, 0.3, K["yard"], K["yard"])
            r = random.Random(5)
            for gx in range(10):
                for gy in range(3):
                    for lvl in range(r.randint(1, 3)):
                        add_box(bm, cx - sx / 2 + 4 + gx * 5.2, cy - sy / 2 + 4 + gy * 4, 0.42 + lvl * 2.6, 4.8, 2.4, 2.5, len(keys) + r.randrange(6), len(keys) + r.randrange(6))
            for k in range(2):
                bx = cx + sx / 2 - 6 - k * 14
                add_box(bm, bx, cy - sy / 2 - 3, 0.12, 1.2, 1.2, 24, K["crane"], K["crane"])
                add_box(bm, bx, cy - sy / 2 + 6, 24, 1.2, 26, 1.2, K["crane"], K["crane"])
        elif name == "SKD Sports Complex":
            add_box(bm, cx, cy, 0.12, sx - 10, sy - 10, 0.1, K["pitch"], K["pitch"])
            n = 28
            for i in range(n):
                a = i * math.tau / n
                px = cx + math.cos(a) * (sx / 2 - 3); py = cy + math.sin(a) * (sy / 2 - 3)
                add_box(bm, px, py, 0.12, 5.2, 3.5, 7, K["stand"], K["stand"], a + math.pi / 2)
    mesh_obj("Landmarks", bm, [m[k] for k in keys] + cont, coll)

    # market stalls on market tiles
    stall_cols = [mat("Stall_%d" % i, h, 0.8) for i, h in enumerate(["#c8173a", "#1aa39e", "#f5c518", "#2b5fb3", "#ef7d22", "#7c3aed"])]
    wood = mat("Wood", "#7a4e30", 0.9)
    bm = bmesh.new()
    for y in range(H):
        for x in range(W):
            if tile(x, y) == MARKET:
                c = P(x + 0.5, y + 0.5)
                r = random.Random(x * 31 + y)
                add_box(bm, c.x, c.y, 0.12, 2.6, 1.6, 0.9, 0, 0)
                M = Matrix.Translation((c.x, c.y, 2.5)) @ Matrix.Rotation(0.12, 4, "X") @ Matrix.Diagonal((3.4, 3.2, 0.12, 1))
                add_matrix_cube(bm, M, 1 + r.randrange(6))
                for sx_, sy_ in ((-1.5, -1.4), (1.5, -1.4), (-1.5, 1.4), (1.5, 1.4)):
                    add_cyl(bm, c.x + sx_, c.y + sy_, 0.12, 0.08, 2.4, 0, 6)
    mesh_obj("MarketStalls", bm, [wood] + stall_cols, coll)


def build_trees(coll):
    trunk = mat("Trunk", "#6b4a2b", 0.9)
    leaf = mat("PalmLeaf", "#2f7a2f", 0.7)
    leaf2 = mat("TreeLeaf", "#2e6f2c", 0.8)
    mang = mat("Mangrove", "#2d5e37", 0.8)
    bm = bmesh.new()
    for y in range(H):
        for x in range(W):
            t = tile(x, y)
            r = random.Random(x * 1000 + y)
            if t == TREE:
                c = P(x + 0.3 + r.random() * 0.4, y + 0.3 + r.random() * 0.4)
                if r.random() < 0.55:  # palm
                    hgt = r.uniform(6, 9)
                    lean = r.uniform(-0.6, 0.6)
                    add_cyl(bm, c.x, c.y, 0.1, 0.25, hgt, 0, 6, 0.18)
                    top = Vector((c.x, c.y, hgt))
                    for k in range(7):
                        a = k * math.tau / 7 + r.random()
                        M = (Matrix.Translation(top) @ Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(0.35, 4, "Y")
                             @ Matrix.Translation((1.7, 0, 0)) @ Matrix.Diagonal((3.4, 0.7, 0.12, 1)))
                        add_matrix_cube(bm, M, 1)
                else:
                    hgt = r.uniform(2, 3)
                    add_cyl(bm, c.x, c.y, 0.1, 0.3, hgt, 0, 6)
                    add_blob(bm, Vector((c.x, c.y, hgt + 1.6)), r.uniform(2.0, 2.8), 2, 1, 0.85)
            elif t == MANG and r.random() < 0.55:
                c = P(x + r.random(), y + r.random())
                add_blob(bm, Vector((c.x, c.y, 0.2)), r.uniform(1.4, 2.4), 3, 1, 0.6)
    mesh_obj("Trees", bm, [trunk, leaf, leaf2, mang], coll)


def build_traffic(coll, spots):
    rng.shuffle(spots)
    weights = [("taxi", 30), ("keke", 25), ("car", 18), ("suv", 10), ("truck", 8), ("police", 5), ("van", 2), ("sport", 2)]
    pool = [k for k, w in weights for _ in range(w)]
    colors = [ms.srgb(h) for h in ["#ffffff", "#c0c6cc", "#2b2b2b", "#c8173a", "#2b5fb3", "#3a6b3a"]]
    count = 0
    for ri, i, p, d, z in spots:
        if count >= 70:
            break
        r = ROADS[ri]
        kind = rng.choice(pool)
        before = set(bpy.data.objects)
        if kind == "car":
            ms.sedan(rng.choice(colors))
        else:
            ms.VEHICLES[kind]()
        new = [o for o in bpy.data.objects if o not in before]
        dirn = 1 if rng.random() < 0.5 else -1
        dd = Vector((d.x * dirn, d.y * dirn))
        nrm = Vector((-dd.y, dd.x))
        lane = r["w"] * 0.26
        pos = P(p.x + nrm.x * lane, p.y + nrm.y * lane, z)
        empty = bpy.data.objects.new("Vehicle_%s_%d" % (kind, count), None)
        coll.objects.link(empty)
        for o in new:
            for c in o.users_collection:
                c.objects.unlink(o)
            coll.objects.link(o)
            o.parent = empty
        empty.location = pos
        empty.rotation_euler = (0, 0, math.atan2(-dd.y, dd.x))
        count += 1
    print("placed", count, "vehicles")


def build_labels(coll):
    white = mat("Label", "#ffffff", 0.5, emit="#ffffff")
    for name, lx, ly, lw, lh in LANDMARKS:
        cu = bpy.data.curves.new("lbl_" + name, "FONT")
        cu.body = name
        cu.size = 5.0
        cu.align_x = "CENTER"
        cu.extrude = 0.15
        ob = bpy.data.objects.new("Label " + name, cu)
        ob.data.materials.append(white)
        c = P(lx + lw / 2, ly + lh / 2)
        ob.location = (c.x, c.y - lh * T / 2 - 2, 36 if name == "Ducor Hotel" else 22)
        ob.rotation_euler = (math.radians(70), 0, 0)
        coll.objects.link(ob)


def setup_world_and_cameras(sc):
    world = bpy.data.worlds.new("Sky")
    sc.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = ms.srgb("#a9cfe8")
    bg.inputs["Strength"].default_value = 0.9
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.0
    sun.angle = math.radians(3)
    sun.color = (1.0, 0.95, 0.85)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(42), math.radians(8), math.radians(-35))
    sc.collection.objects.link(so)
    cams = {}
    for name, loc, look, lens in [
        ("Cam_Overview", P(110, 160, 520), P(118, 52, 0), 30),
        ("Cam_Downtown", P(28, 92, 95), P(44, 57, 0), 32),
        ("Cam_Sinkor", P(95, 100, 70), P(100, 66, 0), 35),
    ]:
        cd = bpy.data.cameras.new(name)
        cd.lens = lens
        cd.clip_end = 8000
        co = bpy.data.objects.new(name, cd)
        co.location = loc
        direction = look - loc
        co.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(co)
        cams[name] = co
    sc.camera = cams["Cam_Downtown"]
    return cams


def main():
    sc = reset()
    colls = {}
    for n in ["Terrain", "Roads", "Buildings", "Landmarks", "Nature", "Traffic", "Labels"]:
        c = bpy.data.collections.new(n)
        sc.collection.children.link(c)
        colls[n] = c
    build_terrain(colls["Terrain"]); print("terrain done")
    spots = build_roads(colls["Roads"]); print("roads done")
    build_buildings(colls["Buildings"]); print("buildings done")
    build_landmarks(colls["Landmarks"]); print("landmarks done")
    build_trees(colls["Nature"]); print("trees done")
    build_traffic(colls["Traffic"], spots)
    build_labels(colls["Labels"])
    cams = setup_world_and_cameras(sc)
    os.makedirs(OUTDIR, exist_ok=True)
    blend = os.path.join(OUTDIR, "monrovia_city.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("saved", blend)
    if "--no-render" in ARGS:
        return
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 900
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.eevee.taa_render_samples = 32
    except Exception:
        pass
    for name in ["Cam_Overview", "Cam_Downtown", "Cam_Sinkor"]:
        sc.camera = cams[name]
        sc.render.filepath = os.path.join(OUTDIR, "render_%s.png" % name.split("_")[1].lower())
        bpy.ops.render.render(write_still=True)
        print("rendered", name)
    sc.camera = cams["Cam_Downtown"]
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("ALL DONE")


main()
