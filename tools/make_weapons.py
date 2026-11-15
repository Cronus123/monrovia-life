"""
Monrovia Life - builds the hand-held weapons (proto3d/models/weapons/<id>.glb) and their
HUD icons (proto3d/ui/weapons/<id>.png).

Guns are from Quaternius's "Ultimate Gun Pack" (CC0 1.0, third_party/quaternius-ultimate-gun-pack):
re-scaled to real size, turned so the barrel points along glTF -Z (the hand's forward in
the game), with the origin at the grip and an empty called "muzzle" at the barrel's end.
The baseball bat and the machete are modelled here in the same low-poly style.

Run:  blender -b -P tools/make_weapons.py
"""
import bmesh
import bpy
import math
import os
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
PACK = os.path.join(ROOT, "third_party", "quaternius-ultimate-gun-pack", "FBX")
OUT = os.path.join(ROOT, "proto3d", "models", "weapons")
ICONS = os.path.join(ROOT, "proto3d", "ui", "weapons")

GUNS = {  # id: (source, real length in metres)
    "pistol": ("Pistol_1", 0.21),
    "smg": ("SubmachineGun_1", 0.48),
    "shotgun": ("Shotgun_1", 1.0),
}


def mat(name, hexcol, rough=0.6, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    h = hexcol.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = c
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = c
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bounds(obs):
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in obs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def flatten():
    """Apply every transform and drop empties, so all geometry is in world space."""
    obs = meshes()
    for o in obs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.context.scene.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    for o in obs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    return obs


def gun(gid, src, length):
    reset()
    bpy.ops.import_scene.fbx(filepath=os.path.join(PACK, src + ".fbx"))
    obs = flatten()
    lo, hi = bounds(obs)
    size = hi - lo
    axis = max(range(3), key=lambda i: size[i])          # the barrel runs along the longest axis
    up = 2 if axis != 2 else 1
    # handle = the lowest third of the gun; the muzzle is the far end from it
    pts = [v.co.copy() for o in obs for v in o.data.vertices]
    low = [p for p in pts if p[up] < lo[up] + size[up] * 0.35]
    hc = sum((p[axis] for p in low), 0.0) / max(1, len(low))
    mid = (lo[axis] + hi[axis]) / 2
    sign = 1.0 if hc < mid else -1.0                       # muzzle direction along `axis`
    # rotate: barrel -> +Y (glTF -Z), up -> +Z
    fwd = Vector((0, 0, 0))
    fwd[axis] = sign
    upv = Vector((0, 0, 0))
    upv[up] = 1.0
    side = fwd.cross(upv)
    R = Matrix((side, fwd, upv)).to_4x4()                  # rows: new x, y, z in old coords
    s = length / size[axis]
    for o in obs:
        o.data.transform(Matrix.Scale(s, 4) @ R)
    lo, hi = bounds(obs)
    # grip point: top of the handle, a third along from the back
    grip = Vector(((lo.x + hi.x) / 2, lo.y + (hi.y - lo.y) * (0.22 if gid == "pistol" else 0.3), lo.z + (hi.z - lo.z) * 0.55))
    for o in obs:
        o.data.transform(Matrix.Translation(-grip))
    lo, hi = bounds(obs)
    bpy.ops.object.empty_add(location=(0, hi.y + 0.01, (lo.z + hi.z) / 2 + (hi.z - lo.z) * 0.25))
    bpy.context.object.name = "muzzle"
    for o in obs:
        for slot in o.material_slots:
            if slot.material is not None:
                b = slot.material.node_tree.nodes.get("Principled BSDF") if slot.material.use_nodes else None
                if b is not None:
                    b.inputs["Roughness"].default_value = 0.45
                    b.inputs["Metallic"].default_value = 0.4
                    # the FBX materials come in with alpha 0: make them solid
                    for link in list(b.inputs["Alpha"].links):
                        slot.material.node_tree.links.remove(link)
                    b.inputs["Alpha"].default_value = 1.0
                if hasattr(slot.material, "surface_render_method"):
                    slot.material.surface_render_method = "DITHERED"
                if hasattr(slot.material, "blend_method"):
                    slot.material.blend_method = "OPAQUE"
    export(gid)


def bat():
    reset()
    wood = mat("Wood", "#b5824a", 0.7)
    tape = mat("Tape", "#1b1b1b", 0.9)
    bm = bmesh.new()
    rings = [(-0.1, 0.022), (0.0, 0.016), (0.18, 0.017), (0.45, 0.028), (0.7, 0.034), (0.76, 0.03)]
    segs = 12
    prev = None
    for y, r in rings:
        ring = [bm.verts.new((r * math.cos(a * math.tau / segs), y, r * math.sin(a * math.tau / segs))) for a in range(segs)]
        if prev:
            for i in range(segs):
                bm.faces.new((prev[i], prev[(i + 1) % segs], ring[(i + 1) % segs], ring[i]))
        else:
            bm.faces.new(list(reversed(ring)))
        prev = ring
    bm.faces.new(prev)
    me = bpy.data.meshes.new("bat")
    bm.to_mesh(me)
    me.materials.append(wood)
    ob = bpy.data.objects.new("bat", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.019, depth=0.2, location=(0, 0.04, 0), rotation=(math.pi / 2, 0, 0), vertices=12)
    bpy.context.object.data.materials.append(tape)
    bpy.ops.object.empty_add(location=(0, 0.72, 0))
    bpy.context.object.name = "muzzle"                    # the hitting end
    export("bat")


def machete():
    reset()
    steel = mat("Steel", "#c9ccd1", 0.25, 0.9)
    handle = mat("Handle", "#3a2a1c", 0.8)
    bm = bmesh.new()
    pts = [(0.0, 0.1), (0.0, 0.55), (0.03, 0.6), (0.05, 0.58), (0.045, 0.12), (0.03, 0.1)]
    t = 0.004
    top = [bm.verts.new((x - 0.02, y, t)) for x, y in pts]
    bot = [bm.verts.new((x - 0.02, y, -t)) for x, y in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((top[i], top[j], bot[j], bot[i]))
    me = bpy.data.meshes.new("blade")
    bm.to_mesh(me)
    me.materials.append(steel)
    ob = bpy.data.objects.new("blade", me)
    bpy.context.scene.collection.objects.link(ob)
    # blade lies in the X/Y plane: stand it up (edge down) so it swings like a blade
    ob.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.02, 0))
    h = bpy.context.object
    h.scale = (0.025, 0.16, 0.035)
    h.data.materials.append(handle)
    bpy.ops.object.empty_add(location=(0, 0.55, 0))
    bpy.context.object.name = "muzzle"
    export("machete")


def export(gid):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, gid + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes():
        o.select_set(True)
    if meshes():
        bpy.context.view_layer.objects.active = meshes()[0]
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    icon(gid)
    print("exported %-8s %.0f KB" % (gid, os.path.getsize(path) / 1024))


def icon(gid):
    """Side-view silhouette icon (white, transparent background) for the HUD and wheel."""
    os.makedirs(ICONS, exist_ok=True)
    scene = bpy.context.scene
    lo, hi = bounds(meshes())
    c = (lo + hi) / 2
    span = max(hi.y - lo.y, (hi.z - lo.z) * 2.0) * 1.15
    bpy.ops.object.camera_add(location=(c.x + 3.0, c.y, c.z), rotation=(math.pi / 2, 0, math.pi / 2))
    cam = bpy.context.object
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = span
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "SINGLE"
    scene.display.shading.single_color = (1, 1, 1)
    scene.render.film_transparent = True
    scene.render.resolution_x = 256
    scene.render.resolution_y = 128
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = os.path.join(ICONS, gid + ".png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


for g, (src, length) in GUNS.items():
    gun(g, src, length)
bat()
machete()
reset()
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(0, 0, 0))     # fists icon: a simple fist shape
bpy.ops.mesh.primitive_cube_add(size=0.09, location=(0, 0.03, 0.02))
icon("fists")
