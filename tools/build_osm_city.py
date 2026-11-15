"""
Monrovia Life - builds the 1:1 central Monrovia world from real map data.

Input  (tools/fetch_map_data.py):  data/osm/monrovia_central.json, data/dem/*.png, data/bbox.json
Output (proto3d/city/):
    manifest.json          tile list, origin, spawn, landmarks, credits
    hi/t_<i>_<j>.glb       detailed 256 m tile with collision (nodes named "*-col")
    lo/t_<i>_<j>.glb       low-detail tile (coarse terrain, roads, buildings; no collision)
    meta/t_<i>_<j>.json    street signs, sidewalk paths (pedestrians), parking spots

What it builds:
    UTM 29N projection (metres); terrain from the SRTM-derived DEM (smoothed); the Atlantic
    by flood-filling from the OSM coastline; Mesurado River / lagoons from OSM water areas;
    land cover colours (beach, grass, parks, wetland, built-up laterite, downtown paving);
    roads with real widths by highway type, draped on the terrain, with centre lines;
    bridges lifted over water; raised sidewalks along the main roads; every building
    footprint extruded by building:levels (or a size-based default, taller downtown) with
    painted walls and zinc / concrete roofs; street lights and palms.

Map data (c) OpenStreetMap contributors, ODbL 1.0 - the generated tiles are a derived
database and fall under the ODbL share-alike terms.

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\5.3\\python\\bin\\python.exe" -I tools\\build_osm_city.py
(needs only Python 3 + numpy; Blender's bundled Python has both)
"""
import json
import math
import os
import struct
import sys
import time
import zlib
from collections import defaultdict

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "proto3d", "city")
TILE = 256.0
GRID = 8.0              # raster cell (m) for water / land cover / heights
HI_STEP = 8.0           # terrain vertex spacing in detailed tiles
LO_STEP = 32.0          # terrain vertex spacing in low-detail tiles
SEA = -1.0              # sea-bed height (the water plane is at 0)
# Area to build (south, west, north, east). The downloaded data (data/bbox.json) may be larger;
# widen this to add Congo Town and beyond later (and re-run tools/fetch_map_data.py if needed).
BUILD_BBOX = (6.280, -10.815, 6.325, -10.765)     # Mamba Point to Sinkor
SPAWN_LATLON = (6.3070, -10.8003)   # local origin (Capitol Hill side of downtown)
DOWNTOWN = (-1350.0, 950.0, -250.0, 1650.0)   # x0, x1, y0, y1 (m): Broad Street / Ashmun / Randall core
SPAWN_NEAR = (-300.0, 950.0)                 # spawn on Broad Street nearest this (by Centennial Pavilion)

ROAD_W = {"motorway": 16, "trunk": 14, "primary": 12, "secondary": 10, "tertiary": 8.5,
          "trunk_link": 7, "primary_link": 7, "secondary_link": 7, "tertiary_link": 6,
          "residential": 6.5, "unclassified": 6.5, "living_street": 5, "service": 4.5,
          "pedestrian": 5, "track": 3.5, "road": 6}
ROAD_RANK = {"motorway": 9, "trunk": 8, "primary": 7, "secondary": 6, "tertiary": 5, "trunk_link": 4,
             "primary_link": 4, "secondary_link": 4, "tertiary_link": 4, "unclassified": 3,
             "residential": 3, "living_street": 2, "pedestrian": 2, "road": 2, "service": 1, "track": 0}
MAJOR = {"motorway", "trunk", "primary", "secondary", "tertiary"}
WALLS = [(0.89, 0.83, 0.68), (0.85, 0.65, 0.65), (0.61, 0.76, 0.84), (0.78, 0.86, 0.68), (0.91, 0.89, 0.82),
         (0.85, 0.75, 0.42), (0.69, 0.72, 0.75), (0.76, 0.49, 0.35), (0.94, 0.9, 0.78), (0.65, 0.77, 0.63),
         (0.95, 0.95, 0.93), (0.98, 0.85, 0.55)]
COL = {
    "sand": (0.86, 0.79, 0.6), "grass": (0.36, 0.55, 0.26), "park": (0.31, 0.52, 0.22),
    "forest": (0.2, 0.38, 0.17), "wetland": (0.24, 0.36, 0.22), "laterite": (0.6, 0.45, 0.35),
    "paving": (0.62, 0.6, 0.56), "seabed": (0.55, 0.5, 0.36), "asphalt": (0.42, 0.43, 0.45),
    "dirt": (0.6, 0.42, 0.29), "sidewalk": (0.66, 0.64, 0.6), "curb": (0.82, 0.8, 0.75),
    "paint": (0.95, 0.95, 0.93), "yellow": (0.96, 0.76, 0.1), "zinc": (0.6, 0.63, 0.66),
    "rust": (0.55, 0.3, 0.17), "roofcon": (0.7, 0.69, 0.66), "lamp": (0.35, 0.37, 0.4),
    "trunk_wood": (0.45, 0.34, 0.22), "leaf": (0.24, 0.5, 0.18), "rail": (0.55, 0.56, 0.58),
}
LANDMARKS = ["Executive Mansion", "Capitol Building", "Centennial Pavilion", "Temple of Justice",
             "Ducor Intercontinental Hotel", "University of Liberia", "James Spriggs Payne Airport",
             "Antoinette Tubman Stadium", "Waterside Market", "John F. Kennedy",
             "National Police Headquarters", "Providence Baptist Church",
             "Providence Island", "E. J. Roye", "Masonic Temple", "Ministry of Foreign Affairs",
             "Trinity Cathedral", "Tubman High School"]


# ------------------------------------------------------------------ projection (UTM 29N)
A_ = 6378137.0
F_ = 1 / 298.257223563
K0 = 0.9996
LON0 = math.radians(-9.0)
E2 = F_ * (2 - F_)
EP2 = E2 / (1 - E2)


def utm(lat, lon):
    phi, lam = math.radians(lat), math.radians(lon)
    n = A_ / math.sqrt(1 - E2 * math.sin(phi) ** 2)
    t = math.tan(phi) ** 2
    c = EP2 * math.cos(phi) ** 2
    a = math.cos(phi) * (lam - LON0)
    m = A_ * ((1 - E2 / 4 - 3 * E2 ** 2 / 64 - 5 * E2 ** 3 / 256) * phi
              - (3 * E2 / 8 + 3 * E2 ** 2 / 32 + 45 * E2 ** 3 / 1024) * math.sin(2 * phi)
              + (15 * E2 ** 2 / 256 + 45 * E2 ** 3 / 1024) * math.sin(4 * phi)
              - (35 * E2 ** 3 / 3072) * math.sin(6 * phi))
    x = K0 * n * (a + (1 - t + c) * a ** 3 / 6 + (5 - 18 * t + t * t + 72 * c - 58 * EP2) * a ** 5 / 120) + 500000.0
    y = K0 * (m + n * math.tan(phi) * (a * a / 2 + (5 - t + 9 * c + 4 * c * c) * a ** 4 / 24
                                       + (61 - 58 * t + t * t + 600 * c - 330 * EP2) * a ** 6 / 720))
    return x, y


def utm_inv(x, y):
    x -= 500000.0
    m = y / K0
    mu = m / (A_ * (1 - E2 / 4 - 3 * E2 ** 2 / 64 - 5 * E2 ** 3 / 256))
    e1 = (1 - math.sqrt(1 - E2)) / (1 + math.sqrt(1 - E2))
    p1 = (mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * math.sin(2 * mu) + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * math.sin(4 * mu)
          + (151 * e1 ** 3 / 96) * math.sin(6 * mu))
    n1 = A_ / math.sqrt(1 - E2 * math.sin(p1) ** 2)
    t1 = math.tan(p1) ** 2
    c1 = EP2 * math.cos(p1) ** 2
    r1 = A_ * (1 - E2) / (1 - E2 * math.sin(p1) ** 2) ** 1.5
    d = x / (n1 * K0)
    lat = p1 - (n1 * math.tan(p1) / r1) * (d * d / 2 - (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * EP2) * d ** 4 / 24
                                          + (61 + 90 * t1 + 298 * c1 + 45 * t1 * t1 - 252 * EP2 - 3 * c1 * c1) * d ** 6 / 720)
    lon = LON0 + (d - (1 + 2 * t1 + c1) * d ** 3 / 6 + (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * EP2 + 24 * t1 * t1) * d ** 5 / 120) / math.cos(p1)
    return math.degrees(lat), math.degrees(lon)


# ------------------------------------------------------------------ small PNG reader / writer
def read_png_rgb(path):
    data = open(path, "rb").read()
    pos, w, h, idat = 8, 0, 0, b""
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", chunk[:10])
            assert depth == 8 and ctype in (2, 6), "expects 8-bit RGB/RGBA"
            bpp = 3 if ctype == 2 else 4
        elif typ == b"IDAT":
            idat += chunk
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * bpp
    out = np.zeros((h, stride), np.uint8)
    prev = np.zeros(stride, np.int32)
    for r in range(h):
        f = raw[r * (stride + 1)]
        line = np.frombuffer(raw, np.uint8, stride, r * (stride + 1) + 1).astype(np.int32)
        if f == 0:
            cur = line
        elif f == 2:
            cur = (line + prev) & 255
        else:
            cur = np.zeros(stride, np.int32)
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                if f == 1:
                    pr = a
                elif f == 3:
                    pr = (a + b) >> 1
                else:
                    p = a + b - c
                    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                    pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (line[i] + pr) & 255
        out[r] = cur
        prev = cur
    return out.reshape(h, w, bpp)[:, :, :3]


def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[r].tobytes() for r in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


# ------------------------------------------------------------------ glTF writer
class Mesh:
    """Triangle soup with per-vertex colour, collected per material."""

    def __init__(self):
        self.parts = defaultdict(lambda: ([], [], []))   # material -> (pos, col, idx)

    def tri(self, mat, a, b, c, col, up=None):
        """a,b,c in game space (x east, y up, z = -north). If `up` is given, the triangle
        is wound so its front faces that direction."""
        if up is not None:
            n = np.cross(np.subtract(b, a), np.subtract(c, a))
            if np.dot(n, up) < 0:
                b, c = c, b
        p, cl, ix = self.parts[mat]
        base = len(p)
        p.extend((a, b, c))
        cl.extend((col, col, col))
        ix.extend((base, base + 1, base + 2))

    def quad(self, mat, a, b, c, d, col, up=None):
        self.tri(mat, a, b, c, col, up)
        self.tri(mat, a, c, d, col, up)

    def grid(self, mat, verts, cols, nx, ny):
        """Regular grid (ny rows x nx cols), shared vertices, front face up."""
        p, cl, ix = self.parts[mat]
        base = len(p)
        p.extend(map(tuple, verts))
        cl.extend(map(tuple, cols))
        for j in range(ny - 1):
            for i in range(nx - 1):
                a = base + j * nx + i
                b, c, d = a + 1, a + nx + 1, a + nx
                # rows go north -> south in z (z grows south); this winding faces +y
                ix.extend((a, d, b, b, d, c))

    def empty(self):
        return all(len(v[0]) == 0 for v in self.parts.values())


def write_glb(path, nodes):
    """nodes: list of (name, Mesh). Writes POSITION / NORMAL / COLOR_0 / indices."""
    bin_parts, views, accessors, meshes, gnodes, materials, mat_index = [], [], [], [], [], [], {}
    offset = 0

    def add_view(arr, target):
        nonlocal offset
        b = arr.tobytes()
        pad = (-len(b)) % 4
        bin_parts.append(b + b"\x00" * pad)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(b), "target": target})
        offset += len(b) + pad
        return len(views) - 1

    for name, mesh in nodes:
        prims = []
        for mat, (pos, col, idx) in mesh.parts.items():
            if not idx:
                continue
            P = np.asarray(pos, np.float32)
            C = np.asarray(col, np.float32)
            I = np.asarray(idx, np.uint32)
            # flat normals per triangle (low-poly look)
            tri = P[I.reshape(-1, 3)]
            n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            ln = np.linalg.norm(n, axis=1, keepdims=True)
            n = n / np.maximum(ln, 1e-9)
            Nrm = np.zeros_like(P)
            np.add.at(Nrm, I.reshape(-1, 3), n[:, None, :].repeat(3, 1))
            Nrm /= np.maximum(np.linalg.norm(Nrm, axis=1, keepdims=True), 1e-9)
            if mat not in mat_index:
                mat_index[mat] = len(materials)
                materials.append({"name": mat, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                  "metallicFactor": 0.0, "roughnessFactor": 0.9}})
            va = add_view(P, 34962)
            accessors.append({"bufferView": va, "componentType": 5126, "count": len(P), "type": "VEC3",
                              "min": P.min(0).tolist(), "max": P.max(0).tolist()})
            ap = len(accessors) - 1
            accessors.append({"bufferView": add_view(Nrm.astype(np.float32), 34962), "componentType": 5126,
                              "count": len(P), "type": "VEC3"})
            an = len(accessors) - 1
            accessors.append({"bufferView": add_view(C, 34962), "componentType": 5126, "count": len(P),
                              "type": "VEC4" if C.shape[1] == 4 else "VEC3"})
            ac = len(accessors) - 1
            accessors.append({"bufferView": add_view(I, 34963), "componentType": 5125, "count": len(I), "type": "SCALAR"})
            ai = len(accessors) - 1
            prims.append({"attributes": {"POSITION": ap, "NORMAL": an, "COLOR_0": ac}, "indices": ai,
                          "material": mat_index[mat]})
        if prims:
            meshes.append({"name": name, "primitives": prims})
            gnodes.append({"name": name, "mesh": len(meshes) - 1})
    if not gnodes:
        return False
    gltf = {"asset": {"version": "2.0", "generator": "monrovia build_osm_city.py",
                      "copyright": "Map data (c) OpenStreetMap contributors, ODbL"},
            "scene": 0, "scenes": [{"nodes": list(range(len(gnodes)))}], "nodes": gnodes, "meshes": meshes,
            "materials": materials, "accessors": accessors, "bufferViews": views,
            "buffers": [{"byteLength": offset}]}
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    binb = b"".join(bin_parts)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)
    return True


# ------------------------------------------------------------------ geometry helpers
def polygon_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        a += x1 * y2 - x2 * y1
    return a / 2.0


def earclip(pts):
    """Triangulates a simple polygon (CCW). Returns index triples."""
    n = len(pts)
    if n < 3:
        return []
    idx = list(range(n))
    out = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            ax, ay = pts[i0]
            bx, by = pts[i1]
            cx, cy = pts[i2]
            if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) <= 1e-9:
                continue
            inside = False
            for j in idx:
                if j in (i0, i1, i2):
                    continue
                px, py = pts[j]
                d1 = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
                d2 = (cx - bx) * (py - by) - (cy - by) * (px - bx)
                d3 = (ax - cx) * (py - cy) - (ay - cy) * (px - cx)
                if d1 > 0 and d2 > 0 and d3 > 0:
                    inside = True
                    break
            if inside:
                continue
            out.append((i0, i1, i2))
            idx.pop(k)
            found = True
            break
        if not found:
            break
    if len(idx) == 3:
        out.append(tuple(idx))
    elif len(idx) > 3:          # degenerate leftovers: fan
        for k in range(1, len(idx) - 1):
            out.append((idx[0], idx[k], idx[k + 1]))
    return out


def fill_polygon(mask, poly, value, x0, y0, cell):
    """Scanline-fills polygon (list of local x,y) into mask (rows = y going north from y0)."""
    if len(poly) < 3:
        return
    P = np.asarray(poly, np.float64)
    gx = (P[:, 0] - x0) / cell
    gy = (P[:, 1] - y0) / cell
    r0 = max(0, int(math.floor(gy.min())))
    r1 = min(mask.shape[0] - 1, int(math.ceil(gy.max())))
    xa, ya = gx, gy
    xb, yb = np.roll(gx, -1), np.roll(gy, -1)
    for r in range(r0, r1 + 1):
        yc = r + 0.5
        cond = ((ya <= yc) & (yb > yc)) | ((yb <= yc) & (ya > yc))
        if not cond.any():
            continue
        xs = np.sort(xa[cond] + (yc - ya[cond]) * (xb[cond] - xa[cond]) / (yb[cond] - ya[cond]))
        for k in range(0, len(xs) - 1, 2):
            c0 = max(0, int(math.ceil(xs[k] - 0.5)))
            c1 = min(mask.shape[1] - 1, int(math.floor(xs[k + 1] - 0.5)))
            if c1 >= c0:
                mask[r, c0:c1 + 1] = value


def draw_line(mask, a, b, value, x0, y0, cell, thick=1):
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    n = max(2, int(L / (cell * 0.4)))
    xs = np.linspace(a[0], b[0], n)
    ys = np.linspace(a[1], b[1], n)
    cs = ((xs - x0) / cell).astype(int)
    rs = ((ys - y0) / cell).astype(int)
    for dr in range(-thick + 1, thick):
        for dc in range(-thick + 1, thick):
            rr = np.clip(rs + dr, 0, mask.shape[0] - 1)
            cc = np.clip(cs + dc, 0, mask.shape[1] - 1)
            mask[rr, cc] = value


def resample(line, step):
    """Densify a polyline (list of (x,y)) to points every `step` metres."""
    out = [line[0]]
    for i in range(len(line) - 1):
        a, b = line[i], line[i + 1]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(L / step))
        for k in range(1, n + 1):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def hsh(*v):
    h = 2166136261
    for x in v:
        h = ((h ^ (int(x) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    return h / 4294967296.0


# ------------------------------------------------------------------ build
class City:
    def __init__(self):
        t0 = time.time()
        self.bbox = json.load(open(os.path.join(ROOT, "data", "bbox.json")))
        s, w, n, e = BUILD_BBOX
        self.bbox.update({"south": max(s, self.bbox["south"]), "west": max(w, self.bbox["west"]),
                          "north": min(n, self.bbox["north"]), "east": min(e, self.bbox["east"])})
        self.osm = json.load(open(os.path.join(ROOT, "data", "osm", "monrovia_central.json"), encoding="utf-8"))["elements"]
        e0, n0 = utm(*SPAWN_LATLON)
        self.E0, self.N0 = round(e0), round(n0)
        corners = [self.local(self.bbox[a], self.bbox[b]) for a in ("south", "north") for b in ("west", "east")]
        self.xmin = min(c[0] for c in corners)
        self.xmax = max(c[0] for c in corners)
        self.ymin = min(c[1] for c in corners)
        self.ymax = max(c[1] for c in corners)
        self.nx = int((self.xmax - self.xmin) / GRID) + 1
        self.ny = int((self.ymax - self.ymin) / GRID) + 1
        print("area %.1f x %.1f km, raster %d x %d" % ((self.xmax - self.xmin) / 1000, (self.ymax - self.ymin) / 1000, self.nx, self.ny))
        self._dem()
        self._water_and_cover()
        print("rasters ready in %.0f s" % (time.time() - t0))

    def inside(self, x, y, margin=0.0):
        return self.xmin + margin <= x <= self.xmax - margin and self.ymin + margin <= y <= self.ymax - margin

    def local(self, lat, lon):
        e, n = utm(lat, lon)
        return e - self.E0, n - self.N0

    def geom(self, el):
        return [self.local(p["lat"], p["lon"]) for p in el.get("geometry", []) if p]

    def cell(self, x, y):
        c = int((x - self.xmin) / GRID)
        r = int((y - self.ymin) / GRID)
        return min(max(r, 0), self.ny - 1), min(max(c, 0), self.nx - 1)

    # ---------------- elevation
    def _dem(self):
        z = self.bbox["dem_zoom"]
        tiles = {}
        for f in os.listdir(os.path.join(ROOT, "data", "dem")):
            if f.startswith("terrarium_") and f.endswith(".png"):
                _, zz, tx, ty = f[:-4].split("_")
                rgb = read_png_rgb(os.path.join(ROOT, "data", "dem", f)).astype(np.float64)
                tiles[(int(tx), int(ty))] = rgb[:, :, 0] * 256 + rgb[:, :, 1] + rgb[:, :, 2] / 256 - 32768
        n = 2 ** z
        H = np.zeros((self.ny, self.nx))
        for r in range(self.ny):
            y = self.ymin + (r + 0.5) * GRID
            for c in range(self.nx):
                x = self.xmin + (c + 0.5) * GRID
                lat, lon = utm_inv(x + self.E0, y + self.N0)
                fx = (lon + 180) / 360 * n
                fy = (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n
                tx, ty = int(fx), int(fy)
                t = tiles.get((tx, ty))
                if t is None:
                    continue
                px = min(int((fx - tx) * 256), 255)
                py = min(int((fy - ty) * 256), 255)
                H[r, c] = t[py, px]
        # SRTM is a surface model (roofs, trees): smooth it to ground-ish relief
        for _ in range(4):
            H = (H + np.roll(H, 1, 0) + np.roll(H, -1, 0) + np.roll(H, 1, 1) + np.roll(H, -1, 1)) / 5.0
        self.dem = H

    # ---------------- water, coast, land cover
    def _water_and_cover(self):
        W = np.zeros((self.ny, self.nx), np.uint8)        # 1 = coastline barrier
        cover = np.zeros((self.ny, self.nx), np.uint8)    # land cover code
        water = np.zeros((self.ny, self.nx), bool)
        codes = {"park": 2, "grass": 1, "forest": 3, "wetland": 4, "sand": 5, "paving": 6, "built": 7}
        for el in self.osm:
            t = el.get("tags", {})
            if el["type"] == "way" and t.get("natural") == "coastline":
                g = self.geom(el)
                for i in range(len(g) - 1):
                    draw_line(W, g[i], g[i + 1], 1, self.xmin, self.ymin, GRID, thick=2)
        # Ocean = flood fill from the open sea (south-west corner), stopped by the coastline
        ocean = np.zeros_like(water)
        seed_r, seed_c = 1, 1
        ocean[seed_r, seed_c] = True
        free = W == 0
        for _ in range(4000):
            grown = ocean.copy()
            grown[1:] |= ocean[:-1]
            grown[:-1] |= ocean[1:]
            grown[:, 1:] |= ocean[:, :-1]
            grown[:, :-1] |= ocean[:, 1:]
            grown &= free
            if (grown == ocean).all():
                break
            ocean = grown
        if ocean.mean() > 0.85:       # coastline leak: fall back to "below sea level in the DEM"
            print("WARNING: coastline flood leaked; using DEM for the sea")
            ocean = self.dem < 0.5
        water |= ocean
        # Lagoons, river, ponds (outer rings fill, inner rings = islands)
        def rings(el):
            if el["type"] == "way":
                return [(self.geom(el), "outer")]
            return [([self.local(p["lat"], p["lon"]) for p in m.get("geometry", [])], m.get("role", "outer"))
                    for m in el.get("members", []) if m.get("type") == "way"]
        islands = []
        for el in self.osm:
            t = el.get("tags", {})
            is_water = (t.get("natural") == "water" or t.get("waterway") == "riverbank" or t.get("landuse") in ("reservoir", "basin"))
            cov = None
            if t.get("leisure") in ("park", "garden", "pitch", "stadium", "golf_course", "playground"):
                cov = "park"
            elif t.get("landuse") in ("grass", "meadow", "recreation_ground", "cemetery", "village_green", "farmland"):
                cov = "grass"
            elif t.get("natural") in ("wood", "scrub", "grassland") or t.get("landuse") == "forest":
                cov = "forest"
            elif t.get("natural") == "wetland":
                cov = "wetland"
            elif t.get("natural") in ("beach", "sand"):
                cov = "sand"
            elif t.get("aeroway") in ("runway", "apron", "taxiway") or t.get("landuse") in ("commercial", "retail") or t.get("amenity") == "parking":
                cov = "paving"
            elif t.get("landuse") in ("residential", "industrial"):
                cov = "built"
            if not is_water and cov is None:
                continue
            for ring, role in rings(el):
                if len(ring) < 3 or ring[0] != ring[-1] and el["type"] == "way":
                    continue
                if is_water:
                    if role == "inner":
                        islands.append(ring)
                    else:
                        m = np.zeros_like(water)
                        fill_polygon(m, ring, True, self.xmin, self.ymin, GRID)
                        water |= m
                elif role != "inner":
                    fill_polygon(cover, ring, codes[cov], self.xmin, self.ymin, GRID)
        for ring in islands:
            m = np.zeros_like(water)
            fill_polygon(m, ring, True, self.xmin, self.ymin, GRID)
            water &= ~m
        # river centre lines: carve a channel for waterways without areas
        for el in self.osm:
            t = el.get("tags", {})
            if el["type"] == "way" and t.get("waterway") in ("river", "canal"):
                g = self.geom(el)
                for i in range(len(g) - 1):
                    draw_line(water.view(np.uint8), g[i], g[i + 1], 1, self.xmin, self.ymin, GRID, thick=2)
        # Beaches: land within 3 cells of the ocean
        near = ocean.copy()
        for _ in range(3):
            near[1:] |= near[:-1].copy()
            near[:-1] |= near[1:].copy()
            near[:, 1:] |= near[:, :-1].copy()
            near[:, :-1] |= near[:, 1:].copy()
        cover[(near & ~water) & (cover != 6)] = codes["sand"]
        self.water = water
        self.ocean = ocean
        self.cover = cover
        self.codes = codes
        land = ~water
        H = np.where(land, np.maximum(self.dem, 0.6), SEA)
        self.H = H
        # preview image for checking (north up)
        img = np.zeros((self.ny, self.nx, 3), np.uint8)
        palette = {0: (180, 130, 90), 1: (90, 140, 66), 2: (80, 133, 56), 3: (51, 97, 43), 4: (61, 92, 56),
                   5: (219, 201, 153), 6: (158, 153, 143), 7: (168, 112, 77)}
        for k, v in palette.items():
            img[cover == k] = v
        img[water] = (40, 110, 160)
        img[W == 1] = (255, 255, 255)
        os.makedirs(OUT, exist_ok=True)
        write_png(os.path.join(OUT, "preview_landcover.png"), img[::-1].copy())

    def h(self, x, y):
        """Bilinear terrain height at local x, y."""
        fx = (x - self.xmin) / GRID - 0.5
        fy = (y - self.ymin) / GRID - 0.5
        c0 = int(math.floor(fx))
        r0 = int(math.floor(fy))
        tx, ty = fx - c0, fy - r0
        def g(r, c):
            return self.H[min(max(r, 0), self.ny - 1), min(max(c, 0), self.nx - 1)]
        return (g(r0, c0) * (1 - tx) * (1 - ty) + g(r0, c0 + 1) * tx * (1 - ty)
                + g(r0 + 1, c0) * (1 - tx) * ty + g(r0 + 1, c0 + 1) * tx * ty)

    def hm(self, x, y):
        """Height of the detailed terrain MESH at x, y (its 8 m triangles, same winding as
        Mesh.grid), so roads, sidewalks and buildings sit exactly on the ground surface."""
        s = HI_STEP
        gx = math.floor(x / s) * s
        gy = math.ceil(y / s) * s           # row nodes run north -> south
        u = (x - gx) / s
        v = (gy - y) / s
        a = self.h(gx, gy)
        b = self.h(gx + s, gy)
        d = self.h(gx, gy - s)
        c = self.h(gx + s, gy - s)
        if u + v <= 1.0:
            return a + u * (b - a) + v * (d - a)
        return c + (1 - u) * (d - c) + (1 - v) * (b - c)

    def is_water(self, x, y):
        r, c = self.cell(x, y)
        return bool(self.water[r, c])

    def cover_color(self, x, y):
        r, c = self.cell(x, y)
        if self.water[r, c]:
            return COL["seabed"]
        code = self.cover[r, c]
        name = {1: "grass", 2: "park", 3: "forest", 4: "wetland", 5: "sand", 6: "paving", 7: "laterite"}.get(code)
        if name is None:
            # unmapped land: downtown paving near Broad Street, otherwise laterite / grass mix
            if DOWNTOWN[0] < x < DOWNTOWN[1] and DOWNTOWN[2] < y < DOWNTOWN[3]:
                name = "paving"
            else:
                name = "laterite" if hsh(int(x / 24), int(y / 24)) < 0.7 else "grass"
        base = COL[name]
        v = 0.92 + 0.16 * hsh(int(x / 8), int(y / 8), 7)
        return (base[0] * v, base[1] * v, base[2] * v)


def tile_of(x, y):
    return int(math.floor(x / TILE)), int(math.floor(y / TILE))


def P(x, y, h):
    """local (x east, y north, height) -> game/glTF space (x, up, -north)"""
    return (x, h, -y)


def main():
    t_start = time.time()
    city = City()
    hi = defaultdict(lambda: {"Terrain-col": Mesh(), "Roads-col": Mesh(), "Sidewalks-col": Mesh(),
                              "Buildings-col": Mesh(), "Props": Mesh(), "Details": Mesh(),
                              "Foliage": Mesh()})
    lo = defaultdict(lambda: {"Lo": Mesh()})
    meta = defaultdict(lambda: {"signs": [], "paths": [], "parking": [], "lamps": [], "shops": [], "grass": [], "trees": []})
    graph_ways = []      # for the traffic road graph
    building_rings = []  # for the minimap
    UP = (0, 1, 0)

    # ---------------- roads
    ways = [el for el in city.osm if el["type"] == "way" and el.get("tags", {}).get("highway") in ROAD_W]
    ways.sort(key=lambda el: ROAD_RANK.get(el["tags"]["highway"], 0))
    road_mask = np.zeros((city.ny * 4, city.nx * 4), bool)       # 2 m grid: where roads are
    RM = GRID / 4

    def stamp(x, y, half):
        r = int((y - city.ymin) / RM)
        c = int((x - city.xmin) / RM)
        k = max(1, int((half - 0.5) / RM))     # cells covering the carriageway only
        road_mask[max(0, r - k):r + k + 1, max(0, c - k):c + k + 1] = True

    road_lines = []
    junction_count = defaultdict(set)
    for el in ways:
        t = el["tags"]
        kind = t["highway"]
        g = city.geom(el)
        g = [p for p in g if city.inside(*p)]
        if len(g) < 2:
            continue
        w = float(t.get("width", ROAD_W[kind])) if str(t.get("width", "")).replace(".", "", 1).isdigit() else ROAD_W[kind]
        w = min(max(w, 3.0), 24.0)
        for p in el.get("geometry", []):
            junction_count[(round(p["lat"], 7), round(p["lon"], 7))].add(t.get("name", "#%d" % el["id"]))
        road_lines.append((el, g, w))
        for x, y in resample(g, 4.0):
            stamp(x, y, w / 2)
    print("roads:", len(road_lines))

    for el, g, w in road_lines:
        t = el["tags"]
        kind = t["highway"]
        rank = ROAD_RANK.get(kind, 0)
        bridge = t.get("bridge") not in (None, "no")
        unpaved = t.get("surface") in ("unpaved", "dirt", "ground", "gravel", "sand", "earth", "compacted") or kind == "track"
        col = COL["dirt"] if unpaved else COL["asphalt"]
        pts = resample(g, 4.0)
        n = len(pts)
        hs = [city.hm(x, y) for x, y in pts]
        if bridge:
            # deck above the water, ramping down to the banks at both ends
            deck = max(max(hs), 0.0) + 4.0
            L = [0.0]
            for i in range(1, n):
                L.append(L[-1] + math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
            total = L[-1]
            for i in range(n):
                ramp = min(1.0, min(L[i], total - L[i]) / 30.0)
                hs[i] = max(hs[i], hs[i] + (deck - hs[i]) * ramp)
        ys = [hv + 0.12 + rank * 0.006 for hv in hs]
        if kind not in ("pedestrian", "track", "service"):
            ow = t.get("oneway", "no")
            graph_ways.append((kind, t.get("name", ""), 1 if ow in ("yes", "1", "true") else (-1 if ow == "-1" else 0), w, g, pts, ys))
        half = w / 2
        left, right = [], []
        for i in range(n):
            a = pts[max(0, i - 1)]
            b = pts[min(n - 1, i + 1)]
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy) or 1.0
            nx_, ny_ = -dy / L, dx / L
            left.append((pts[i][0] + nx_ * half, pts[i][1] + ny_ * half))
            right.append((pts[i][0] - nx_ * half, pts[i][1] - ny_ * half))
        dash = 0.0
        for i in range(n - 1):
            mx = (pts[i][0] + pts[i + 1][0]) / 2
            my = (pts[i][1] + pts[i + 1][1]) / 2
            tk = tile_of(mx, my)
            a, b = P(*left[i], ys[i]), P(*right[i], ys[i])
            c, d = P(*right[i + 1], ys[i + 1]), P(*left[i + 1], ys[i + 1])
            hi[tk]["Roads-col"].quad("Road", a, b, c, d, col, UP)
            lo[tk]["Lo"].quad("LoVC", a, b, c, d, col, UP)
            if not unpaved and not bridge and kind not in ("track", "service") and w >= 5.0:
                # concrete gutter channels along both edges
                for s0, s1 in ((left, 1), (right, -1)):
                    e0, e1 = s0[i], s0[i + 1]
                    ix, iy = pts[i][0] - e0[0], pts[i][1] - e0[1]
                    k0 = 0.45 / (math.hypot(ix, iy) or 1.0)
                    jx, jy = pts[i + 1][0] - e1[0], pts[i + 1][1] - e1[1]
                    k1 = 0.45 / (math.hypot(jx, jy) or 1.0)
                    hi[tk]["Roads-col"].quad("Paint", P(*e0, ys[i] + 0.012), P(e0[0] + ix * k0, e0[1] + iy * k0, ys[i] + 0.012),
                                             P(e1[0] + jx * k1, e1[1] + jy * k1, ys[i + 1] + 0.012), P(*e1, ys[i + 1] + 0.012),
                                             (0.36, 0.35, 0.33), UP)
            seg = math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            dash += seg
            if kind in MAJOR and not unpaved and (dash % 9.0) < 4.5:
                # centre line (yellow on the trunk roads), slightly above the road
                dxp, dyp = pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]
                Ls = math.hypot(dxp, dyp) or 1.0
                ox, oy = -dyp / Ls * 0.08, dxp / Ls * 0.08
                lc = COL["yellow"] if kind in ("trunk", "primary") else COL["paint"]
                hi[tk]["Roads-col"].quad("Paint", P(pts[i][0] + ox, pts[i][1] + oy, ys[i] + 0.02),
                                         P(pts[i][0] - ox, pts[i][1] - oy, ys[i] + 0.02),
                                         P(pts[i + 1][0] - ox, pts[i + 1][1] - oy, ys[i + 1] + 0.02),
                                         P(pts[i + 1][0] + ox, pts[i + 1][1] + oy, ys[i + 1] + 0.02), lc, UP)
            if bridge:
                for side in (left, right):     # railings
                    hi[tk]["Roads-col"].quad("Rail", P(*side[i], ys[i]), P(*side[i + 1], ys[i + 1]),
                                             P(*side[i + 1], ys[i + 1] + 1.0), P(*side[i], ys[i] + 1.0), COL["rail"])
        # sidewalks, lamps, parking along the main and residential roads (not on bridges)
        if bridge or unpaved or kind in ("service", "track"):
            continue
        name = t.get("name", "")
        sw = 2.2 if kind in MAJOR else 1.6
        for side in (1, -1):
            run = []
            for i in range(n):
                a = pts[max(0, i - 1)]
                b = pts[min(n - 1, i + 1)]
                dx, dy = b[0] - a[0], b[1] - a[1]
                L = math.hypot(dx, dy) or 1.0
                nx_, ny_ = -dy / L * side, dx / L * side
                inner = (pts[i][0] + nx_ * (half + 0.05), pts[i][1] + ny_ * (half + 0.05))
                outer = (pts[i][0] + nx_ * (half + sw), pts[i][1] + ny_ * (half + sw))
                mid = (pts[i][0] + nx_ * (half + sw / 2 + 1.0), pts[i][1] + ny_ * (half + sw / 2 + 1.0))
                rr = int((mid[1] - city.ymin) / RM)
                cc = int((mid[0] - city.xmin) / RM)
                inside_road = 0 <= rr < road_mask.shape[0] and 0 <= cc < road_mask.shape[1] and road_mask[rr, cc]
                ok = not inside_road and not city.is_water(*outer)
                if ok:
                    run.append((inner, outer, mid, ys[i], nx_, ny_))
                if (not ok or i == n - 1) and len(run) >= 2:
                    for k in range(len(run) - 1):
                        e, f = run[k], run[k + 1]
                        tk = tile_of(e[2][0], e[2][1])
                        ya, yb = e[3] + 0.15, f[3] + 0.15
                        hi[tk]["Sidewalks-col"].quad("Sidewalk", P(*e[0], ya), P(*e[1], ya), P(*f[1], yb), P(*f[0], yb), COL["sidewalk"], UP)
                        hi[tk]["Sidewalks-col"].quad("Sidewalk", P(*e[0], ya - 0.2), P(*f[0], yb - 0.2), P(*f[0], yb), P(*e[0], ya), COL["curb"], (-e[4], 0, e[5]))
                        hi[tk]["Sidewalks-col"].quad("Sidewalk", P(*e[1], ya), P(*f[1], yb), P(*f[1], yb - 0.4), P(*e[1], ya - 0.4), COL["sidewalk"], (e[4], 0, -e[5]))
                    # pedestrian path and props for this run (by tile)
                    by_tile = defaultdict(list)
                    for e in run:
                        by_tile[tile_of(*e[2])].append([round(e[2][0], 2), round(e[3] + 0.2, 2), round(-e[2][1], 2)])
                    for tk, path in by_tile.items():
                        if len(path) >= 4:
                            meta[tk]["paths"].append(path)
                    for k, e in enumerate(run):
                        tk = tile_of(*e[2])
                        x, y = e[1][0] - e[4] * 0.4, e[1][1] - e[5] * 0.4
                        if kind in MAJOR and k % 9 == 4 and side == (1 if (k // 9) % 2 == 0 else -1):
                            _lamp(hi[tk]["Props"], x, y, e[3] + 0.15, -e[4], -e[5])
                            meta[tk]["lamps"].append([round(x - e[4] * 1.6, 2), round(e[3] + 6.6, 2), round(-(y - e[5] * 1.6), 2)])
                        if kind in ("trunk", "primary", "secondary") and k % 7 == 2 and hsh(x, y) < 0.5:
                            meta[tk]["trees"].append([round(x, 2), round(e[3] + 0.15, 2), round(-y, 2), 0, round(hsh(x, y, 3), 2)])
                        if kind in ("residential", "unclassified", "tertiary") and k % 5 == 2 and hsh(x, y, 9) < 0.18:
                            px, py = e[0][0] - e[4] * 1.3, e[0][1] - e[5] * 1.3
                            heading = math.atan2(-e[5], -e[4]) if side > 0 else math.atan2(e[5], e[4])
                            meta[tk]["parking"].append([round(px, 2), round(e[3] + 0.5, 2), round(-py, 2), round(heading, 3)])
                    run = []
                elif not ok:
                    run = []
    # street-name signs at junctions of two named roads
    for el in city.osm:
        if el["type"] != "way" or el.get("tags", {}).get("highway") not in ROAD_W:
            continue
        for p in el.get("geometry", []):
            names = {n for n in junction_count[(round(p["lat"], 7), round(p["lon"], 7))] if not n.startswith("#")}
            if len(names) >= 2:
                x, y = city.local(p["lat"], p["lon"])
                tk = tile_of(x, y)
                if not any(abs(s[0] - x) < 12 and abs(s[2] + y) < 12 for s in meta[tk]["signs"]):
                    meta[tk]["signs"].append([round(x, 2), round(city.hm(x, y), 2), round(-y, 2), sorted(names)[:2]])
    print("roads, sidewalks, props done %.0f s" % (time.time() - t_start))

    # ---------------- buildings
    count = 0
    landmarks = []
    downtown = lambda x, y: DOWNTOWN[0] < x < DOWNTOWN[1] and DOWNTOWN[2] < y < DOWNTOWN[3]
    for el in city.osm:
        t = el.get("tags", {})
        name = t.get("name", "")
        if name and any(k.lower() in name.lower() for k in LANDMARKS):
            g = city.geom(el) if el["type"] == "way" else ([city.local(el["lat"], el["lon"])] if "lat" in el else [])
            if not g and el["type"] == "relation":
                for m in el.get("members", []):
                    if m.get("role") == "outer" and m.get("geometry"):
                        g = [city.local(p["lat"], p["lon"]) for p in m["geometry"]]
                        break
            if g:
                cx = sum(p[0] for p in g) / len(g)
                cy = sum(p[1] for p in g) / len(g)
                if city.inside(cx, cy) and not any(L["name"] == name for L in landmarks):
                    landmarks.append({"name": name, "pos": [round(cx, 1), round(city.h(cx, cy), 1), round(-cy, 1)]})
        if "building" not in t:
            continue
        if el["type"] == "way":
            ring = city.geom(el)
        else:
            ring = []
            for m in el.get("members", []):
                if m.get("role") == "outer" and m.get("geometry"):
                    ring = [city.local(p["lat"], p["lon"]) for p in m["geometry"]]
                    break
        if len(ring) < 4:
            continue
        if ring[0] == ring[-1]:
            ring = ring[:-1]
        area = polygon_area(ring)
        if abs(area) < 6:
            continue
        if area < 0:
            ring = ring[::-1]
            area = -area
        cx = sum(p[0] for p in ring) / len(ring)
        cy = sum(p[1] for p in ring) / len(ring)
        if city.is_water(cx, cy) or not city.inside(cx, cy):
            continue
        try:
            levels = float(str(t.get("building:levels", "")).split(";")[0])
        except ValueError:
            levels = 0
        height = None
        try:
            height = float(str(t.get("height", "")).replace("m", "").strip())
        except ValueError:
            pass
        r = hsh(el["id"])
        if not levels:
            levels = 1 if area < 70 else (1 + (r < 0.4) if area < 220 else (2 + (r < 0.5) if area < 700 else 3 + int(r * 2)))
            if downtown(cx, cy) and area > 120:
                levels += int(r * 2.5)          # downtown: a little taller on average
        if t.get("building") in ("church", "cathedral", "mosque"):
            levels = max(levels, 3)
        top_h = height if height else levels * 3.2 + 0.3
        base = min(city.hm(x, y) for x, y in ring) - 0.4
        top = base + 0.4 + top_h
        wall = WALLS[int(r * len(WALLS)) % len(WALLS)]
        flat = levels >= 3 or area > 400
        roof = COL["roofcon"] if flat else (COL["rust"] if hsh(el["id"], 5) < 0.45 else COL["zinc"])
        tk = tile_of(cx, cy)
        building_rings.append(ring)
        # low detail: plain walls and a flat top
        lom = lo[tk]["Lo"]
        for i in range(len(ring)):
            a = ring[i]
            b = ring[(i + 1) % len(ring)]
            lom.quad("LoVC", P(*a, base), P(*b, base), P(*b, top), P(*a, top), wall, (b[1] - a[1], 0, b[0] - a[0]))
        for i0, i1, i2 in earclip(ring):
            lom.tri("LoVC", P(*ring[i0], top), P(*ring[i1], top), P(*ring[i2], top), roof, UP)
        # detailed: walls, then a real roof and details
        m = hi[tk]["Buildings-col"]
        props = hi[tk]["Details"]
        for i in range(len(ring)):
            a = ring[i]
            b = ring[(i + 1) % len(ring)]
            out = (b[1] - a[1], 0, b[0] - a[0])    # outward for CCW rings, in game space (z = -north)
            m.quad("Wall", P(*a, base), P(*b, base), P(*b, top), P(*a, top), wall, out)
        if flat:
            _flat_roof(m, props, ring, top, roof, wall, el["id"])
        else:
            _pitched_roof(m, ring, top, roof, el["id"])
        _wall_details(m, props, meta[tk], ring, base, top, levels, wall, el["id"], downtown(cx, cy) or t.get("building") in ("commercial", "retail"), city, road_mask, RM)
        count += 1
    print("buildings:", count, "(%.0f s)" % (time.time() - t_start))

    # ---------------- vegetation: palms, trees and bushes on green land, grass tuft spots
    bmask = np.zeros_like(road_mask)
    for ring in building_rings:
        fill_polygon(bmask, ring, True, city.xmin, city.ymin, RM)
    nveg = [0, 0, 0]
    STEP = 5.0
    for yy in np.arange(city.ymin + 2, city.ymax - 2, STEP):
        for xx in np.arange(city.xmin + 2, city.xmax - 2, STEP):
            jx = float(xx + (hsh(int(xx), int(yy), 21) - 0.5) * STEP)
            jy = float(yy + (hsh(int(xx), int(yy), 22) - 0.5) * STEP)
            if city.is_water(jx, jy):
                continue
            rr, cc = int((jy - city.ymin) / RM), int((jx - city.xmin) / RM)
            if not (1 <= rr < bmask.shape[0] - 1 and 1 <= cc < bmask.shape[1] - 1):
                continue
            if bmask[rr - 1:rr + 2, cc - 1:cc + 2].any() or road_mask[rr - 1:rr + 2, cc - 1:cc + 2].any():
                continue
            r_, c_ = city.cell(jx, jy)
            code = int(city.cover[r_, c_])
            green = code in (1, 2, 3, 4) or (code == 0 and not (DOWNTOWN[0] < jx < DOWNTOWN[1] and DOWNTOWN[2] < jy < DOWNTOWN[3])
                                                and hsh(int(jx / 24), int(jy / 24)) >= 0.7)
            if not green:
                continue
            tk = tile_of(jx, jy)
            h = city.hm(jx, jy)
            u = hsh(int(jx * 7), int(jy * 7), 23)
            dense = code in (3, 4)
            if u < (0.05 if dense else 0.012):
                kind_ = 1 if dense and u < 0.03 else 0
                meta[tk]["trees"].append([round(jx, 2), round(h, 2), round(-jy, 2), kind_, round(hsh(int(jx), int(jy), 24), 2)])
                nveg[0] += 1
            elif u < (0.16 if dense else 0.05):
                meta[tk]["trees"].append([round(jx, 2), round(h, 2), round(-jy, 2), 2, round(hsh(int(jx), int(jy), 25), 2)])
                nveg[1] += 1
            if len(meta[tk]["grass"]) < 900 and u > 0.35:
                meta[tk]["grass"].append([round(jx, 1), round(h, 2), round(-jy, 1)])
                nveg[2] += 1
    print("vegetation: %d trees, %d bushes, %d grass spots" % tuple(nveg))
    # the plant models themselves, instanced by the game at the positions in the tile meta
    veg = []
    for name, fn in (("Palm", lambda m, f: _palm(m, f, 0.0, 0.0, 0.0, 0.5)),
                     ("Tree", lambda m, f: _tree(m, f, 0.0, 0.0, 0.0, 0.5)),
                     ("Bush", lambda m, f: _bush(f, 0.0, 0.0, 0.0, 0.5))):
        mm = Mesh()
        fn(mm, mm)
        veg.append((name, mm))

    # ---------------- terrain tiles
    tiles = set(hi.keys()) | set(lo.keys())
    i0, j0 = tile_of(city.xmin, city.ymin)
    i1, j1 = tile_of(city.xmax - 1, city.ymax - 1)
    for i in range(i0, i1 + 1):
        for j in range(j0, j1 + 1):
            x0, y0 = i * TILE, j * TILE
            # skip open-sea tiles (the game's endless ocean plane covers them)
            sample = [city.is_water(x0 + a, y0 + b) for a in range(0, 257, 32) for b in range(0, 257, 32)]
            if all(sample) and (i, j) not in tiles:
                continue
            tiles.add((i, j))
            for step, target, mat, name in ((HI_STEP, hi, "Terrain", "Terrain-col"), (LO_STEP, lo, "LoVC", "Lo")):
                nv = int(TILE / step) + 1
                verts, cols = [], []
                for r in range(nv):              # north to south rows
                    y = y0 + TILE - r * step
                    for c in range(nv):
                        x = x0 + c * step
                        hv = city.h(x, y) if step == HI_STEP else city.h(x, y) - 0.15
                        verts.append(P(x, y, hv))
                        cols.append(city.cover_color(x, y))
                target[(i, j)][name].grid(mat, verts, cols, nv, nv)

    # ---------------- write
    for sub in ("hi", "lo", "meta"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
        for f in os.listdir(os.path.join(OUT, sub)):
            os.remove(os.path.join(OUT, sub, f))
    write_glb(os.path.join(OUT, "vegetation.glb"), veg)
    with open(os.path.join(OUT, "vegetation.glb.import"), "w") as f:
        f.write('[remap]\n\nimporter="keep"\n')
    manifest_tiles = []
    total = 0
    for (i, j) in sorted(tiles):
        tag = "t_%d_%d" % (i, j)
        ok_hi = write_glb(os.path.join(OUT, "hi", tag + ".glb"), [(k, m) for k, m in hi[(i, j)].items() if not m.empty()])
        ok_lo = write_glb(os.path.join(OUT, "lo", tag + ".glb"), [(k, m) for k, m in lo[(i, j)].items() if not m.empty()])
        with open(os.path.join(OUT, "meta", tag + ".json"), "w") as f:
            json.dump(meta[(i, j)], f, separators=(",", ":"))
        # Tiles are loaded at runtime by the world streamer (GLTFDocument), so Godot keeps
        # them as raw files in exports instead of importing ~1,700 scenes.
        for sub, ok in (("hi", ok_hi), ("lo", ok_lo)):
            if ok:
                with open(os.path.join(OUT, sub, tag + ".glb.import"), "w") as f:
                    f.write('[remap]\n\nimporter="keep"\n')
        if ok_hi or ok_lo:
            manifest_tiles.append([i, j])
            total += os.path.getsize(os.path.join(OUT, "hi", tag + ".glb")) if ok_hi else 0
            total += os.path.getsize(os.path.join(OUT, "lo", tag + ".glb")) if ok_lo else 0
    sx, sy = SPAWN_NEAR   # spawn: the Broad Street point nearest SPAWN_NEAR
    best = 1e9
    for el, g, w in road_lines:
        if el["tags"].get("name") == "Broad Street":
            for x, y in resample(g, 4.0):
                d = math.hypot(x - SPAWN_NEAR[0], y - SPAWN_NEAR[1])
                if d < best:
                    best, sx, sy = d, x, y
    places = {}          # a point in the middle of some well-known roads (for tests and screenshots)
    for want in ("Broad Street", "Tubman Boulevard", "United Nations Drive", "UN Drive", "Capitol Bypass", "Ashmun Street", "Randall Street"):
        pts_all = [p for el, g, w in road_lines if el["tags"].get("name") == want for p in resample(g, 4.0)]
        if pts_all:
            mx = sum(p[0] for p in pts_all) / len(pts_all)
            my = sum(p[1] for p in pts_all) / len(pts_all)
            px, py = min(pts_all, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)
            places[want] = [round(px, 2), round(city.hm(px, py) + 1.5, 2), round(-py, 2)]
    manifest = {
        "tile_size": TILE, "origin_utm29n": [city.E0, city.N0], "origin_latlon": SPAWN_LATLON,
        "hi": [[i, j] for (i, j) in sorted(tiles) if os.path.exists(os.path.join(OUT, "hi", "t_%d_%d.glb" % (i, j)))],
        "spawn": [round(sx, 2), round(city.hm(sx, sy) + 1.5, 2), round(-sy, 2)],
        "bounds": [city.xmin, -city.ymax, city.xmax, -city.ymin],
        "tiles": manifest_tiles, "landmarks": landmarks, "places": places,
        "credits": "Map data (c) OpenStreetMap contributors, ODbL. Elevation: Terrain Tiles (AWS Open Data), SRTM.",
    }
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    nodes, edges = build_graph(graph_ways)
    with open(os.path.join(OUT, "roads_graph.json"), "w") as f:
        json.dump({"nodes": nodes, "edges": edges}, f, separators=(",", ":"))
    print("road graph: %d junctions, %d road edges" % (len(nodes), len(edges)))
    write_places(city, meta, landmarks, edges)
    write_minimap(city, road_mask, building_rings)
    print("tiles: %d, %.1f MB of glb, landmarks: %d, done in %.0f s" % (len(manifest_tiles), total / 1e6, len(landmarks), time.time() - t_start))


# ------------------------------------------------------------------ game data: road graph, places, minimap
def build_graph(graph_ways):
    """Junction graph of the drivable roads for traffic: nodes where roads meet or end,
    edges = road pieces between them (points every ~8 m at road-surface height)."""
    key = lambda x, y: (round(x * 2), round(y * 2))
    count = defaultdict(int)
    for kind, name, oneway, w, g, pts, ys in graph_ways:
        for i, (x, y) in enumerate(g):
            count[key(x, y)] += 2 if i in (0, len(g) - 1) else 1
    ids, nodes, edges = {}, [], []

    def node_id(x, y, z):
        k = key(x, y)
        if k not in ids:
            ids[k] = len(nodes)
            nodes.append([round(x, 2), round(z, 2), round(-y, 2)])
        return ids[k]

    for kind, name, oneway, w, g, pts, ys in graph_ways:
        idx = [0]
        for i in range(len(g) - 1):
            L = math.hypot(g[i + 1][0] - g[i][0], g[i + 1][1] - g[i][1])
            idx.append(idx[-1] + max(1, int(L / 4.0)))
        start = 0
        for vi in range(1, len(g)):
            if count[key(*g[vi])] >= 2 or vi == len(g) - 1:
                seg = list(range(idx[start], idx[vi] + 1))
                keep = seg[::2]
                if keep[-1] != seg[-1]:
                    keep.append(seg[-1])
                p = [[round(pts[j][0], 2), round(ys[j], 2), round(-pts[j][1], 2)] for j in keep]
                a = node_id(g[start][0], g[start][1], ys[idx[start]])
                b = node_id(g[vi][0], g[vi][1], ys[idx[vi]])
                if a != b and len(p) >= 2:
                    edges.append({"a": a, "b": b, "p": p, "w": w, "k": kind, "n": name, "o": oneway})
                start = vi
    return nodes, edges


LANDMARK_FOR = {"executive_mansion": "Executive Mansion", "capitol": "Capitol Building", "jfk": "John F. Kennedy",
                "hospital": "John F. Kennedy", "university": "University of Liberia", "centennial": "Centennial Pavilion",
                "ducor": "Ducor", "tubman_stadium": "Antoinette Tubman Stadium",
                "police_hq": "National Police Headquarters"}


def write_places(city, meta, landmarks, edges):
    """Snaps the game's places (proto3d/game/data/places_src.json) to the nearest sidewalk
    (or road) and writes them in game coordinates to proto3d/city/places.json."""
    src = json.load(open(os.path.join(ROOT, "proto3d", "game", "data", "places_src.json"), encoding="utf-8"))
    walk = np.array([p for m in meta.values() for path in m["paths"] for p in path], np.float64)
    road = np.array([p for e in edges for p in e["p"]], np.float64)

    def snap(x, z, pool):
        d = (pool[:, 0] - x) ** 2 + (pool[:, 2] - z) ** 2
        i = int(np.argmin(d))
        return pool[i].tolist(), math.sqrt(d[i])

    def place(entry):
        lm = LANDMARK_FOR.get(entry.get("id", ""))
        pos = None
        if lm:
            for L in landmarks:
                if lm.lower() in L["name"].lower():
                    pos = (L["pos"][0], L["pos"][2])
        if pos is None:
            x, y = city.local(entry["lat"], entry["lon"])
            pos = (x, -y)
        p, d = snap(pos[0], pos[1], walk)
        if d > 120.0:
            p, d = snap(pos[0], pos[1], road)
        out = dict(entry)
        out.pop("lat", None)
        out.pop("lon", None)
        out["pos"] = [round(p[0], 2), round(p[1], 2), round(p[2], 2)]
        return out

    res = {"poi": [place(e) for e in src["poi"]], "dest": [place(e) for e in src["dest"]], "district": []}
    for e in src["district"]:
        x, y = city.local(e["lat"], e["lon"])
        res["district"].append({"name": e["name"], "pos": [round(x, 1), 0, round(-y, 1)]})
    with open(os.path.join(OUT, "places.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, indent=1)
    print("places: %d points of interest, %d destinations" % (len(res["poi"]), len(res["dest"])))


def write_minimap(city, road_mask, rings):
    """North-up map image of the built area at 4 m per pixel (water, land cover, buildings,
    roads) for the HUD minimap and the full-screen map."""
    MPP = 4.0
    cover = np.repeat(np.repeat(city.cover, 2, 0), 2, 1)
    water = np.repeat(np.repeat(city.water, 2, 0), 2, 1)
    h, w = cover.shape
    img = np.zeros((h, w, 3), np.uint8)
    pal = {0: (176, 132, 98), 1: (104, 150, 78), 2: (92, 146, 70), 3: (62, 110, 52), 4: (70, 104, 64),
           5: (222, 205, 160), 6: (170, 166, 158), 7: (180, 128, 94)}
    for k, v in pal.items():
        img[cover == k] = v
    img[water] = (38, 108, 158)
    bmask = np.zeros((h, w), bool)
    for ring in rings:
        fill_polygon(bmask, ring, True, city.xmin, city.ymin, MPP)
    img[bmask] = (205, 196, 182)
    rm = road_mask[: h * 2, : w * 2]
    rm = rm.reshape(rm.shape[0] // 2, 2, rm.shape[1] // 2, 2).any(axis=(1, 3))
    img[: rm.shape[0], : rm.shape[1]][rm] = (238, 238, 232)
    write_png(os.path.join(OUT, "minimap.png"), img[::-1].copy())
    info = {"x0": city.xmin, "z0": -city.ymax, "m_per_px": MPP, "w": w, "h": h}
    with open(os.path.join(OUT, "minimap.json"), "w") as f:
        json.dump(info, f)
    print("minimap: %d x %d px" % (w, h))


def _lamp(m, x, y, h, dx, dy):
    """Street light: pole, arm reaching over the road (dx, dy = toward road), lamp head."""
    s = 0.09
    for (ax, ay, bx, by, z0, z1) in ((x - s, y - s, x + s, y + s, h, h + 7.0),):
        _box(m, "Props", ax, ay, bx, by, z0, z1, COL["lamp"])
    ex, ey = x + dx * 1.6, y + dy * 1.6
    _box(m, "Props", min(x, ex) - 0.05, min(y, ey) - 0.05, max(x, ex) + 0.05, max(y, ey) + 0.05, h + 6.85, h + 6.95, COL["lamp"])
    _box(m, "Glow", ex - 0.25, ey - 0.25, ex + 0.25, ey + 0.25, h + 6.65, h + 6.85, (1.0, 0.95, 0.8))


LEAF = (0.22, 0.47, 0.16)


def _frond(f, x, y, z, a, length, droop, col):
    """Arched palm frond: 4 segments, double sided. Vertex alpha = wind sway weight
    (0 at the crown, 1 at the tip)."""
    ca, sa = math.cos(a), math.sin(a)
    px, py = -sa, ca
    pts = []
    for k in range(5):
        t = k / 4
        d = length * t
        zz = z + d * 0.45 - droop * t * t * length
        w = 0.15 + 0.55 * math.sin(t * math.pi) if k < 4 else 0.02
        pts.append((x + ca * d, y + sa * d, zz, w, 0.2 + 0.8 * t))
    for k in range(4):
        (ax, ay, az, aw, ak), (bx, by, bz, bw, bk) = pts[k], pts[k + 1]
        qa = (P(ax + px * aw, ay + py * aw, az - aw * 0.25), col + (ak,))
        qb = (P(ax - px * aw, ay - py * aw, az - aw * 0.25), col + (ak,))
        qc = (P(bx - px * bw, by - py * bw, bz - bw * 0.25), col + (bk,))
        qd = (P(bx + px * bw, by + py * bw, bz - bw * 0.25), col + (bk,))
        for up in ((0, 1, 0), (0, -1, 0)):
            _vtri(f, "Foliage", qa, qb, qc, up)
            _vtri(f, "Foliage", qa, qc, qd, up)


def _vtri(m, mat, a, b, c, up):
    """Triangle with per-vertex colours: a, b, c = (position, colour)."""
    n = np.cross(np.subtract(b[0], a[0]), np.subtract(c[0], a[0]))
    if np.dot(n, up) < 0:
        b, c = c, b
    p, cl, ix = m.parts[mat]
    base = len(p)
    for v in (a, b, c):
        p.append(v[0])
        cl.append(v[1])
    ix.extend((base, base + 1, base + 2))


def _palm(m, f, x, y, h, r):
    """Coconut palm: slightly leaning tapered trunk, crown of arched fronds, coconuts."""
    ht = 6.5 + r * 3.5
    lean_a = r * 40.0
    lx, ly = math.cos(lean_a) * ht * 0.08, math.sin(lean_a) * ht * 0.08
    sides = 6
    prev = None
    for k in range(5):
        t = k / 4
        cx, cy, cz = x + lx * t * t, y + ly * t * t, h + ht * t
        rad = 0.2 - 0.07 * t
        ring = [(cx + rad * math.cos(i * math.tau / sides), cy + rad * math.sin(i * math.tau / sides), cz) for i in range(sides)]
        if prev:
            for i in range(sides):
                a0, a1 = prev[i], prev[(i + 1) % sides]
                b0, b1 = ring[i], ring[(i + 1) % sides]
                mx, my = (a0[0] + a1[0]) / 2 - cx, (a0[1] + a1[1]) / 2 - cy
                m.quad("Props", P(*a0), P(*a1), P(*b1), P(*b0), _shade(COL["trunk_wood"], 0.9 + 0.2 * (k % 2)), (mx, 0, -my))
        prev = ring
    tx, ty, tz = x + lx, y + ly, h + ht
    _box(m, "Props", tx - 0.2, ty - 0.2, tx + 0.2, ty + 0.2, tz - 0.6, tz - 0.15, (0.3, 0.42, 0.12))     # coconuts
    n = 9
    for k in range(n):
        a = k * math.tau / n + r * 3.0
        col = _shade(LEAF, 0.85 + 0.3 * hsh(int(r * 1000), k))
        _frond(f, tx, ty, tz, a, 3.2 + r * 0.8, 0.9 + 0.3 * hsh(int(r * 997), k), col)
    for k in range(3):        # young upright fronds
        _frond(f, tx, ty, tz, k * 2.1 + r, 1.8, 0.1, _shade(LEAF, 1.15))


def _tree(m, f, x, y, h, r):
    """Broadleaf tree (mango / cotton tree style): trunk and a few clumped canopy blobs."""
    ht = 4.0 + r * 4.0
    _box(m, "Props", x - 0.22, y - 0.22, x + 0.22, y + 0.22, h, h + ht, COL["trunk_wood"])
    for k in range(4):
        a = k * 1.9 + r * 5
        d = 0 if k == 0 else 1.6
        _bush(f, x + math.cos(a) * d, y + math.sin(a) * d, h + ht - 0.6 + (k % 2) * 0.8, min(0.99, r + k * 0.1), 2.0 + r * 1.2)


def _bush(f, x, y, h, r, size=None):
    """Low-poly leafy clump (jittered double cone), sways a little."""
    s = size or (0.6 + r * 0.7)
    col = _shade((0.2, 0.42, 0.15), 0.85 + 0.3 * r)
    k = 8
    top = (x, y, h + s * 1.3)
    bot = (x, y, h + s * 0.1)
    ring = []
    for i in range(k):
        a = i * math.tau / k + r
        rr = s * (0.85 + 0.3 * hsh(int(r * 1000), i))
        ring.append((x + math.cos(a) * rr, y + math.sin(a) * rr, h + s * (0.55 + 0.2 * hsh(int(r * 999), i))))
    for i in range(k):
        a, b = ring[i], ring[(i + 1) % k]
        mx, my = (a[0] + b[0]) / 2 - x, (a[1] + b[1]) / 2 - y
        f.tri("Foliage", P(*a), P(*b), P(*top), col + (0.6,), (mx, 1, -my))
        f.tri("Foliage", P(*a), P(*b), P(*bot), _shade(col, 0.7) + (0.15,), (mx, -0.3, -my))


# ------------------------------------------------------------------ building detail
AWNING_COLS = [(0.78, 0.12, 0.16), (0.1, 0.35, 0.65), (0.12, 0.5, 0.3), (0.95, 0.7, 0.1), (0.9, 0.45, 0.1),
               (0.55, 0.15, 0.45), (0.85, 0.85, 0.82)]
SHOP_A = ["Mama Korto's", "Blessed Hands", "God's Time", "Small Small", "Peace Corner", "Ma Fatu", "Sweet Mother",
          "Johnson & Sons", "Big Boss", "Lucky Star", "Ducor View", "Grace", "Freeport", "Kru Town", "Sinkor Sunrise",
          "Tubman Corner", "Old Road", "Mesurado", "Lone Star", "Ma Musu", "Mr. Kollie", "Pepper Bush"]
SHOP_B = ["Cookshop", "Phone Repair", "Provisions", "Pharmacy", "Barber Shop", "Tailoring", "Hardware",
          "Mini Mart", "Electronics", "Beauty Salon", "Fashion", "Money Transfer", "Bakery", "Auto Parts",
          "Printing", "Furniture", "Video Club", "Cold Store", "Generator Repair", "Building Materials"]


def _obox(m, mat, cx, cy, ux, uy, hu, d0, d1, z0, z1, col):
    """Box aligned to a wall: centre (cx, cy) on the wall line, u = unit along the wall,
    n = (uy, -ux) outward; spans +-hu along u, d0..d1 outward, z0..z1 up."""
    nx_, ny_ = uy, -ux
    c = []
    for z in (z0, z1):
        for s, d in ((-hu, d0), (hu, d0), (hu, d1), (-hu, d1)):
            c.append(P(cx + ux * s + nx_ * d, cy + uy * s + ny_ * d, z))
    ng = lambda a, b: (a * ux + b * nx_, 0, -(a * uy + b * ny_))     # local (along, out) -> game direction
    m.quad(mat, c[4], c[5], c[6], c[7], col, (0, 1, 0))
    m.quad(mat, c[0], c[1], c[2], c[3], col, (0, -1, 0))
    for a, b, n in ((0, 1, ng(0, -1)), (1, 2, ng(1, 0)), (2, 3, ng(0, 1)), (3, 0, ng(-1, 0))):
        m.quad(mat, c[a], c[b], c[b + 4], c[a + 4], col, n)


def _cyl(m, mat, x, y, r, z0, z1, col, sides=10):
    pts = [(x + r * math.cos(k * math.tau / sides), y + r * math.sin(k * math.tau / sides)) for k in range(sides)]
    for k in range(sides):
        a, b = pts[k], pts[(k + 1) % sides]
        mx, my = (a[0] + b[0]) / 2 - x, (a[1] + b[1]) / 2 - y
        m.quad(mat, P(*a, z0), P(*b, z0), P(*b, z1), P(*a, z1), col, (mx, 0, -my))
        m.tri(mat, P(x, y, z1 + r * 0.25), P(*a, z1), P(*b, z1), col, (0, 1, 0))


def _shade(c, f):
    return tuple(min(1.0, v * f) for v in c)


def _inside(ring, x, y):
    ins = False
    for i in range(len(ring)):
        a, b = ring[i], ring[i - 1]
        if (a[1] > y) != (b[1] > y) and x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1] + 1e-12) + a[0]:
            ins = not ins
    return ins


def _pitched_roof(m, ring, top, col, bid):
    """Zinc roof with eaves overhanging the walls: a hip roof on rectangular houses, a
    shallow pyramid on other shapes. Underside of the eaves is dark timber."""
    o, pitch = 0.45, 0.32 + hsh(bid, 7) * 0.12
    under = (0.32, 0.24, 0.17)
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    rect = None
    if len(ring) == 4:
        e = [(ring[(i + 1) % 4][0] - ring[i][0], ring[(i + 1) % 4][1] - ring[i][1]) for i in range(4)]
        L = [math.hypot(*v) for v in e]
        if min(L) > 1.0:
            dot = abs(e[0][0] * e[1][0] + e[0][1] * e[1][1]) / (L[0] * L[1])
            if dot < 0.2:
                k = 0 if L[0] >= L[1] else 1
                ux, uy = e[k][0] / L[k], e[k][1] / L[k]
                rect = (ux, uy, (L[k] + L[k + 2]) / 4, (L[1 - k] + L[3 - k]) / 4)
    if rect:
        ux, uy, a, b = rect
        vx, vy = -uy, ux
        eave = top - o * pitch
        Q = lambda su, sv: P(cx + ux * su * (a + o) + vx * sv * (b + o), cy + uy * su * (a + o) + vy * sv * (b + o), eave)
        rl = max(a - b, 0.0)
        rh = top + b * pitch
        R = lambda su: P(cx + ux * su * rl, cy + uy * su * rl, rh)
        if rl > 0.01:
            m.quad("Roof", Q(-1, 1), Q(1, 1), R(1), R(-1), col, (0, 1, 0))
            m.quad("Roof", Q(1, -1), Q(-1, -1), R(-1), R(1), col, (0, 1, 0))
        else:
            m.tri("Roof", Q(-1, 1), Q(1, 1), R(1), col, (0, 1, 0))
            m.tri("Roof", Q(1, -1), Q(-1, -1), R(-1), col, (0, 1, 0))
        m.tri("Roof", Q(1, 1), Q(1, -1), R(1), col, (0, 1, 0))
        m.tri("Roof", Q(-1, -1), Q(-1, 1), R(-1), col, (0, 1, 0))
        m.quad("Roof", Q(-1, -1), Q(1, -1), Q(1, 1), Q(-1, 1), under, (0, -1, 0))
        return
    rmin = min(math.hypot(p[0] - cx, p[1] - cy) for p in ring)
    eave = top - o * pitch
    apex = P(cx, cy, top + min(rmin, 6.0) * pitch)
    q = []
    for x, y in ring:
        d = math.hypot(x - cx, y - cy) or 1.0
        q.append((x + (x - cx) / d * o, y + (y - cy) / d * o))
    for i in range(len(q)):
        a, b = q[i], q[(i + 1) % len(q)]
        m.tri("Roof", P(*a, eave), P(*b, eave), apex, col, (0, 1, 0))
    for i0, i1, i2 in earclip(q):
        m.tri("Roof", P(*q[i0], eave), P(*q[i1], eave), P(*q[i2], eave), under, (0, -1, 0))


def _flat_roof(m, d, ring, top, col, wall, bid):
    """Concrete roof slab with a parapet, and the usual roof clutter: black poly water
    tanks on stands, a stair housing, sometimes a satellite dish."""
    for i0, i1, i2 in earclip(ring):
        m.tri("Roof", P(*ring[i0], top), P(*ring[i1], top), P(*ring[i2], top), col, (0, 1, 0))
    ph, pt = 0.85, 0.22
    cap = _shade(wall, 0.92)
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        if L < 0.3:
            continue
        ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        _obox(d, "Props", (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, ux, uy, L / 2, -pt, 0.03, top, top + ph, cap)
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    area = polygon_area(ring)
    r = hsh(bid, 11)
    spots = [(cx, cy)]
    rmin = min(math.hypot(p[0] - cx, p[1] - cy) for p in ring)
    if rmin > 4.0:
        spots += [(cx + rmin * 0.5, cy), (cx - rmin * 0.5, cy + rmin * 0.3)]
    tanks = 1 + int(r * 2.2) if area > 60 else 0
    for k in range(min(tanks, len(spots))):
        x, y = spots[k]
        if not _inside(ring, x, y):
            continue
        rad = 0.7 + hsh(bid, 13 + k) * 0.35
        _box(d, "Props", x - rad, y - rad, x + rad, y + rad, top, top + 1.1, (0.38, 0.38, 0.4))        # steel stand
        _cyl(d, "Props", x, y, rad, top + 1.1, top + 1.1 + rad * 2.0, (0.08, 0.08, 0.09))           # poly tank
    if area > 150 and rmin > 3.0:
        sx, sy = cx - rmin * 0.45, cy - rmin * 0.35
        if _inside(ring, sx, sy):
            _box(d, "Props", sx - 1.3, sy - 1.6, sx + 1.3, sy + 1.6, top, top + 2.6, _shade(wall, 0.95))  # stair housing
    if r > 0.7 and rmin > 2.0:
        x, y = cx + rmin * 0.4, cy + rmin * 0.4
        if _inside(ring, x, y):
            _box(d, "Props", x - 0.04, y - 0.04, x + 0.04, y + 0.04, top, top + 1.2, (0.3, 0.3, 0.3))
            _cyl(d, "Props", x, y, 0.45, top + 1.2, top + 1.25, (0.9, 0.9, 0.9), 8)


def _wall_details(m, d, meta_t, ring, base, top, levels, wall, bid, commercial, city, road_mask, RM):
    """Per wall: floor ledges, AC units, balconies; street-facing ground floors of
    commercial buildings get a shopfront (dark glass, awning, signboard with a made-up
    name in the tile meta)."""
    ledge = _shade(wall, 0.85)
    floors = max(1, int(round((top - base - 0.7) / 3.2)))
    shop_done = 0
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        if L < 2.5:
            continue
        ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        nx_, ny_ = uy, -ux
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        g = city.hm(mx, my)
        # does this wall face a street?
        rr = int((my + ny_ * 7.0 - city.ymin) / RM)
        cc = int((mx + nx_ * 7.0 - city.xmin) / RM)
        street = 0 <= rr < road_mask.shape[0] and 0 <= cc < road_mask.shape[1] and bool(road_mask[rr, cc])
        # floor ledges / window sills
        if floors >= 2 and L > 3.0:
            for f in range(1, floors):
                z = base + 0.4 + f * 3.2
                if z < top - 0.5:
                    _obox(d, "Props", mx, my, ux, uy, L / 2, 0.0, 0.16, z - 0.05, z + 0.1, ledge)
        # balconies on residential upper floors facing the street
        if floors >= 2 and street and not commercial and L > 5.0 and hsh(bid, i, 3) < 0.55:
            w = min(L * 0.45, 4.5)
            for f in range(1, floors):
                z = base + 0.4 + f * 3.2
                if z + 1.1 > top:
                    break
                _obox(d, "Props", mx, my, ux, uy, w / 2, 0.0, 1.1, z - 0.15, z, ledge)                      # slab
                _obox(d, "Props", mx, my, ux, uy, w / 2, 1.0, 1.1, z, z + 1.0, _shade(wall, 1.05))          # balustrade
                for s in (-1, 1):
                    _obox(d, "Props", mx + ux * s * (w / 2 - 0.05), my + uy * s * (w / 2 - 0.05), ux, uy, 0.05, 0.0, 1.0, z, z + 1.0, _shade(wall, 1.05))
        # AC units (split-system outdoor boxes) hung under windows
        if L > 4.0:
            for f in range(floors):
                if hsh(bid, i, f, 5) < 0.18:
                    s = (hsh(bid, i, f, 6) - 0.5) * (L - 2.0)
                    z = base + 0.4 + f * 3.2 + 1.0 + (0.0 if f else 1.2)
                    if z + 0.6 > top:
                        continue
                    _obox(d, "Props", mx + ux * s, my + uy * s, ux, uy, 0.42, 0.0, 0.32, z, z + 0.55, (0.86, 0.86, 0.84))
                    _obox(d, "Props", mx + ux * s, my + uy * s, ux, uy, 0.28, 0.32, 0.34, z + 0.08, z + 0.47, (0.2, 0.2, 0.22))
        # shopfront
        if commercial and street and L > 5.0 and shop_done < 2 and top - base > 3.6:
            shop_done += 1
            w = min(L - 1.0, 9.0)
            gz = g
            _obox(d, "Props", mx, my, ux, uy, w / 2, 0.0, 0.06, gz + 0.2, gz + 2.7, (0.1, 0.13, 0.16))           # glass / shutters
            ac = AWNING_COLS[int(hsh(bid, i, 9) * len(AWNING_COLS))]
            z0, z1, depth = gz + 2.75, gz + 3.15, 1.8
            # sloped awning, double sided
            p0 = P(mx - ux * w / 2, my - uy * w / 2, z1)
            p1 = P(mx + ux * w / 2, my + uy * w / 2, z1)
            p2 = P(mx + ux * w / 2 + nx_ * depth, my + uy * w / 2 + ny_ * depth, z0)
            p3 = P(mx - ux * w / 2 + nx_ * depth, my - uy * w / 2 + ny_ * depth, z0)
            d.quad("Props", p0, p1, p2, p3, ac, (0, 1, 0))
            d.quad("Props", p0, p1, p2, p3, _shade(ac, 0.6), (0, -1, 0))
            _obox(d, "Props", mx, my, ux, uy, w / 2, depth - 0.02, depth + 0.02, z0 - 0.25, z0, _shade(ac, 0.8))     # valance
            # signboard above the awning
            sb = (0.95, 0.95, 0.92) if hsh(bid, i, 10) < 0.5 else AWNING_COLS[int(hsh(bid, i, 12) * len(AWNING_COLS))]
            if gz + 4.1 < top:
                _obox(d, "Props", mx, my, ux, uy, w * 0.42, 0.0, 0.12, gz + 3.25, gz + 4.05, sb)
                name = SHOP_A[int(hsh(bid, i, 14) * len(SHOP_A))] + " " + SHOP_B[int(hsh(bid, i, 15) * len(SHOP_B))]
                dark = sum(sb) < 1.6
                meta_t["shops"].append([round(mx + nx_ * 0.14, 2), round(gz + 3.65, 2), round(-(my + ny_ * 0.14), 2),
                                        round(math.atan2(nx_, -ny_), 3), round(w * 0.8, 2), name, 1 if dark else 0])


def _box(m, mat, x0, y0, x1, y1, z0, z1, col):
    c = [P(x0, y0, z0), P(x1, y0, z0), P(x1, y1, z0), P(x0, y1, z0), P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)]
    m.quad(mat, c[4], c[5], c[6], c[7], col, (0, 1, 0))
    for a, b, n in ((0, 1, (0, 0, 1)), (1, 2, (1, 0, 0)), (2, 3, (0, 0, -1)), (3, 0, (-1, 0, 0))):
        m.quad(mat, c[a], c[b], c[b + 4], c[a + 4], col, n)


if __name__ == "__main__":
    main()
