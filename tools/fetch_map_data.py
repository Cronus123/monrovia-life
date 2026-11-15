"""
Downloads the real-world map data for the 1:1 central Monrovia map.

- OpenStreetMap features (roads, buildings, water, coastline, land use, named places)
  for the bounding box below, from the official Overpass API instance (overpass-api.de).
  Licence: ODbL 1.0, "(c) OpenStreetMap contributors". Map data derived from it is
  share-alike (ODbL).
- Elevation: "Terrain Tiles" on AWS Open Data (Terrarium PNG encoding; SRTM-derived
  in this area), zoom 13, covering the same box.

Output: data/osm/monrovia_central.json, data/dem/terrarium_13_<x>_<y>.png, data/bbox.json

Run with any Python 3 that has working TLS (Blender's bundled Python works):
    "C:\\Program Files\\Blender Foundation\\Blender 5.3\\5.3\\python\\bin\\python.exe" -I tools\\fetch_map_data.py
or simply:  powershell -ExecutionPolicy Bypass -File tools\\fetch_map_data.ps1
"""
import json
import math
import os
import urllib.parse
import urllib.request

# Mamba Point (west) to Congo Town (east); Atlantic (south) to the Mesurado / Bushrod shore (north)
S, W, N, E = 6.262, -10.815, 6.330, -10.735
DEM_ZOOM = 13
UA = {"User-Agent": "MonroviaLife-mapbuilder/1.0 (game map generator)"}

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OSM_DIR = os.path.join(ROOT, "data", "osm")
DEM_DIR = os.path.join(ROOT, "data", "dem")

QUERY = f"""[out:json][timeout:300][bbox:{S},{W},{N},{E}];
(
  way[highway];
  way[building]; relation[building];
  way[natural]; relation[natural];
  way[landuse]; relation[landuse];
  way[leisure]; relation[leisure];
  way[waterway]; relation[waterway];
  way[amenity]; node[amenity][name];
  way[aeroway];
  way[man_made];
  way[tourism]; node[tourism][name];
  way[historic]; node[historic][name];
  node[place][name];
);
out geom;
"""


def fetch(url, out, data=None, tries=4):
    import time
    headers = dict(UA, Accept="*/*")
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers=headers)
            with urllib.request.urlopen(req, timeout=600) as r, open(out, "wb") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
            print("  %.1f MB -> %s" % (os.path.getsize(out) / 1e6, out))
            return
        except urllib.error.HTTPError as e:
            if attempt == tries - 1 or e.code not in (429, 502, 503, 504):
                raise
            wait = 20 * (attempt + 1)
            print("  HTTP %d, retrying in %d s" % (e.code, wait))
            time.sleep(wait)


def tile_x(lon, z):
    return int((lon + 180.0) / 360.0 * 2 ** z)


def tile_y(lat, z):
    r = math.radians(lat)
    return int((1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) / 2.0 * 2 ** z)


def main():
    os.makedirs(OSM_DIR, exist_ok=True)
    os.makedirs(DEM_DIR, exist_ok=True)
    print("Overpass query for", S, W, N, E)
    fetch("https://overpass-api.de/api/interpreter", os.path.join(OSM_DIR, "monrovia_central.json"),
          urllib.parse.urlencode({"data": QUERY}).encode())
    z = DEM_ZOOM
    for x in range(tile_x(W, z), tile_x(E, z) + 1):
        for y in range(tile_y(N, z), tile_y(S, z) + 1):
            fetch(f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png",
                  os.path.join(DEM_DIR, f"terrarium_{z}_{x}_{y}.png"))
    with open(os.path.join(ROOT, "data", "bbox.json"), "w") as f:
        json.dump({"south": S, "west": W, "north": N, "east": E, "dem_zoom": z}, f, indent=1)
    print("done")


if __name__ == "__main__":
    main()
