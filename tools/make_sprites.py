"""
Monrovia Life: Streets - Blender sprite builder.

Builds simple low-poly vehicles and people in Blender and renders them as
top-down PNG sprites (transparent background) into the project's sprites/ folder.

Run from a terminal (Blender 4.2 or newer, including 5.x):
    blender -b -P tools/make_sprites.py
or open Blender > Scripting tab > Open this file > Run Script.

Conventions: every model faces +X (the sprite's right side is the front).
Vehicles: 8 m x 4 m frame rendered at 256x128 px (Godot draws them at 56x28 px).
People:   1.2 m x 1.2 m frame rendered at 96x96 px (Godot draws them at 26x26 px).
Bodies rendered near-white are tinted in Godot (cars, SUVs, sports cars, trucks).
"""
import bpy
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else bpy.path.abspath("//")
OUT = os.path.normpath(os.path.join(HERE, "..", "sprites"))
os.makedirs(OUT, exist_ok=True)

WHITE = (0.93, 0.93, 0.93, 1)
GLASS = (0.07, 0.11, 0.17, 1)
TIRE = (0.04, 0.04, 0.045, 1)
YELLOW = (0.96, 0.72, 0.05, 1)
NAVY = (0.06, 0.1, 0.24, 1)
RED = (0.85, 0.05, 0.1, 1)
BLUE = (0.08, 0.3, 0.95, 1)
LAMP = (1.0, 0.97, 0.8, 1)
TAIL = (0.7, 0.03, 0.05, 1)
STEEL = (0.42, 0.46, 0.5, 1)


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (lin[0], lin[1], lin[2], 1)


# ------------------------------------------------------------------ scene
def reset_scene(res_x, res_y, ortho):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = res_x
    sc.render.resolution_y = res_y
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    try:
        sc.view_settings.view_transform = "Standard"
    except Exception:
        pass
    sh = sc.display.shading
    sh.light = "FLAT"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.cavity_ridge_factor = 1.0
    sh.cavity_valley_factor = 1.2
    sh.curvature_ridge_factor = 1.0
    sh.curvature_valley_factor = 1.0
    sh.show_object_outline = True
    sh.object_outline_color = (0.03, 0.04, 0.07)
    sh.show_specular_highlight = True
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (0, 0, 30)
    cam.rotation_euler = (0, 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


def material(rgba):
    key = "m_%.3f_%.3f_%.3f" % rgba[:3]
    m = bpy.data.materials.get(key)
    if m is None:
        m = bpy.data.materials.new(key)
        m.diffuse_color = rgba
        m.roughness = 0.45
        try:
            m.use_nodes = True
        except Exception:
            pass
        nt = getattr(m, "node_tree", None)
        if nt is not None:
            bsdf = nt.nodes.get("Principled BSDF")
            if bsdf is not None:
                bsdf.inputs["Base Color"].default_value = rgba
                bsdf.inputs["Roughness"].default_value = 0.45
    return m


def _finish(o, rgba, bevel=0.0):
    o.data.materials.append(material(rgba))
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
    for p in o.data.polygons:
        p.use_smooth = bevel > 0
    return o


def box(center, size, rgba, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(o, rgba, bevel)


def cyl(center, r, depth, rgba, axis="y", verts=20):
    rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=center, rotation=rot)
    return _finish(bpy.context.active_object, rgba)


def ball(center, scale, rgba):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1, location=center)
    o = bpy.context.active_object
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o = _finish(o, rgba)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def render(name):
    bpy.context.scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


# ------------------------------------------------------------------ vehicles
def wheels(xs, half_w, r=0.36, w=0.32):
    for x in xs:
        for s in (-1, 1):
            cyl((x, s * half_w, r), r, w, TIRE, "y")


def lights(front_x, rear_x, half_w):
    for s in (-1, 1):
        box((front_x, s * (half_w - 0.25), 0.75), (0.08, 0.35, 0.16), LAMP)
        box((rear_x, s * (half_w - 0.25), 0.8), (0.08, 0.3, 0.14), TAIL)


def sedan(body, L=4.4, Wd=1.85, H=0.75, cabin_len=2.3, cabin_x=-0.25, low=False):
    z0 = 0.32
    box((0, 0, z0 + H / 2), (L, Wd, H), body, bevel=0.12)
    top = z0 + H
    ch = 0.42 if low else 0.55
    roof_len = cabin_len * 0.5
    box((cabin_x, 0, top + ch / 2), (roof_len, Wd * 0.82, ch), body, bevel=0.08)
    box((cabin_x + roof_len / 2 + 0.33, 0, top + ch * 0.42), (0.7, Wd * 0.8, ch * 0.84), GLASS, bevel=0.05)
    box((cabin_x - roof_len / 2 - 0.25, 0, top + ch * 0.42), (0.5, Wd * 0.8, ch * 0.84), GLASS, bevel=0.05)
    for s in (-1, 1):
        box((cabin_x, s * (Wd * 0.41), top + ch * 0.4), (roof_len + 0.9, 0.04, ch * 0.6), GLASS)
        box((cabin_x + roof_len / 2 + 0.75, s * (Wd / 2 + 0.08), top), (0.12, 0.16, 0.1), body)
    wheels((L / 2 - 0.85, -L / 2 + 0.85), Wd / 2 - 0.05)
    lights(L / 2, -L / 2, Wd / 2)
    return top + ch


def build_car():
    sedan(WHITE)


def build_taxi():
    top = sedan(YELLOW)
    box((-0.25, 0, top + 0.12), (0.35, 0.8, 0.22), NAVY, bevel=0.03)
    box((-0.25, 0, top + 0.24), (0.3, 0.7, 0.03), YELLOW)


def build_sport():
    top = sedan(WHITE, L=4.5, Wd=1.95, H=0.55, cabin_len=2.0, cabin_x=-0.45, low=True)
    for s in (-0.22, 0.22):
        box((0.6, s, 0.32 + 0.56), (2.6, 0.16, 0.02), (0.75, 0.75, 0.75, 1))
    box((-2.1, 0, 1.0), (0.25, 1.8, 0.06), WHITE)  # spoiler


def build_suv():
    top = sedan(WHITE, L=4.8, Wd=2.0, H=1.0, cabin_len=3.1, cabin_x=-0.4)
    for s in (-0.55, 0.55):
        box((-0.4, s, top + 0.05), (1.5, 0.06, 0.06), STEEL)


def build_police():
    top = sedan(WHITE, L=4.6, Wd=1.9)
    box((1.55, 0, 0.32 + 0.76), (1.4, 1.75, 0.02), NAVY)
    box((-1.85, 0, 0.32 + 0.76), (0.85, 1.75, 0.02), NAVY)
    box((-0.25, -0.33, top + 0.09), (0.3, 0.6, 0.14), RED, bevel=0.03)
    box((-0.25, 0.33, top + 0.09), (0.3, 0.6, 0.14), BLUE, bevel=0.03)


def build_truck():
    box((2.55, 0, 1.15), (1.7, 2.2, 1.7), WHITE, bevel=0.1)          # cab
    box((3.3, 0, 1.35), (0.3, 2.0, 0.9), GLASS, bevel=0.03)          # windscreen
    box((-1.0, 0, 1.55), (5.2, 2.4, 2.3), WHITE, bevel=0.05)          # cargo box
    for x in (-3.0, -2.0, -1.0, 0.0, 1.0):
        box((x, 0, 2.71), (0.06, 2.3, 0.03), (0.75, 0.75, 0.75, 1))
    wheels((2.6, -0.4, -2.6), 1.12, r=0.45, w=0.38)
    lights(3.4, -3.6, 1.1)


def build_van():
    gray = srgb("#6b7680")
    box((0, 0, 1.25), (5.4, 2.2, 1.9), gray, bevel=0.08)
    box((2.35, 0, 1.55), (0.55, 2.0, 0.7), GLASS, bevel=0.03)
    box((-0.4, 0, 2.21), (3.6, 2.0, 0.05), srgb("#596370"))
    box((-0.4, 0, 2.25), (3.4, 0.35, 0.03), YELLOW)
    for x in (-2.0, -1.0, 0.0, 1.0):
        for s in (-0.85, 0.85):
            cyl((x, s, 2.25), 0.06, 0.05, STEEL, "z", 10)
    wheels((1.7, -1.7), 1.05, r=0.44, w=0.36)
    lights(2.7, -2.7, 1.1)


def build_keke():
    y = YELLOW
    box((-0.2, 0, 0.6), (2.3, 1.25, 0.6), y, bevel=0.12)                  # body tub
    box((1.15, 0, 0.75), (0.7, 0.55, 0.7), y, bevel=0.12)                 # nose
    box((1.0, 0, 1.25), (0.15, 1.05, 0.5), GLASS, bevel=0.02)             # windscreen
    box((-0.35, 0, 1.75), (1.6, 1.1, 0.12), srgb("#1d5a3a"), bevel=0.06)  # canopy roof
    box((-0.35, 0, 1.82), (1.2, 0.8, 0.03), srgb("#2a7a50"))
    cyl((1.25, 0, 0.3), 0.3, 0.2, TIRE, "y")
    for s in (-1, 1):
        cyl((-0.95, s * 0.6, 0.3), 0.3, 0.2, TIRE, "y")
    box((1.5, 0, 0.85), (0.06, 0.25, 0.14), LAMP)


VEHICLES = {
    "keke": build_keke, "taxi": build_taxi, "car": build_car, "sport": build_sport,
    "suv": build_suv, "truck": build_truck, "police": build_police, "van": build_van,
}

# ------------------------------------------------------------------ people
SKIN = srgb("#5a3825")
SHIRTS = ["#c8173a", "#1aa39e", "#f5c518", "#2b5fb3", "#ef7d22", "#7c3aed"]


def person(shirt, head="hair", wrap=None, cap=None, load=False):
    ball((0, 0, 1.25), (0.2, 0.36, 0.2), shirt)                  # shoulders / torso
    for s in (-1, 1):
        ball((0.05, s * 0.36, 1.15), (0.09, 0.08, 0.18), shirt)  # sleeves
        ball((0.12, s * 0.38, 0.95), (0.06, 0.06, 0.06), SKIN)   # hands
    ball((0.03, 0, 1.58), (0.13, 0.12, 0.14), SKIN)              # head
    ball((0.16, 0, 1.56), (0.03, 0.03, 0.03), SKIN)              # nose
    if head == "hair":
        ball((0.0, 0, 1.64), (0.12, 0.115, 0.09), (0.02, 0.015, 0.012, 1))
    if wrap is not None:
        ball((0.0, 0, 1.68), (0.15, 0.14, 0.11), wrap)
        ball((-0.13, 0, 1.72), (0.07, 0.09, 0.06), wrap)
    if cap is not None:
        cyl((0.0, 0, 1.7), 0.14, 0.08, cap, "z")
        box((0.15, 0, 1.68), (0.12, 0.2, 0.02), cap)
        box((0.0, 0, 1.75), (0.06, 0.06, 0.01), YELLOW)
    if load:
        cyl((0.0, 0, 1.85), 0.3, 0.12, srgb("#d9a441"), "z")
        for i, c in enumerate(("#c8173a", "#3ccf7a", "#ef7d22")):
            ball((-0.1 + i * 0.1, (i - 1) * 0.12, 1.93), (0.08, 0.08, 0.06), srgb(c))


def build_people():
    peds = {}
    for i, h in enumerate(SHIRTS):
        style = i % 3
        peds["ped_%d" % i] = (lambda h=h, style=style: person(
            srgb(h), head="hair" if style != 1 else "none",
            wrap=srgb(SHIRTS[(SHIRTS.index(h) + 2) % 6]) if style == 1 else None,
            load=(style == 2)))
    peds["ped_player"] = lambda: person(srgb("#c8173a"))
    peds["ped_cop"] = lambda: person(srgb("#2b4a7a"), head="none", cap=srgb("#14213d"))
    peds["ped_auntie"] = lambda: person(srgb("#7c3aed"), head="none", wrap=srgb("#ef7d22"))
    return peds


# ------------------------------------------------------------------ main
def main():
    for name, fn in VEHICLES.items():
        reset_scene(256, 128, 8.0)
        fn()
        render("veh_" + name)
    for name, fn in build_people().items():
        reset_scene(96, 96, 1.2)
        fn()
        render(name)
    print("Sprites written to", OUT)


if __name__ == "__main__":
    main()
