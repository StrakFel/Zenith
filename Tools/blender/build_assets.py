"""
ZENITH asset generator - run with Blender in background mode:

  blender --background --python Tools/blender/build_assets.py -- Assets/Models

Builds every 3D model of the game procedurally (rocket parts, launchpad, satellite,
space station, spacecraft, astronaut) and exports them as .glb files.
Conventions: metres, Blender +Z is up (becomes +Y in Godot), objects keep their own
origin so Godot can animate them (swing arms, solar wing hinges, antenna ...).
Palette: white / grey bodies, dark technical parts, blue + orange accents (no flag colours).
"""
import bpy
import bmesh
import math
import os
import sys

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
os.makedirs(OUT, exist_ok=True)

# ----------------------------------------------------------------- materials --
_mats = {}


def mat(name, color, metallic=0.0, rough=0.5, emit=None, strength=0.0):
    key = name
    if key in _mats and _mats[key].name in bpy.data.materials:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit is not None:
        b.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        b.inputs["Emission Strength"].default_value = strength
    _mats[key] = m
    return m


def M():
    """(Re)create the shared palette after a scene reset."""
    _mats.clear()
    return {
        "white": mat("hull_white", (0.90, 0.92, 0.95), 0.25, 0.36),
        "gray": mat("hull_gray", (0.58, 0.62, 0.68), 0.55, 0.42),
        "dark": mat("tech_dark", (0.07, 0.08, 0.10), 0.7, 0.5),
        "steel": mat("steel", (0.30, 0.32, 0.37), 0.92, 0.32),
        "blue": mat("accent_blue", (0.1, 0.45, 1.0), 0.0, 0.4, (0.15, 0.55, 1.0), 4.0),
        "orange": mat("accent_orange", (1.0, 0.42, 0.08), 0.0, 0.4, (1.0, 0.45, 0.1), 5.0),
        "gold": mat("gold_foil", (0.95, 0.72, 0.25), 0.95, 0.22),
        "solar": mat("solar_cell", (0.02, 0.06, 0.22), 0.55, 0.18, (0.02, 0.10, 0.40), 0.5),
        "frame": mat("solar_frame", (0.75, 0.78, 0.84), 0.6, 0.35),
        "concrete": mat("concrete", (0.46, 0.47, 0.50), 0.0, 0.92),
        "visor": mat("visor_gold", (0.9, 0.65, 0.25), 1.0, 0.08),
        "lamp": mat("lamp_white", (1.0, 0.95, 0.85), 0.0, 0.3, (1.0, 0.92, 0.75), 2.5),
        "glass": mat("dark_glass", (0.02, 0.05, 0.12), 0.9, 0.1),
    }


# ------------------------------------------------------------------- helpers --
def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


def _finish(o, material, bevel=0.0, smooth_angle=None):
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    if bevel > 0.0:
        md = o.modifiers.new("bevel", "BEVEL")
        md.width = bevel
        md.segments = 2
        md.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier="bevel")
    if material is not None:
        o.data.materials.clear()
        o.data.materials.append(material)
    if smooth_angle is not None:
        autosmooth(o, smooth_angle)
    o.select_set(False)
    return o


def autosmooth(o, ang=40.0):
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(ang):
            e.smooth = False
    bm.to_mesh(me)
    bm.free()


def box(name, size, loc, material, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, material, bevel, 35.0 if bevel > 0 else None)


def cyl(name, r, h, loc, material, seg=48, axis="Z", bevel=0.0, r2=None):
    rot = {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=r, depth=h, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=r, radius2=r2, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return _finish(o, material, bevel, 50.0)


def sphere(name, r, loc, material, scale=(1, 1, 1), seg=40):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, material, 0.0, 80.0)


def torus(name, major, minor, loc, material, axis="Z"):
    rot = {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
    bpy.ops.mesh.primitive_torus_add(major_segments=48, minor_segments=12, major_radius=major,
                                     minor_radius=minor, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return _finish(o, material, 0.0, 80.0)


def lathe(name, profile, material, seg=64, loc=(0, 0, 0), axis="Z"):
    """Surface of revolution. profile = [(radius, z), ...] with z increasing (outward normals)."""
    verts, faces = [], []
    n = len(profile)
    for (r, z) in profile:
        for i in range(seg):
            a = 2.0 * math.pi * i / seg
            verts.append((max(r, 0.002) * math.cos(a), max(r, 0.002) * math.sin(a), z))
    for j in range(n - 1):
        for i in range(seg):
            a = j * seg + i
            b = j * seg + (i + 1) % seg
            c = (j + 1) * seg + (i + 1) % seg
            d = (j + 1) * seg + i
            faces.append((a, b, c, d))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.location = loc
    if axis == "X":
        o.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "-Z":
        o.rotation_euler = (math.pi, 0, 0)
    return _finish(o, material, 0.0, 70.0)


def prism(name, pts2d, thickness, material, plane="XZ", loc=(0, 0, 0)):
    """Extruded polygon. plane XZ: points are (x, z), thickness along Y."""
    n = len(pts2d)
    t = thickness / 2.0
    verts = []
    for (a, b) in pts2d:
        verts.append((a, -t, b))
    for (a, b) in pts2d:
        verts.append((a, t, b))
    faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    me.validate()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.location = loc
    return _finish(o, material, 0.0, 30.0)


def join(objs, name, origin=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    j = bpy.context.active_object
    j.name = name
    if origin is not None:
        cur = bpy.context.scene.cursor
        cur.location = origin
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        cur.location = (0, 0, 0)
    j.select_set(False)
    return j


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_cameras=False,
                              export_lights=False)
    print("EXPORTED", path)


def new_asset():
    clear()
    return M()


# --------------------------------------------------------------- rocket parts --
RR = 2.0  # rocket radius


def nose(kind):
    m = new_asset()
    H = 12.0 if kind == "std" else 18.0
    n = 18
    body, tip = [], []
    for i in range(n + 1):
        t = i / n
        if kind == "std":
            r = RR * (max(0.0, 1.0 - t ** 2.3)) ** 0.55
        else:
            s = 1.0 - t  # distance from tip (0..1)
            th = math.acos(max(-1.0, min(1.0, 1.0 - 2.0 * s)))
            r = RR * math.sqrt(max(0.0, (th - math.sin(2 * th) / 2.0) / math.pi))
        (body if t < (0.9 if kind == "std" else 0.88) else tip).append((r, H * t))
    if tip:
        tip.insert(0, body[-1])
    lathe("nose_body", body + [], m["white"], 72)
    if tip:
        lathe("nose_tip", tip, m["dark"], 72)
    cyl("nose_base_band", RR + 0.03, 0.55, (0, 0, 0.275), m["dark"], 72, bevel=0.03)
    torus("nose_accent_ring", RR + 0.04, 0.045, (0, 0, 0.95), m["blue"])
    # fairing seam lines
    for k in range(2):
        a = math.pi * k
        box("seam_%d" % k, (0.05, 0.05, H * 0.8), (math.cos(a) * (RR - 0.04), math.sin(a) * (RR - 0.04), H * 0.42), m["gray"])
    export("rocket_nose_" + kind)


def tank(kind, H):
    m = new_asset()
    cyl("tank_body", RR, H - 1.6, (0, 0, H * 0.5), m["white"], 72)
    cyl("band_bottom", RR + 0.04, 0.9, (0, 0, 0.45), m["dark"], 72, bevel=0.04)
    cyl("band_top", RR + 0.04, 0.9, (0, 0, H - 0.45), m["dark"], 72, bevel=0.04)
    # panel seams
    z = 4.0
    while z < H - 1.5:
        cyl("seam", RR + 0.018, 0.07, (0, 0, z), m["gray"], 72)
        z += 4.0
    if kind != "s":
        cyl("mid_band", RR + 0.04, 0.5, (0, 0, H * 0.5), m["dark"], 72, bevel=0.03)
    # cable raceways + accents
    for k in range(4):
        a = math.pi * 0.25 + k * math.pi * 0.5
        box("raceway_%d" % k, (0.22, 0.12, H - 3.2), (math.cos(a) * (RR + 0.04), math.sin(a) * (RR + 0.04), H * 0.5),
            m["gray"], 0.02, (0, 0, a))
    for k in range(2):
        a = math.pi * k
        box("led_strip_%d" % k, (0.06, 0.5, 1.6), (math.cos(a) * (RR + 0.02), math.sin(a) * (RR + 0.02), H - 3.0),
            m["blue"], 0.0, (0, 0, a))
    export("rocket_tank_" + kind)


def engine(kind):
    m = new_asset()
    cfg = {"spark": (5.5, 1.25, 0.34, 1), "kestrel": (7.0, 1.75, 0.5, 1), "phoenix": (8.5, 1.08, 0.3, 3)}[kind]
    h, r_exit, r_throat, count = cfg
    z_skirt = h - 1.8
    cyl("skirt", RR, 1.8, (0, 0, h - 0.9), m["dark"], 72, bevel=0.05)
    cyl("skirt_ring", RR + 0.06, 0.28, (0, 0, h - 0.14), m["steel"], 72, bevel=0.04)
    offsets = [(0.0, 0.0)] if count == 1 else [(1.0 * math.cos(a), 1.0 * math.sin(a)) for a in (math.pi * 0.5, math.pi * 1.1667, math.pi * 1.8333)]
    for idx, (ox, oy) in enumerate(offsets):
        prof = []
        steps = 16
        z0 = 0.0
        for i in range(steps + 1):
            u = i / steps  # 0 = exit, 1 = throat
            z = z0 + (z_skirt - z0) * u
            f = (1.0 - u) ** 0.6
            r = r_throat + (r_exit - r_throat) * f
            prof.append((r, z))
        lathe("bell_%d" % idx, prof, m["steel"], 48, (ox, oy, 0))
        lathe("bell_in_%d" % idx, [(r - 0.05, z) for (r, z) in prof][:steps], m["dark"], 48, (ox, oy, 0.02))
        cyl("glow_%d" % idx, r_exit - 0.02, 0.1, (ox, oy, 0.05), m["orange"], 48)
        torus("bell_ring_%d" % idx, r_exit * 0.62, 0.07, (ox, oy, z_skirt * 0.55), m["gray"])
    # turbopump boxes + pipes
    for k in range(4):
        a = k * math.pi * 0.5 + math.pi * 0.25
        box("pump_%d" % k, (0.5, 0.35, 0.9), (math.cos(a) * (RR + 0.2), math.sin(a) * (RR + 0.2), h - 0.9), m["steel"], 0.05, (0, 0, a))
    # swept fins
    for k in range(4):
        a = k * math.pi * 0.5
        pts = [(RR - 0.1, h - 0.1), (RR - 0.1, h - 4.4), (4.8, h - 5.2), (4.8, h - 3.4)]
        f = prism("fin_%d" % k, pts, 0.22, m["dark"])
        f.rotation_euler = (0, 0, a)
        bpy.context.view_layer.objects.active = f
        bpy.ops.object.transform_apply(rotation=True)
        edge = prism("fin_edge_%d" % k, [(4.7, h - 3.5), (4.8, h - 3.4), (4.8, h - 5.2), (4.7, h - 5.1)], 0.26, m["gray"])
        edge.rotation_euler = (0, 0, a)
        bpy.context.view_layer.objects.active = edge
        bpy.ops.object.transform_apply(rotation=True)
    export("rocket_engine_" + kind)


# --------------------------------------------------------------------- launchpad --
def launchpad():
    m = new_asset()
    # apron + trench
    box("apron", (150, 150, 1.0), (0, 0, -0.5), m["concrete"], 0.1)
    box("trench", (30, 30, 0.6), (0, 0, 0.0), m["dark"])
    box("pad_ring_plate", (14, 14, 0.4), (0, 0, 3.8), m["steel"], 0.1)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("pillar", (2.6, 2.6, 3.8), (sx * 5.0, sy * 5.0, 1.9), m["gray"], 0.1)
    cyl("launch_mount", 4.6, 0.7, (0, 0, 4.05), m["dark"], 48, bevel=0.1)
    for k in range(8):
        a = k * math.pi / 4
        box("hold_down_%d" % k, (0.6, 0.5, 0.6), (math.cos(a) * 3.6, math.sin(a) * 3.6, 4.5), m["steel"], 0.05, (0, 0, a))
    # service tower (lattice) at x = -15
    tx, ty = -15.0, 0.0
    height = 72.0
    steel, dark = [], []
    for sx in (-1, 1):
        for sy in (-1, 1):
            steel.append(box("col", (0.9, 0.9, height), (tx + sx * 3.6, ty + sy * 3.6, height * 0.5), m["gray"], 0.05))
    floors = int(height // 6)
    for i in range(floors + 1):
        z = 3.0 + i * 6.0
        if z > height:
            break
        dark.append(box("floor", (8.6, 8.6, 0.35), (tx, ty, z), m["dark"]))
        for (dx, dy, w, d) in ((0, 3.6, 7.2, 0.3), (0, -3.6, 7.2, 0.3), (3.6, 0, 0.3, 7.2), (-3.6, 0, 0.3, 7.2)):
            steel.append(box("rail", (w, d, 0.25), (tx + dx, ty + dy, z + 0.2), m["gray"]))
        if i < floors:
            ang = math.atan2(6.0, 7.2)
            L = math.hypot(6.0, 7.2)
            flip = 1 if i % 2 == 0 else -1
            steel.append(box("brace_x", (L, 0.25, 0.25), (tx, ty + 3.6, z + 3.0), m["gray"], 0.0, (0, flip * ang, 0)))
            steel.append(box("brace_x2", (L, 0.25, 0.25), (tx, ty - 3.6, z + 3.0), m["gray"], 0.0, (0, -flip * ang, 0)))
            steel.append(box("brace_y", (0.25, L, 0.25), (tx + 3.6, ty, z + 3.0), m["gray"], 0.0, (-flip * ang, 0, 0)))
            steel.append(box("brace_y2", (0.25, L, 0.25), (tx - 3.6, ty, z + 3.0), m["gray"], 0.0, (flip * ang, 0, 0)))
    join(steel, "tower_steel")
    join(dark, "tower_floors")
    # swing arms (origin at the tower side so Godot can rotate them away)
    for i, z in enumerate((14.0, 30.0, 44.0, 58.0)):
        a1 = box("arm_%d" % (i + 1), (11.0, 1.6, 1.6), (tx + 4.4 + 5.5, 0, z), m["steel"], 0.06)
        pad = box("arm_pad_%d" % (i + 1), (1.4, 2.4, 2.0), (tx + 4.4 + 10.8, 0, z), m["dark"], 0.05)
        j = join([a1, pad], "arm_%d" % (i + 1), origin=(tx + 4.4, 0, z))
    # lightning masts with beacons
    for (px, py) in ((-30, 30), (30, 30), (-30, -30), (30, -30)):
        cyl("mast", 0.18, 95, (px, py, 47.5), m["dark"], 12)
        sphere("beacon", 0.6, (px, py, 95.5), m["lamp"])
    # floodlights
    for i, (px, py) in enumerate(((16, 24), (-16, 24), (22, -22), (-22, -22), (40, 0))):
        cyl("lamp_pole_%d" % i, 0.25, 22, (px, py, 11), m["steel"], 12)
        box("lamp_%d" % i, (2.4, 1.2, 0.6), (px, py, 22.3), m["lamp"], 0.05)
    # fuel storage + building
    for (px, py) in ((60, 30), (60, -10)):
        sphere("lox_sphere", 7.0, (px, py, 12), m["white"], seg=48)
        for k in range(6):
            a = k * math.pi / 3
            cyl("lox_leg", 0.4, 10, (px + math.cos(a) * 5.2, py + math.sin(a) * 5.2, 5), m["gray"], 12)
    box("vab", (60, 48, 70), (-230, 300, 35), m["dark"], 0.3)
    box("vab_door", (14, 1, 44), (-230, 275.5, 22), m["steel"])
    box("vab_stripe", (60.2, 48.2, 3), (-230, 300, 55), m["gray"], 0.1)
    for k in range(5):
        box("pipe_%d" % k, (40, 0.8, 0.8), (35, -40 + k * 1.2, 0.6), m["steel"], 0.1)
    export("launchpad")


# ----------------------------------------------------------------- satellite etc --
def solar_wing(name, length, chord, cells, material_cell, material_frame, origin_x, sign):
    objs = []
    gap = 0.12
    cw = (length - gap * (cells + 1)) / cells
    for i in range(cells):
        x0 = sign * (gap + i * (cw + gap) + cw / 2.0)
        objs.append(box("cell", (cw, chord, 0.12), (origin_x + x0, 0, 0), material_cell))
    objs.append(box("spar", (length, 0.25, 0.25), (origin_x + sign * length / 2.0, 0, 0.0), material_frame, 0.03))
    return objs


def satellite():
    m = new_asset()
    # body (14 x 9 deep x 10 tall) gold foil
    box("body", (14, 9, 10), (0, 0, 0), m["gold"], 0.35)
    box("body_band", (14.2, 9.2, 2.0), (0, 0, -3.2), m["dark"], 0.2)
    box("body_trim", (14.1, 9.1, 0.6), (0, 0, 4.2), m["gray"], 0.1)
    sphere("lens", 1.2, (0, -4.6, 0.5), m["glass"], (1, 0.35, 1))
    sphere("status_led", 0.35, (-5.5, -4.6, 3.6), m["blue"])
    # right wing (intact, hinge at x = 8)
    objs = solar_wing("wing_R", 20.0, 6.0, 6, m["solar"], m["frame"], 0.0, 1)
    objs.append(cyl("hinge_R", 0.5, 1.2, (0, 0, 0), m["steel"], 24, axis="X"))
    join(objs, "wing_R", origin=(0, 0, 0))
    bpy.data.objects["wing_R"].location = (8.0, 0, 0)
    # left wing (hinge at x = -8) - Godot rotates this node when it is "broken"
    objs = solar_wing("wing_L", 18.0, 6.0, 6, m["solar"], m["frame"], 0.0, -1)
    objs.append(cyl("hinge_L", 0.5, 1.2, (0, 0, 0), m["steel"], 24, axis="X"))
    join(objs, "wing_L", origin=(0, 0, 0))
    bpy.data.objects["wing_L"].location = (-8.0, 0, 0)
    # antenna dish: origin at the base on top of the body (2, 0, 5)
    mast = cyl("mast", 0.18, 3.2, (0, 0, 1.6), m["steel"], 16)
    dish = lathe("dish_bowl", [(0.05, 3.3), (0.9, 3.45), (1.7, 3.8), (2.3, 4.3)], m["white"], 40)
    dish2 = lathe("dish_back", [(2.3, 4.3), (1.7, 4.22), (0.9, 3.92), (0.05, 3.7)], m["gray"], 40)
    feed = cyl("feed", 0.08, 1.8, (0, 0, 4.4), m["steel"], 12)
    knob = sphere("feed_tip", 0.2, (0, 0, 5.3), m["orange"])
    join([mast, dish, dish2, feed, knob], "dish", origin=(0, 0, 0))
    bpy.data.objects["dish"].location = (2.0, 0, 5.0)
    # battery unit under the body: origin at its centre (4, 0, -6.5)
    b = box("battery_box", (5, 4, 3), (0, 0, 0), m["steel"], 0.15)
    box("battery_vent", (4, 0.1, 1), (0, -2.05, 0), m["dark"])
    bl = sphere("battery_led", 0.4, (-1.8, -2.1, 0.9), m["orange"])
    bpy.data.objects["battery_box"].location = (4.0, 0, -6.5)
    bpy.data.objects["battery_vent"].location = (4.0, 0, -6.5)
    bpy.data.objects["battery_led"].location = (4.0 - 1.8, -2.1, -6.5 + 0.9)
    # --- science instruments: Godot shows only the one picked in the mission design
    parts = [cyl("tube", 1.9, 4.5, (0, 0, 0), m["dark"], 40, axis="Y"),
             cyl("hood", 2.25, 1.2, (0, -2.6, 0), m["gray"], 40, axis="Y"),
             sphere("lens2", 1.6, (0, -3.15, 0), m["glass"], (1, 0.15, 1)),
             torus("lens_ring", 2.05, 0.12, (0, -3.25, 0), m["blue"], axis="Y"),
             box("tube_mount", (3.6, 1.4, 0.6), (0, 1.6, -1.9), m["steel"], 0.05)]
    join(parts, "inst_imager", origin=(0, 0, 0))
    bpy.data.objects["inst_imager"].location = (-3.5, -6.0, -1.0)
    parts = [cyl("boom", 0.22, 9.0, (0, 0, 4.5), m["steel"], 16),
             sphere("mag_head", 0.7, (0, 0, 9.2), m["gold"]),
             sphere("mag_mid", 0.45, (0, 0, 5.0), m["blue"]),
             box("mag_base", (2.2, 2.2, 1.2), (0, 0, 0.6), m["dark"], 0.1)]
    join(parts, "inst_mag", origin=(0, 0, 0))
    bpy.data.objects["inst_mag"].location = (-4.0, 1.0, 5.0)
    parts = [cyl("cone", 2.5, 3.6, (0, -1.8, 0), m["steel"], 40, axis="Y", r2=0.9),
             sphere("sensor", 0.9, (0, -3.8, 0), m["orange"]),
             box("rad", (4.0, 0.2, 2.4), (0, 0.2, 2.6), m["white"], 0.04),
             box("rad_arm", (0.2, 1.8, 0.2), (0, -0.6, 1.4), m["steel"])]
    join(parts, "inst_spec", origin=(0, 0, 0))
    bpy.data.objects["inst_spec"].location = (-3.5, -6.0, -1.0)
    export("satellite")


def station():
    m = new_asset()
    # docking module along X (0..14), radius 3.4
    cyl("node", 3.4, 14.0, (7.0, 0, 0), m["white"], 64, axis="X")
    cyl("node_ring_a", 3.5, 0.6, (1.0, 0, 0), m["dark"], 64, axis="X", bevel=0.05)
    cyl("node_ring_b", 3.5, 0.6, (13.4, 0, 0), m["dark"], 64, axis="X", bevel=0.05)
    cyl("adapter", 1.9, 1.2, (-0.4, 0, 0), m["steel"], 48, axis="X", bevel=0.05)
    cyl("adapter_core", 1.4, 1.3, (-0.45, 0, 0), m["dark"], 48, axis="X")
    port_ring = torus("port_light", 1.65, 0.09, (-1.05, 0, 0), m["orange"], axis="X")
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        box("handrail_%d" % k, (6.0, 0.15, 0.15), (7.0, math.cos(a) * 3.55, math.sin(a) * 3.55), m["gray"])
    for k in range(4):
        box("window_%d" % k, (1.1, 0.12, 0.5), (3.0 + k * 2.6, -3.38, 1.3), m["glass"], 0.04)
    # truss (14 .. 118)
    parts = []
    for sy in (-1, 1):
        for sz in (-1, 1):
            parts.append(box("rail", (104, 0.22, 0.22), (66, sy * 1.4, sz * 1.4), m["gray"]))
    x = 14.0
    while x <= 118.0:
        parts.append(box("frame_z", (0.18, 2.8, 0.18), (x, 0, 1.4), m["gray"]))
        parts.append(box("frame_z2", (0.18, 2.8, 0.18), (x, 0, -1.4), m["gray"]))
        parts.append(box("frame_y", (0.18, 0.18, 2.8), (x, 1.4, 0), m["gray"]))
        parts.append(box("frame_y2", (0.18, 0.18, 2.8), (x, -1.4, 0), m["gray"]))
        if x + 4.0 <= 118.0:
            L = math.hypot(4.0, 2.8)
            parts.append(box("diag", (L, 0.12, 0.12), (x + 2.0, 1.4, 0), m["gray"], 0.0, (0, math.atan2(2.8, 4.0), 0)))
            parts.append(box("diag", (L, 0.12, 0.12), (x + 2.0, -1.4, 0), m["gray"], 0.0, (0, -math.atan2(2.8, 4.0), 0)))
        x += 4.0
    join(parts, "truss")
    # pressurised modules (vertical, along Z)
    cyl("lab", 4.0, 24.0, (26.0, 0, 0), m["white"], 64)
    cyl("lab_band_a", 4.1, 0.8, (26.0, 0, 7.0), m["dark"], 64, bevel=0.05)
    cyl("lab_band_b", 4.1, 0.8, (26.0, 0, -7.0), m["dark"], 64, bevel=0.05)
    sphere("lab_cap_a", 4.0, (26.0, 0, 12.0), m["gray"], (1, 1, 0.35))
    sphere("lab_cap_b", 4.0, (26.0, 0, -12.0), m["gray"], (1, 1, 0.35))
    cyl("hab", 3.0, 20.0, (63.0, 0, 0), m["white"], 64)
    cyl("hab_band", 3.1, 0.7, (63.0, 0, 5.0), m["dark"], 64, bevel=0.05)
    cyl("hab_band2", 3.1, 0.7, (63.0, 0, -5.0), m["dark"], 64, bevel=0.05)
    sphere("hab_cap_a", 3.0, (63.0, 0, 10.0), m["gray"], (1, 1, 0.4))
    sphere("hab_cap_b", 3.0, (63.0, 0, -10.0), m["gray"], (1, 1, 0.4))
    # four big solar arrays: x 36..52 / 86..102, z +-(16..62)
    for ax in (36.0, 86.0):
        for sgn in (-1, 1):
            cells = []
            z0 = 16.0
            n = 11
            ch = (46.0 - 0.3 * (n + 1)) / n
            for i in range(n):
                zc = sgn * (z0 + 0.3 + i * (ch + 0.3) + ch / 2.0)
                cells.append(box("cell", (7.4, 0.1, ch), (ax + 4.0, 0, zc), m["solar"]))
                cells.append(box("cell", (7.4, 0.1, ch), (ax + 12.0, 0, zc), m["solar"]))
            cells.append(box("mast", (0.5, 0.5, 46.0), (ax + 8.0, 0, sgn * 39.0), m["frame"], 0.05))
            cells.append(box("edge_l", (0.25, 0.2, 46.0), (ax, 0, sgn * 39.0), m["frame"]))
            cells.append(box("edge_r", (0.25, 0.2, 46.0), (ax + 16.0, 0, sgn * 39.0), m["frame"]))
            join(cells, "array_%d_%d" % (int(ax), sgn))
    # radiators
    for sgn in (-1, 1):
        panels = [box("rad", (6.0, 0.2, 5.8), (111.0, 0, sgn * (4.0 + i * 6.0)), m["white"], 0.03) for i in range(5)]
        join(panels, "radiator_%d" % sgn)
    # greebles: antennas and a robotic arm
    for k in range(5):
        cyl("antenna_%d" % k, 0.12, 5, (20 + k * 18, 1.6, 2.8), m["gray"], 10)
        sphere("dish_%d" % k, 0.9, (20 + k * 18, 1.6, 5.4), m["white"], (1, 1, 0.3))
    arm = [box("arm_seg", (14, 0.5, 0.5), (74, 0, 3.2), m["white"], 0.05),
           box("arm_seg2", (0.5, 0.5, 10), (81, 0, 8.0), m["white"], 0.05),
           sphere("arm_joint", 0.6, (81, 0, 3.2), m["gray"])]
    join(arm, "arm")
    export("station")


def ship():
    m = new_asset()
    # service module (aft) along X
    cyl("service", 1.5, 3.8, (-2.7, 0, 0), m["white"], 48, axis="X")
    cyl("service_band", 1.56, 0.4, (-1.0, 0, 0), m["dark"], 48, axis="X", bevel=0.03)
    cyl("service_band2", 1.56, 0.4, (-4.3, 0, 0), m["dark"], 48, axis="X", bevel=0.03)
    # main engine bell
    lathe("bell", [(0.1, 0.0), (0.45, 0.35), (0.75, 0.9), (0.95, 1.4)], m["steel"], 36, loc=(-5.9, 0, 0), axis="X")
    # crew capsule
    cap = cyl("capsule", 1.5, 3.2, (0.8, 0, 0), m["white"], 48, axis="X", r2=0.75)
    cyl("heat_shield", 1.52, 0.3, (-0.7, 0, 0), m["dark"], 48, axis="X")
    sphere("window_a", 0.22, (1.2, -1.0, 0.45), m["glass"])
    sphere("window_b", 0.22, (1.2, -1.0, -0.45), m["glass"])
    # docking probe
    cyl("probe", 0.12, 2.2, (3.5, 0, 0), m["steel"], 16, axis="X")
    cyl("drogue", 0.45, 0.25, (2.5, 0, 0), m["dark"], 24, axis="X")
    sphere("probe_tip", 0.28, (4.6, 0, 0), m["orange"])
    # solar wings (up/down so they stay visible from the side camera)
    wings = []
    for sgn in (-1, 1):
        for i in range(3):
            wings.append(box("cell", (2.0, 0.07, 1.6), (-3.2, 0, sgn * (1.9 + i * 1.75)), m["solar"]))
        wings.append(box("wing_spar", (0.18, 0.1, 5.4), (-3.2, 0, sgn * 4.3), m["frame"]))
    join(wings, "wings")
    # RCS quads
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        box("rcs_%d" % k, (0.5, 0.35, 0.35), (-1.2, math.cos(a) * 1.55, math.sin(a) * 1.55), m["dark"], 0.05, (a, 0, 0))
    sphere("nav_light", 0.15, (-4.4, -1.55, 0), m["blue"])
    export("ship")


def astronaut():
    m = new_asset()
    # facing +X, backpack at -X, up = +Z. Origin = body centre.
    box("torso", (0.55, 0.85, 0.95), (0, 0, 0), m["white"], 0.12)
    box("chest_panel", (0.06, 0.4, 0.28), (0.3, 0, 0.1), m["gray"], 0.02)
    sphere("chest_led", 0.05, (0.34, -0.12, 0.12), m["blue"])
    box("backpack", (0.5, 0.78, 0.95), (-0.5, 0, 0.0), m["gray"], 0.1)
    box("backpack_core", (0.12, 0.6, 0.7), (-0.8, 0, 0.0), m["dark"], 0.04)
    sphere("pack_led", 0.06, (-0.8, 0.25, 0.28), m["orange"])
    sphere("helmet", 0.4, (0.05, 0, 0.78), m["white"], (1, 1, 1), 40)
    sphere("visor", 0.33, (0.2, 0, 0.8), m["visor"], (0.7, 0.95, 0.72), 40)
    cyl("neck", 0.28, 0.2, (0, 0, 0.5), m["gray"], 24)
    for sy in (-1, 1):
        cyl("upper_arm_%d" % sy, 0.14, 0.55, (0.12, sy * 0.58, 0.28), m["white"], 20, bevel=0.0)
        cyl("fore_arm_%d" % sy, 0.13, 0.55, (0.42, sy * 0.64, 0.12), m["white"], 20, axis="X")
        sphere("glove_%d" % sy, 0.14, (0.72, sy * 0.64, 0.12), m["gray"])
        cyl("thigh_%d" % sy, 0.17, 0.55, (0.0, sy * 0.22, -0.72), m["white"], 20)
        cyl("shin_%d" % sy, 0.15, 0.5, (0.04, sy * 0.22, -1.2), m["white"], 20)
        box("boot_%d" % sy, (0.42, 0.24, 0.2), (0.12, sy * 0.22, -1.52), m["dark"], 0.05)
        torus("cuff_%d" % sy, 0.15, 0.03, (0.04, sy * 0.22, -1.38), m["blue"])
    box("belt", (0.58, 0.88, 0.1), (0, 0, -0.5), m["dark"], 0.03)
    export("astronaut")



def zenith_station():
    """Mission 2 station, sized to match the 2D hull rectangles of SpacewalkWorld.
    Blender (x, y, z) -> Godot (x, z, -y): the camera sits at Godot +Z = Blender -Y."""
    m = new_asset()
    cyl("main", 7.0, 40.0, (-24.0, 0, 0), m["white"], 64, axis="X")
    for xs in (-42.0, -33.0, -24.0, -15.0, -6.5):
        cyl("band", 7.08, 0.7, (xs, 0, 0), m["dark"], 64, axis="X", bevel=0.05)
    cyl("aft", 4.0, 10.0, (-49.0, 0, 0), m["gray"], 48, axis="X")
    sphere("aft_cap", 4.0, (-54.0, 0, 0), m["gray"], (0.35, 1, 1))
    cyl("airlock", 3.0, 4.0, (-6.0, 0, 0), m["white"], 48, axis="X")
    cyl("airlock_door", 2.4, 0.5, (-3.9, 0, 0), m["steel"], 48, axis="X")
    torus("hatch_ring", 2.1, 0.1, (-3.6, 0, 0), m["blue"], axis="X")
    for i in range(8):
        box("window_%d" % i, (2.2, 0.15, 1.2), (-41.0 + i * 4.6, -6.9, 2.2), m["glass"], 0.05)
        box("window_l_%d" % i, (2.2, 0.15, 1.2), (-41.0 + i * 4.6, -6.9, -2.2), m["glass"], 0.05)
    for k in range(6):
        a = k * math.pi / 3
        box("handrail_%d" % k, (30.0, 0.15, 0.15), (-24.0, -math.cos(a) * 7.15, math.sin(a) * 7.15), m["gray"])
    for sgn in (-1, 1):
        # truss mast + solar array (x -34..-18, |z| 9..31)
        parts = [box("mast", (0.8, 0.8, 24.0), (-26.0, 0, sgn * 19.0), m["frame"], 0.05)]
        for blade in (0, 1):
            bx = -34.0 + blade * 8.2 + 3.8
            n = 7
            ch = (22.0 - 0.25 * (n + 1)) / n
            for i in range(n):
                zc = sgn * (9.0 + 0.25 + i * (ch + 0.25) + ch / 2.0)
                parts.append(box("cell", (7.4, 0.12, ch), (bx, 0, zc), m["solar"]))
        parts.append(box("edge_a", (0.25, 0.2, 22.0), (-34.0, 0, sgn * 20.0), m["frame"]))
        parts.append(box("edge_b", (0.25, 0.2, 22.0), (-18.0, 0, sgn * 20.0), m["frame"]))
        join(parts, "array_%d" % sgn)
    for k in range(3):
        cyl("antenna_%d" % k, 0.12, 4, (-40.0 + k * 14.0, 2.0, 7.5), m["gray"], 10)
        sphere("dish_%d" % k, 0.8, (-40.0 + k * 14.0, 2.0, 9.6), m["white"], (1, 1, 0.3))
    export("zenith_station")


def link(name, p0, p1, r, material, seg=12):
    """Cylinder strut between two points."""
    from mathutils import Vector
    a = Vector(p0)
    b = Vector(p1)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=r, depth=d.length, location=(a + b) / 2.0)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
    bpy.ops.object.transform_apply(rotation=True)
    return _finish(o, material, 0.0, 50.0)


def lander():
    """Lunar lander: origin = ground contact point under the centre, +Z up."""
    m = new_asset()
    # descent stage (gold foil) + engine
    cyl("descent", 1.9, 1.1, (0, 0, 1.55), m["gold"], 8, bevel=0.08)
    cyl("descent_ring", 1.95, 0.18, (0, 0, 2.1), m["dark"], 8, bevel=0.03)
    lathe("engine_bell", [(0.15, 0.55), (0.42, 0.8), (0.62, 1.05), (0.7, 1.25)], m["steel"], 32, loc=(0, 0, 0.0))
    # ascent stage (white) with windows
    cyl("ascent", 1.35, 1.5, (0, 0, 3.05), m["white"], 8, bevel=0.1)
    sphere("window_a", 0.28, (1.2, -0.35, 3.3), m["glass"], (0.4, 1, 1))
    sphere("window_b", 0.28, (1.2, 0.35, 3.3), m["glass"], (0.4, 1, 1))
    cyl("ascent_cap", 1.0, 0.3, (0, 0, 3.95), m["gray"], 8, bevel=0.05)
    # landing legs + footpads
    for sx in (-1, 1):
        for sy in (-1, 1):
            link("leg", (sx * 1.2, sy * 1.2, 1.9), (sx * 3.0, sy * 3.0, 0.15), 0.1, m["steel"])
            link("brace", (sx * 1.7, sy * 1.7, 1.2), (sx * 2.4, sy * 2.4, 0.9), 0.06, m["gray"])
            cyl("foot", 0.5, 0.14, (sx * 3.0, sy * 3.0, 0.07), m["steel"], 24, bevel=0.03)
    # antenna dish, solar panels, RCS, status light
    link("mast", (0.4, 0, 3.8), (0.4, 0, 4.7), 0.06, m["steel"])
    dish = lathe("dish", [(0.05, 0.0), (0.4, 0.1), (0.8, 0.35)], m["white"], 32, loc=(0.4, 0, 4.7))
    for sy in (-1, 1):
        box("panel_%d" % sy, (2.2, 0.08, 1.0), (0, sy * 2.7, 3.2), m["solar"])
        link("panel_arm_%d" % sy, (0, sy * 1.3, 3.2), (0, sy * 1.6, 3.2), 0.05, m["steel"])
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        box("rcs_%d" % k, (0.4, 0.3, 0.3), (math.cos(a) * 1.45, math.sin(a) * 1.45, 3.7), m["dark"], 0.04, (0, 0, a))
    sphere("beacon", 0.15, (0, 0, 4.1), m["orange"])
    box("ladder", (0.08, 0.5, 1.8), (1.9, 0, 1.0), m["gray"])
    export("lander")


def rover():
    """Six-wheel rover: origin = ground contact (centre), forward = +X, +Z up."""
    m = new_asset()
    box("chassis", (1.8, 1.1, 0.4), (0, 0, 0.62), m["white"], 0.08)
    box("belly", (1.6, 0.9, 0.2), (0, 0, 0.42), m["dark"], 0.04)
    for sx in (-0.65, 0.0, 0.65):
        for sy in (-0.72, 0.72):
            cyl("wheel", 0.3, 0.24, (sx, sy, 0.3), m["dark"], 24, axis="Y", bevel=0.02)
            cyl("hub", 0.12, 0.26, (sx, sy, 0.3), m["gray"], 16, axis="Y")
            link("susp", (sx, sy * 0.78, 0.3), (sx * 0.8, sy * 0.45, 0.58), 0.04, m["steel"])
    # tilted solar panel
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.15, 0, 0.95), rotation=(0, -0.22, 0))
    pan = bpy.context.active_object
    pan.name = "solar"
    pan.scale = (1.5, 1.0, 0.05)
    bpy.ops.object.transform_apply(scale=True)
    _finish(pan, m["solar"], 0.0, 40.0)
    box("panel_frame", (1.56, 1.06, 0.03), (-0.15, 0, 0.9), m["frame"], 0.02, (0, -0.22, 0))
    # mast with camera head + dish
    link("mast", (0.55, 0, 0.8), (0.55, 0, 1.55), 0.04, m["steel"])
    box("cam_head", (0.28, 0.4, 0.18), (0.55, 0, 1.62), m["dark"], 0.03)
    sphere("lens_l", 0.05, (0.7, -0.1, 1.62), m["glass"])
    sphere("lens_r", 0.05, (0.7, 0.1, 1.62), m["glass"])
    link("dish_arm", (-0.6, 0.5, 0.82), (-0.6, 0.5, 1.2), 0.03, m["steel"])
    lathe("dish", [(0.03, 0.0), (0.18, 0.05), (0.32, 0.16)], m["white"], 24, loc=(-0.6, 0.5, 1.2))
    # instrument arm with drill
    link("arm_a", (0.9, -0.3, 0.6), (1.2, -0.3, 0.45), 0.04, m["steel"])
    link("arm_b", (1.2, -0.3, 0.45), (1.35, -0.3, 0.12), 0.035, m["gray"])
    cyl("drill", 0.06, 0.25, (1.35, -0.3, 0.05), m["orange"], 12)
    sphere("status", 0.05, (0.9, 0.35, 0.86), m["blue"])
    export("rover")


if __name__ == "__main__":
    for k in ("std", "aero"):
        nose(k)
    tank("s", 14.0)
    tank("m", 22.0)
    tank("l", 32.0)
    for k in ("spark", "kestrel", "phoenix"):
        engine(k)
    launchpad()
    satellite()
    station()
    ship()
    astronaut()
    zenith_station()
    lander()
    rover()
    print("ALL ASSETS DONE")




