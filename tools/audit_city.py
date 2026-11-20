"""
Monrovia Life: Streets - city tile audit.

Reads the generated tiles (proto3d/city/hi/*.glb and meta/*.json), not the OSM data, and
reports what a player would see as mistakes:

  1. buildings that touch or overlap a road: building footprints (the bottom edges of the
     "Wall" quads, grouped into one ring per building) against the "Road" triangles
     (carriageway strips and junction pads), sampled on a 0.25 m grid
  2. floating or sunk props: every street prop, lamp post, street-sign post, tree, bush and
     grass spot in the tile meta, against the walkable surface under it (the highest
     terrain, road or sidewalk triangle at that point)
  3. props standing inside a building footprint

Run:   "<Blender>\\python\\bin\\python.exe" -I tools\\audit_city.py [--json out.json] [--strict]
         [--city <folder>] [--old-signs]
--strict exits with code 1 if anything is found (used after a rebuild). --city audits a copy
of proto3d/city; --old-signs reads tiles from before the polish pass, whose sign posts the
game moved 5 m along x and z.
"""
import json
import math
import os
import struct
import sys
from collections import defaultdict

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CITY = os.path.join(ROOT, "proto3d", "city")
SAMPLE = 0.25           # m, footprint / road overlap sampling
MIN_OVERLAP = 0.25      # m2 of building on tarmac before it counts (one or two samples is noise)
FLOAT_TOL = 0.06        # m above the surface before a prop counts as floating
SINK_TOL = {"prop": 0.06, "pole": 0.06, "sign": 0.06, "tree": 0.12, "grass": 0.12}
SIGN_OFFSET = 0.0       # tiles before the polish pass: 5.0 (the game added 5 m to x and z)


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _ver, _len = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, path
    jl, _ = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jl])
    bl, _ = struct.unpack_from("<II", data, 20 + jl)
    binb = data[28 + jl:28 + jl + bl]

    def acc(i):
        a = js["accessors"][i]
        v = js["bufferViews"][a["bufferView"]]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a["componentType"]]
        n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        arr = np.frombuffer(binb, dt, a["count"] * n, v.get("byteOffset", 0) + a.get("byteOffset", 0))
        return arr.reshape(-1, n) if n > 1 else arr

    out = {}
    for node in js["nodes"]:
        mesh = js["meshes"][node["mesh"]]
        parts = {}
        for p in mesh["primitives"]:
            mat = js["materials"][p["material"]]["name"]
            pos = acc(p["attributes"]["POSITION"])
            idx = acc(p["indices"]).astype(np.int64)
            parts[mat] = pos[idx.reshape(-1, 3)]          # (ntri, 3, 3) in game space
        out[node["name"]] = parts
    return out


class Surface:
    """Walkable surface heights (terrain, roads, sidewalks) with a 4 m bin grid."""

    def __init__(self):
        self.tris = []
        self.bins = defaultdict(list)

    def add(self, tris, min_up=0.5):
        """min_up: smallest upward share of a face's normal that counts (roads and
        sidewalks: floor-like faces, not curb sides; terrain: any slope, it's a heightfield)."""
        if tris is None or len(tris) == 0:
            return
        e1 = tris[:, 1] - tris[:, 0]
        e2 = tris[:, 2] - tris[:, 0]
        n = np.cross(e1, e2)
        ln = np.linalg.norm(n, axis=1)
        keep = (ln > 1e-9) & (np.abs(n[:, 1]) / np.maximum(ln, 1e-9) > min_up)
        for t in tris[keep]:
            k = len(self.tris)
            self.tris.append(t)
            x0, x1 = t[:, 0].min(), t[:, 0].max()
            z0, z1 = t[:, 2].min(), t[:, 2].max()
            for bx in range(int(math.floor(x0 / 4)), int(math.floor(x1 / 4)) + 1):
                for bz in range(int(math.floor(z0 / 4)), int(math.floor(z1 / 4)) + 1):
                    self.bins[(bx, bz)].append(k)

    def heights(self, x, z):
        hs = []
        for k in self.bins.get((int(math.floor(x / 4)), int(math.floor(z / 4))), ()):
            t = self.tris[k]
            (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
            d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
            if abs(d) < 1e-12:
                continue
            l1 = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / d
            l2 = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / d
            l3 = 1 - l1 - l2
            if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6:
                hs.append(float(l1 * ay + l2 * by + l3 * cy))
        return hs


def wall_rings(walls):
    """Group the wall quads into buildings: each quad's bottom edge (2 lowest corners),
    joined where they share a corner. Returns a list of edge lists [(a, b), ...] in x/z."""
    if walls is None or len(walls) == 0:
        return []
    edges = []
    for q in range(0, len(walls) - 1, 2):
        pts = np.concatenate([walls[q], walls[q + 1]])
        uniq = {}
        for p in pts:
            uniq[(round(float(p[0]), 3), round(float(p[1]), 3), round(float(p[2]), 3))] = p
        corners = sorted(uniq.keys(), key=lambda c: c[1])
        if len(corners) < 4:
            continue
        lo = sorted(corners[:2])
        edges.append(((lo[0][0], lo[0][2]), (lo[1][0], lo[1][2])))
    parent = {}

    def find(a):
        while parent.setdefault(a, a) != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for a, b in edges:
        parent[find(a)] = find(b)
    groups = defaultdict(list)
    for a, b in edges:
        groups[find(a)].append((a, b))
    return list(groups.values())


def points_in_edges(xs, zs, edges):
    """Even-odd point-in-polygon for a building given as unordered edges."""
    ins = np.zeros(xs.shape, bool)
    for (ax, az), (bx, bz) in edges:
        if az == bz:
            continue
        cond = (az > zs) != (bz > zs)
        xi = (bx - ax) * (zs - az) / (bz - az) + ax
        ins ^= cond & (xs < xi)
    return ins


def points_in_tris(xs, zs, tris):
    hit = np.zeros(xs.shape, bool)
    for t in tris:
        (ax, _, az), (bx, _, bz), (cx, _, cz) = t
        d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
        if abs(d) < 1e-12:
            continue
        l1 = ((bz - cz) * (xs - cx) + (cx - bx) * (zs - cz)) / d
        l2 = ((cz - az) * (xs - cx) + (ax - cx) * (zs - cz)) / d
        hit |= (l1 >= 0) & (l2 >= 0) & (1 - l1 - l2 >= 0)
    return hit


def main():
    args = sys.argv[1:]
    out_json = args[args.index("--json") + 1] if "--json" in args else None
    strict = "--strict" in args
    city = args[args.index("--city") + 1] if "--city" in args else CITY
    sign_offset = 5.0 if "--old-signs" in args else SIGN_OFFSET
    hi_dir = os.path.join(city, "hi")
    meta_dir = os.path.join(city, "meta")
    tiles = sorted(f[:-4] for f in os.listdir(hi_dir) if f.endswith(".glb"))
    surf = Surface()
    roads = []           # all Road triangles
    walks = []           # sidewalk tops (floor-like Sidewalk triangles)
    buildings = []
    metas = {}
    for tag in tiles:
        g = read_glb(os.path.join(hi_dir, tag + ".glb"))
        for node in ("Terrain-col", "Roads-col", "Sidewalks-col"):
            for mat, tris in g.get(node, {}).items():
                if mat in ("Rail",):
                    continue
                surf.add(tris, 0.02 if node == "Terrain-col" else 0.5)
        r = g.get("Roads-col", {}).get("Road")
        if r is not None:
            roads.append(r)
        s = g.get("Sidewalks-col", {}).get("Sidewalk")
        if s is not None and len(s):
            n = np.cross(s[:, 1] - s[:, 0], s[:, 2] - s[:, 0])
            up = np.abs(n[:, 1]) > 0.9 * np.maximum(np.linalg.norm(n, axis=1), 1e-9)
            walks.append(s[up])
        buildings += wall_rings(g.get("Buildings-col", {}).get("Wall"))
        mp = os.path.join(meta_dir, tag + ".json")
        if os.path.exists(mp):
            with open(mp) as f:
                metas[tag] = json.load(f)
    roads = np.concatenate(roads) if roads else np.zeros((0, 3, 3))
    walks = np.concatenate(walks) if walks else np.zeros((0, 3, 3))

    def bin_tris(tris):
        out = defaultdict(list)
        for k, t in enumerate(tris):
            for bx in range(int(math.floor(t[:, 0].min() / 8)), int(math.floor(t[:, 0].max() / 8)) + 1):
                for bz in range(int(math.floor(t[:, 2].min() / 8)), int(math.floor(t[:, 2].max() / 8)) + 1):
                    out[(bx, bz)].append(k)
        return out
    # triangle bins (8 m) for the overlap tests
    rbins = bin_tris(roads)
    wbins = bin_tris(walks)
    # building masks per 8 m bin, for "prop inside a building"
    bbins = defaultdict(list)
    report = {"buildings": len(buildings), "overlaps": [], "on_sidewalk": [], "props": defaultdict(lambda: {"total": 0, "floating": [], "sunk": [], "in_building": [], "no_surface": []})}
    for bi, edges in enumerate(buildings):
        xs_all = [p[0] for e in edges for p in e]
        zs_all = [p[1] for e in edges for p in e]
        x0, x1, z0, z1 = min(xs_all), max(xs_all), min(zs_all), max(zs_all)
        for bx in range(int(math.floor(x0 / 8)), int(math.floor(x1 / 8)) + 1):
            for bz in range(int(math.floor(z0 / 8)), int(math.floor(z1 / 8)) + 1):
                bbins[(bx, bz)].append(bi)
        cand = set()
        wcand = set()
        for bx in range(int(math.floor(x0 / 8)), int(math.floor(x1 / 8)) + 1):
            for bz in range(int(math.floor(z0 / 8)), int(math.floor(z1 / 8)) + 1):
                cand.update(rbins.get((bx, bz), ()))
                wcand.update(wbins.get((bx, bz), ()))
        if not cand and not wcand:
            continue
        gx = np.arange(x0 + SAMPLE / 2, x1, SAMPLE)
        gz = np.arange(z0 + SAMPLE / 2, z1, SAMPLE)
        if len(gx) == 0 or len(gz) == 0:
            continue
        X, Z = np.meshgrid(gx, gz)
        inside = points_in_edges(X, Z, edges)
        if not inside.any():
            continue
        xs, zs = X[inside], Z[inside]
        if wcand:
            # kerb clearance: the building standing on a sidewalk (no walkable strip there)
            won = points_in_tris(xs, zs, walks[sorted(wcand)])
            warea = float(won.sum()) * SAMPLE * SAMPLE
            if warea >= MIN_OVERLAP:
                report["on_sidewalk"].append({"centre": [round((x0 + x1) / 2, 1), round((z0 + z1) / 2, 1)], "on_sidewalk_m2": round(warea, 1)})
        if not cand:
            continue
        on = points_in_tris(xs, zs, roads[sorted(cand)])
        area = float(on.sum()) * SAMPLE * SAMPLE
        if area >= MIN_OVERLAP:
            report["overlaps"].append({"centre": [round((x0 + x1) / 2, 1), round((z0 + z1) / 2, 1)],
                                       "footprint_m2": round(float(inside.sum()) * SAMPLE * SAMPLE, 1),
                                       "on_road_m2": round(area, 1)})

    def in_building(x, z):
        for bi in bbins.get((int(math.floor(x / 8)), int(math.floor(z / 8))), ()):
            if points_in_edges(np.array([x]), np.array([z]), buildings[bi])[0]:
                return True
        return False

    def check(kind, label, x, y, z):
        rec = report["props"][label]
        rec["total"] += 1
        hs = [h for h in surf.heights(x, z) if h < y + 2.5]      # ignore bridge decks overhead
        where = [round(x, 2), round(y, 2), round(z, 2)]
        if in_building(x, z):
            rec["in_building"].append(where)
            return
        if not hs:
            rec["no_surface"].append(where)
            return
        top = max(hs)
        d = y - top
        if d > FLOAT_TOL:
            rec["floating"].append(where + [round(d, 2)])
        elif d < -SINK_TOL[kind]:
            rec["sunk"].append(where + [round(d, 2)])

    for tag, mt in metas.items():
        for p in mt.get("props", []):
            check("prop", "prop:" + p[3], p[0], p[1], p[2])
        for p in mt.get("poles", []):
            check("pole", "lamp post", p[0], p[1], p[2])
        for s in mt.get("signs", []):
            off = sign_offset
            check("sign", "street sign", s[0] + off, s[1], s[2] + off)
        for t in mt.get("trees", []):
            check("tree", ["palm", "tree", "bush"][int(t[3])], t[0], t[1], t[2])
        for g_ in mt.get("grass", []):
            check("grass", "grass", g_[0], g_[1], g_[2])

    # ---- print
    print("tiles: %d, buildings: %d, road triangles: %d" % (len(tiles), len(buildings), len(roads)))
    ov = sorted(report["overlaps"], key=lambda o: -o["on_road_m2"])
    print("buildings touching/overlapping a road: %d" % len(ov))
    for o in ov[:15]:
        print("   at x=%.1f z=%.1f  footprint %.0f m2, %.1f m2 on tarmac" % (o["centre"][0], o["centre"][1], o["footprint_m2"], o["on_road_m2"]))
    bad = len(ov)
    sw = report["on_sidewalk"]
    print("buildings standing on a sidewalk (no walkable strip there): %d, %.0f m2" % (len(sw), sum(o["on_sidewalk_m2"] for o in sw)))
    path_m = 0.0
    kerb = 0
    for mt in metas.values():
        for path in mt.get("paths", []):
            for a, b in zip(path, path[1:]):
                path_m += math.hypot(b[0] - a[0], b[2] - a[2])
        kerb += len(mt.get("props", [])) + len(mt.get("poles", []))
    print("sidewalk paths for pedestrians: %.1f km; kerbside props and lamp posts: %d" % (path_m / 1000.0, kerb))
    print("props (floating > %.2f m, sunk, inside a building, nothing under them):" % FLOAT_TOL)
    for label in sorted(report["props"]):
        r = report["props"][label]
        n = len(r["floating"]) + len(r["sunk"]) + len(r["in_building"]) + len(r["no_surface"])
        bad += n
        print("   %-12s %6d  floating %4d  sunk %4d  in building %4d  no surface %4d" % (
            label, r["total"], len(r["floating"]), len(r["sunk"]), len(r["in_building"]), len(r["no_surface"])))
        for k in ("floating", "sunk", "in_building"):
            for w in r[k][:3]:
                print("      %s %s" % (k, w))
    if out_json:
        with open(out_json, "w", encoding="utf-8", newline="\n") as f:
            json.dump({"buildings": report["buildings"], "overlaps": ov, "on_sidewalk": sw, "path_km": round(path_m / 1000.0, 2), "kerb_props": kerb,
                       "props": {k: v for k, v in report["props"].items()}}, f, indent=1)
    print("AUDIT %s: %d issues" % ("CLEAN" if bad == 0 else "FOUND", bad))
    if strict and bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
