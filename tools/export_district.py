"""
Monrovia Life - export one district of the Blender city to glTF for the 3D prototype.

Opens blender/monrovia_city.blend (made by build_city.py), keeps the Downtown /
Mamba Point / Waterside / Capitol Hill area, centres it on the origin and writes
    proto3d/models/district_downtown.glb
plus three drivable vehicle models (built with make_sprites.py):
    proto3d/models/veh_taxi.glb, veh_car.glb, veh_police.glb

Run (from the project folder):
    blender -b blender/monrovia_city.blend -P tools/export_district.py

Notes
- Objects named "<name>-col" make Godot's importer add trimesh collision.
- Materials are flattened to their base colour (glTF can't carry Blender's
  procedural node setups); the game re-adds windows with a shader.
- The district is cut on tile bounds; terrain and roads are bisected, buildings,
  trees and stalls are kept or dropped whole.
"""
import bpy
import bmesh
import os
import sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT = os.path.join(ROOT, "proto3d", "models")
os.makedirs(OUT, exist_ok=True)
sys.path.insert(0, HERE)
import make_sprites as ms  # noqa: E402  (guarded: importing does not render)

T = 4.0  # metres per map tile (same as build_city.py)
# District bounds in map tiles (x east, y south). Blender: X = x*T, Y = -y*T.
TX0, TX1, TY0, TY1 = 12, 82, 40, 78
X0, X1 = TX0 * T, TX1 * T
Y0, Y1 = -TY1 * T, -TY0 * T
CX, CY = (X0 + X1) / 2, (Y0 + Y1) / 2

BISECT = {"Terrain", "Roads"}            # cut geometry on the bounds
ISLANDS = {"Buildings", "Landmarks", "MarketStalls", "Trees"}  # keep/drop whole pieces
COLLIDE = {"Terrain", "Roads", "Buildings", "Landmarks", "MarketStalls"}
OCEAN_PAD = 700.0


def flatten_materials():
    """Make every material's glTF colour its plain base colour."""
    for m in bpy.data.materials:
        nt = m.node_tree
        if nt is None:
            continue
        b = nt.nodes.get("Principled BSDF")
        if b is None:
            continue
        inp = b.inputs["Base Color"]
        for link in list(inp.links):
            nt.links.remove(link)
        inp.default_value = m.diffuse_color


def bisect_box(bm, x0, x1, y0, y1):
    for co, no in (((x0, 0, 0), (-1, 0, 0)), ((x1, 0, 0), (1, 0, 0)),
                   ((0, y0, 0), (0, -1, 0)), ((0, y1, 0), (0, 1, 0))):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-4, plane_co=co, plane_no=no, clear_outer=True)


def drop_islands(bm, x0, x1, y0, y1):
    bm.verts.ensure_lookup_table()
    seen = set()
    kill = []
    for v in bm.verts:
        if v.index in seen:
            continue
        seen.add(v.index)
        stack, island = [v], []
        while stack:
            a = stack.pop()
            island.append(a)
            for e in a.link_edges:
                o = e.other_vert(a)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        c = sum((x.co for x in island), Vector()) / len(island)
        if not (x0 <= c.x <= x1 and y0 <= c.y <= y1):
            kill.extend(island)
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="VERTS")


def export_glb(path):
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                  export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_lights")
        bpy.ops.export_scene.gltf(**kwargs)
    print("exported", path, "%.1f KB" % (os.path.getsize(path) / 1024))


def export_district():
    flatten_materials()
    keep = []
    for ob in list(bpy.data.objects):
        name = ob.name
        if ob.type != "MESH" or name not in BISECT | ISLANDS | {"Atlantic"}:
            bpy.data.objects.remove(ob, do_unlink=True)
            continue
        me = ob.data
        bm = bmesh.new()
        bm.from_mesh(me)
        if name in BISECT:
            bisect_box(bm, X0, X1, Y0, Y1)
        elif name in ISLANDS:
            drop_islands(bm, X0, X1, Y0, Y1)
        else:  # Atlantic: keep a wide sheet of sea around the district
            bisect_box(bm, X0 - OCEAN_PAD, X1 + OCEAN_PAD, Y0 - OCEAN_PAD, Y1 + OCEAN_PAD)
        bm.to_mesh(me)
        bm.free()
        me.transform(Matrix.Translation((-CX, -CY, 0.0)))
        me.update()
        if name in COLLIDE:
            ob.name = name + "-col"
        keep.append(ob)
        print("%-14s %7d verts" % (ob.name, len(me.vertices)))
    bpy.ops.object.select_all(action="DESELECT")
    for ob in keep:
        ob.select_set(True)
    export_glb(os.path.join(OUT, "district_downtown.glb"))


def export_roads():
    """Road centrelines near the district, in Godot coordinates, for street dressing
    (sidewalks, crosswalks, lamps, poles, signs) and pedestrian paths."""
    import json
    with open(os.path.join(ROOT, "blender", "monrovia_map.json")) as f:
        roads = json.load(f)["roads"]
    out = []
    for i, r in enumerate(roads):
        pts = r["p"]
        if not any(TX0 - 6 <= x <= TX1 + 6 and TY0 - 6 <= y <= TY1 + 6 for x, y in pts):
            continue
        out.append({"id": i, "name": r["n"], "width": r["w"] * T,
                    "points": [[round(x * T - CX, 3), round(y * T + CY, 3)] for x, y in pts]})
    half = [(X1 - X0) / 2, (Y1 - Y0) / 2]
    path = os.path.join(ROOT, "proto3d", "data", "roads.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"tile": T, "half_extent": half, "roads": out}, f, indent=1)
    print("wrote", path, len(out), "roads")


def export_vehicles():
    for kind in ("taxi", "car", "police", "keke", "suv", "sport", "truck", "van"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if kind == "car":
            ms.sedan(ms.srgb("#c8173a"))
        elif kind == "sport":
            ms.sedan(ms.srgb("#c8173a"), L=4.5, Wd=1.95, H=0.55, cabin_len=2.0, cabin_x=-0.45, low=True)
        else:
            ms.VEHICLES[kind]()
        flatten_materials()
        for ob in bpy.context.scene.objects:
            ob.select_set(True)
        export_glb(os.path.join(OUT, "veh_%s.glb" % kind))


print("district bounds (Blender m): X %.0f..%.0f  Y %.0f..%.0f  centre (%.0f, %.0f)" % (X0, X1, Y0, Y1, CX, CY))
export_roads()
export_district()
export_vehicles()
print("EXPORT DONE")
