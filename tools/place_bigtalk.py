"""
Monrovia Life - picks the real map spots for the Big Talk Dweh storyline.

Big Talk Dweh is an ORIGINAL fictional character (not based on any real person). This
script only chooses where his things go on the real OpenStreetMap-based city:

  crate        his crate and loudspeaker near Auntie Musu at Waterside
  posters      6 shopfront walls downtown (his first poster job)
  city_posters 60 shopfront walls all over the city (stage 4: "posters cover the city")
  billboard    roadside spot in Sinkor, facing a main road
  rally        open ground in Sinkor for his rallies
  crew         where the rival poster crew works (stage 3)
  house        an open plot of at least 46 x 46 m in Sinkor or Mamba Point, with no
               buildings or roads on it, next to a named street (his walled house)
  statue       next to the billboard (ending: Senator Dweh)

Needs the generated city (tools/build_osm_city.py) for the tile meta.
Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\5.3\\python\\bin\\python.exe" -I tools\\place_bigtalk.py
Out:  proto3d/game/data/bigtalk_spots.json
"""
import glob
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_osm_city as B  # noqa: E402  (reuses the projection, terrain and OSM reader)
import numpy as np  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
CITY = os.path.join(ROOT, "proto3d", "city")
OUT = os.path.join(ROOT, "proto3d", "game", "data", "bigtalk_spots.json")


def place(pid):
    d = json.load(open(os.path.join(CITY, "places.json"), encoding="utf-8"))
    for p in d["poi"] + d["dest"]:
        if p.get("id") == pid:
            return p["pos"]
    raise KeyError(pid)


def main():
    metas = {}
    for f in glob.glob(os.path.join(CITY, "meta", "*.json")):
        metas[os.path.basename(f)] = json.load(open(f, encoding="utf-8"))
    shops = [s for m in metas.values() for s in m.get("shops", [])]
    poles = [s for m in metas.values() for s in m.get("poles", [])]
    grass = [s for m in metas.values() for s in m.get("grass", [])]
    d2 = lambda a, b: (a[0] - b[0]) ** 2 + (a[2] - b[2]) ** 2

    auntie = place("auntie")
    sinkor = place("sinkor")
    # posters: shopfront walls, a little below the signboard (on the shutters)
    def poster(s):
        return [s[0], round(s[1] - 1.55, 2), s[2], s[3]]
    near = sorted(shops, key=lambda s: d2(s, auntie))
    picked = []
    for s in near:
        if all(d2(s, p) > 60 ** 2 for p in picked):
            picked.append(s)
        if len(picked) == 6:
            break
    city = []
    for s in sorted(shops, key=lambda s: B.hsh(int(s[0] * 10), int(s[2] * 10))):
        if all(d2(s, p) > 90 ** 2 for p in city):
            city.append(s)
        if len(city) == 60:
            break
    # billboard: beside a street-light pole in Sinkor, set back from the road, facing it
    pole = min(poles, key=lambda p: d2(p, sinkor))
    yaw = pole[3]
    back = (math.sin(yaw) * 4.0, math.cos(yaw) * 4.0)     # away from the road (arm points to the road)
    billboard = [round(pole[0] + back[0], 2), pole[1], round(pole[2] + back[1], 2), round(yaw, 3)]
    statue = [round(billboard[0] + math.cos(yaw) * 9.0, 2), billboard[1], round(billboard[2] - math.sin(yaw) * 9.0, 2), round(yaw, 3)]
    # rally ground: the green spot near Sinkor with the most green neighbours
    cand = [g for g in grass if d2(g, sinkor) < 600 ** 2]
    best = max(cand[:4000], key=lambda g: sum(1 for h in cand if d2(g, h) < 15 ** 2))
    rally = [best[0], best[1], best[2]]
    crew = picked[3]
    # the house plot: open land (no buildings, roads or water) near a named street
    print("loading the city to find an open plot...")
    city_ = B.City()
    cell = 2.0
    ny, nx = int((city_.ymax - city_.ymin) / cell) + 1, int((city_.xmax - city_.xmin) / cell) + 1
    blocked = np.zeros((ny, nx), bool)
    named = []
    for el in city_.osm:
        t = el.get("tags", {})
        if el["type"] != "way":
            continue
        g = city_.geom(el)
        if "building" in t and len(g) >= 3:
            B.fill_polygon(blocked, g, True, city_.xmin, city_.ymin, cell)
        elif t.get("highway") in B.ROAD_W:
            w = B.ROAD_W[t["highway"]]
            for a, b in zip(g, g[1:]):
                B.draw_line(blocked, a, b, True, city_.xmin, city_.ymin, cell, thick=int(w / cell / 2) + 2)
            if t.get("name"):
                named.append((t["name"], g))
    half = 23.0
    k = int(half / cell)
    best_plot = None
    for anchor_id in ("sinkor", "mamba_point"):
        a = place(anchor_id)
        ax, ay = a[0], -a[2]
        for r in range(0, 900, 8):
            for ang in range(0, 360, 10):
                x = ax + math.cos(math.radians(ang)) * r
                y = ay + math.sin(math.radians(ang)) * r
                rr, cc = int((y - city_.ymin) / cell), int((x - city_.xmin) / cell)
                if not (k <= rr < ny - k and k <= cc < nx - k):
                    continue
                if blocked[rr - k:rr + k + 1, cc - k:cc + k + 1].any():
                    continue
                if any(city_.is_water(x + dx, y + dy) for dx in (-half, half) for dy in (-half, half)):
                    continue
                hs = [city_.hm(x + dx, y + dy) for dx in (-half, 0, half) for dy in (-half, 0, half)]
                if max(hs) - min(hs) > 2.5:
                    continue
                # nearest named street within 45 m (the gate faces it)
                bestd, bname, bpt = 1e9, None, None
                for name, g in named:
                    for p in g[::2]:
                        dd = (p[0] - x) ** 2 + (p[1] - y) ** 2
                        if dd < bestd:
                            bestd, bname, bpt = dd, name, p
                if bestd > 45 ** 2:
                    continue
                best_plot = (x, y, bname, bpt, anchor_id)
                break
            if best_plot:
                break
        if best_plot:
            break
    if best_plot is None:
        raise SystemExit("no open plot found")
    x, y, street, sp, anchor = best_plot
    house = {"pos": [round(x, 2), round(min(city_.hm(x + dx, y + dy) for dx in (-half, half) for dy in (-half, half)), 2), round(-y, 2)],
             "yaw": round(math.atan2(-(sp[0] - x), (sp[1] - y)), 3), "street": street, "area": anchor,
             "lat_lon": [round(v, 6) for v in B.utm_inv(x + city_.E0, y + city_.N0)]}
    out = {"_comment": "Generated by tools/place_bigtalk.py: real map spots for the (fictional) Big Talk Dweh story. Game coordinates.",
           "crate": [round(auntie[0] + 18.0, 2), auntie[1], round(auntie[2] + 6.0, 2)],
           "posters": [poster(s) for s in picked], "city_posters": [poster(s) for s in city],
           "billboard": billboard, "statue": statue, "rally": rally, "crew": poster(crew), "house": house}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w", encoding="utf-8"), indent=1)
    print("house plot: %s, off %s, at %s" % (anchor, street, house["pos"]))
    print("billboard", billboard, "rally", rally)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
