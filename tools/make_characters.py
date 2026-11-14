"""
Monrovia Life - rigged low-poly humanoid for the 3D game.

Builds one character in Blender: an armature (hips, spine, chest, neck, head, arms,
legs, feet) and low-poly body parts rigidly skinned to it, with clothing as separate
mesh objects so the game can mix outfits and colours per character:

    Skin, Shirt, Trousers, Shoes, Hair, Skirt (lappa), HeadWrap, Cap

Each part has one material with the same name; Godot recolours and shows/hides them.
Animations (idle, walk, run, jump, get-in, knocked down) are built in Godot from the
bone layout below, so this file only exports the rest pose.

Bone frames: every limb/spine bone has its local Z axis pointing forward (+Y in
Blender, -Z in Godot), so a positive rotation about the bone's local X axis always
swings the part forward (legs, arms, spine lean, elbows) and a negative one bends
knees back.

Run:  blender -b -P tools/make_characters.py
Out:  proto3d/models/character.glb
"""
import bpy
import bmesh
import math
import os
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "proto3d", "models", "character.glb"))

# name: (head, tail, parent)   metres, Blender Z up, character faces +Y
BONES = {
    "hips": ((0, 0, 0.93), (0, 0, 1.04), None),
    "spine": ((0, 0, 1.04), (0, 0, 1.30), "hips"),
    "chest": ((0, 0, 1.30), (0, 0, 1.49), "spine"),
    "neck": ((0, 0, 1.49), (0, 0, 1.57), "chest"),
    "head": ((0, 0, 1.57), (0, 0, 1.80), "neck"),
}
for side, sx in (("l", 1), ("r", -1)):
    BONES.update({
        "upper_arm.%s" % side: ((0.205 * sx, 0, 1.45), (0.225 * sx, 0, 1.17), "chest"),
        "forearm.%s" % side: ((0.225 * sx, 0, 1.17), (0.235 * sx, 0, 0.93), "upper_arm.%s" % side),
        "hand.%s" % side: ((0.235 * sx, 0, 0.93), (0.235 * sx, 0, 0.83), "forearm.%s" % side),
        "thigh.%s" % side: ((0.098 * sx, 0, 0.93), (0.098 * sx, 0, 0.51), "hips"),
        "shin.%s" % side: ((0.098 * sx, 0, 0.51), (0.098 * sx, 0, 0.09), "thigh.%s" % side),
        "foot.%s" % side: ((0.098 * sx, 0, 0.09), (0.098 * sx, 0.13, 0.03), "shin.%s" % side),
    })

PART_COLORS = {  # placeholder colours; Godot recolours per character
    "Skin": "#6b4329", "Shirt": "#c8173a", "Trousers": "#2b3a55", "Shoes": "#1b1b1b",
    "Hair": "#151210", "Skirt": "#ef7d22", "HeadWrap": "#1aa39e", "Cap": "#14213d",
}


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)


def material(name):
    m = bpy.data.materials.new(name)
    col = srgb(PART_COLORS[name])
    m.diffuse_color = col
    b = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
    if b is not None:
        b.inputs["Base Color"].default_value = col
        b.inputs["Roughness"].default_value = 0.8
    return m


class Part:
    """Collects geometry for one clothing/body object, with one vertex group per bone."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.groups = {}       # bone -> list of vert indices (filled at the end)
        self._vert_bone = []

    def _tag(self, verts, bone):
        for v in verts:
            self._vert_bone.append((v, bone))

    def tube(self, a, b, r1, r2, bone, sides=8, sy=1.0):
        """Tapered tube from a to b (closed ends); sy squashes it front-to-back."""
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        M = Matrix.Translation(a) @ rot
        ring = lambda z, r: [self.bm.verts.new(M @ Vector((r * math.cos(t), r * math.sin(t) * sy, z)))
                             for t in [i * math.tau / sides for i in range(sides)]]
        lo, hi = ring(0.0, r1), ring(L, r2)
        for i in range(sides):
            j = (i + 1) % sides
            self.bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
        self.bm.faces.new(list(reversed(lo)))
        self.bm.faces.new(hi)
        self._tag(lo + hi, bone)

    def blob(self, c, r, bone, scale=(1, 1, 1), segs=(10, 6), zmin=-1.0):
        """Low-poly ellipsoid; zmin > -1 cuts it to a dome (hair, wraps)."""
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs[0], v_segments=segs[1], radius=r,
                                        matrix=Matrix.Translation(c) @ Matrix.Diagonal(Vector(scale + (1,))))
        verts = res["verts"]
        if zmin > -1.0:
            cut = c[2] + zmin * r * scale[2]
            for v in verts:
                if v.co.z < cut:
                    v.co.z = cut
        self._tag(verts, bone)

    def box(self, c, size, bone):
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=Matrix.Translation(c) @ Matrix.Diagonal(Vector(size + (1,))))
        self._tag(res["verts"], bone)

    def build(self, arm_ob):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=[], dist=0.0)
        for i, (v, bone) in enumerate(self._vert_bone):
            v.index = -1
        self.bm.verts.index_update()
        mapping = [(v.index, bone) for v, bone in self._vert_bone if v.is_valid]
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = self.name in ("Skin", "Hair", "HeadWrap")
        me.materials.append(material(self.name))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        for vi, bone in mapping:
            vg = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
            vg.add([vi], 1.0, "REPLACE")
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm_ob
        ob.parent = arm_ob
        return ob


def build_armature():
    arm = bpy.data.armatures.new("Armature")
    ob = bpy.data.objects.new("Armature", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in BONES.items():
        eb = arm.edit_bones.new(name)
        eb.head, eb.tail = h, t
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = False
    for eb in arm.edit_bones:
        if eb.name.startswith("foot"):
            eb.align_roll(Vector((0, 0, 1)))
        else:
            eb.align_roll(Vector((0, 1, 0)))      # local Z = forward
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def build_parts(arm_ob):
    P = {n: Part(n) for n in PART_COLORS}
    skin, shirt, trousers, shoes = P["Skin"], P["Shirt"], P["Trousers"], P["Shoes"]
    # head, face cue and neck
    skin.blob((0, 0.005, 1.685), 0.112, "head", scale=(0.92, 1.0, 1.18), segs=(12, 8))
    skin.box((0, 0.11, 1.67), (0.03, 0.04, 0.05), "head")                       # nose
    for sx in (1, -1):
        skin.box((0.108 * sx, 0.0, 1.68), (0.025, 0.04, 0.06), "head")          # ears
    skin.tube((0, 0, 1.47), (0, 0, 1.6), 0.052, 0.05, "neck", 8)
    # torso (shirt) - slightly flattened front-to-back
    shirt.tube((0, 0, 1.0), (0, 0, 1.3), 0.155, 0.165, "spine", 10, sy=0.68)
    shirt.tube((0, 0, 1.3), (0, 0, 1.5), 0.175, 0.13, "chest", 10, sy=0.7)
    for side, sx in (("l", 1), ("r", -1)):
        shirt.blob((0.17 * sx, 0, 1.44), 0.075, "chest", segs=(8, 5))           # shoulder
        shirt.tube((0.205 * sx, 0, 1.46), (0.222 * sx, 0, 1.22), 0.062, 0.055, "upper_arm." + side, 8)
        skin.tube((0.222 * sx, 0, 1.24), (0.225 * sx, 0, 1.17), 0.047, 0.046, "upper_arm." + side, 8)
        skin.tube((0.225 * sx, 0, 1.17), (0.235 * sx, 0, 0.94), 0.045, 0.038, "forearm." + side, 8)
        skin.box((0.235 * sx, 0.005, 0.875), (0.045, 0.075, 0.11), "hand." + side)
        # legs
        trousers.tube((0.098 * sx, 0, 0.95), (0.098 * sx, 0, 0.5), 0.088, 0.068, "thigh." + side, 8)
        trousers.tube((0.098 * sx, 0, 0.52), (0.098 * sx, 0, 0.11), 0.064, 0.05, "shin." + side, 8)
        shoes.box((0.098 * sx, 0.04, 0.045), (0.1, 0.25, 0.09), "foot." + side)
    trousers.tube((0, 0, 0.88), (0, 0, 1.03), 0.16, 0.155, "hips", 10, sy=0.68)
    # optional clothing
    P["Hair"].blob((0, -0.005, 1.7), 0.118, "head", scale=(0.95, 1.02, 1.12), segs=(12, 7), zmin=-0.05)
    P["Skirt"].tube((0, 0, 1.02), (0, 0, 0.36), 0.17, 0.27, "hips", 12, sy=0.85)
    P["HeadWrap"].blob((0, -0.01, 1.75), 0.15, "head", scale=(1.0, 1.05, 0.95), segs=(12, 7), zmin=-0.25)
    P["HeadWrap"].blob((0, -0.1, 1.86), 0.07, "head", scale=(1.6, 0.9, 0.9), segs=(8, 5))   # knot
    P["Cap"].tube((0, 0, 1.76), (0, 0, 1.84), 0.122, 0.118, "head", 12)
    P["Cap"].box((0, 0.12, 1.765), (0.2, 0.12, 0.015), "head")                   # brim
    return [p.build(arm_ob) for p in P.values()]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    arm_ob = build_armature()
    parts = build_parts(arm_ob)
    bpy.ops.object.select_all(action="DESELECT")
    arm_ob.select_set(True)
    for ob in parts:
        ob.select_set(True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    kwargs = dict(filepath=OUT, export_format="GLB", use_selection=True, export_skins=True,
                  export_animations=False, export_cameras=False)
    bpy.ops.export_scene.gltf(**kwargs)
    print("exported", OUT, "%.1f KB" % (os.path.getsize(OUT) / 1024))
    for ob in parts:
        print("  %-9s %4d verts" % (ob.name, len(ob.data.vertices)))


main()
