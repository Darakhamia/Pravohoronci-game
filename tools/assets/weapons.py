"""Генератор ручного оружия: игрушечный бластер и нож предателя.

Запуск из корня репозитория:
    blender -b --python tools/assets/weapons.py
    blender -b --python tools/assets/weapons.py -- <папка для .glb>

Пишет pistol.glb и knife.glb (по умолчанию в assets/models/weapons/).

Договорённости для предметов в руке:
- начало координат — в точке хвата, то есть в центре кулака-варежки. Варежка занимает вокруг
  него примерно 12 x 15 x 14 см (ширина x вдоль ствола x высота), поэтому рукоять внутри кулака
  почти не видна, а всё заметное вынесено вверх и вперёд;
- ствол/клинок смотрит по +Y Blender (в Godot это -Z), верх — +Z;
- у ножа в свойствах узла записано melee = true (в Godot — метаданные extras): по ним
  PlayerVisuals и Viewmodel выбирают выпад вместо отдачи.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from mathutils import Matrix

import character_shapes as shapes
import common

DEFAULT_OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models",
        "weapons")

# --- Палитра (sRGB) ---
SHELL_COLOR = "f2f3f7"
DARK_COLOR = "20243f"
YELLOW_COLOR = "ffd23f"
CYAN_COLOR = "3ddbd9"
STEEL_COLOR = "c9cfe0"
EDGE_COLOR = "f2f3f7"
RED_COLOR = "ff5d73"

# --- Бластер ---
PISTOL_BODY_Z = 0.1          # ось ствола над точкой хвата: корпус лежит на кулаке
PISTOL_REAR_Y = -0.066
PISTOL_MUZZLE_Y = 0.19       # полная длина около 0.26 м

# --- Нож ---
KNIFE_POMMEL_Y = -0.088
KNIFE_GUARD_Y = 0.082
KNIFE_TIP_Y = 0.272          # полная длина 0.36 м: рукоять под варежку, остальное — клинок


def y_lathe(name, profile, mat, segments=14, squash=(1.0, 1.0)):
    """Тело вращения вокруг оси Y: profile = [(радиус, y), ...] от казённика к дулу."""
    obj = shapes.lathe(name, profile, segments=segments, mat=mat, squash=squash)
    # Ось Z профиля -> ось Y модели.
    return shapes.transform(obj, Matrix.Rotation(math.radians(-90.0), 4, "X"))


def export(path):
    """Как common.export_glb, но со свойствами узлов (extras) — по ним игра узнаёт оружие ближнего боя."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
            export_animations=False, export_extras=True)
    print("EXPORTED", path)


def report(name):
    obj = bpy.data.objects[name]
    xs = [vertex.co for vertex in obj.data.vertices]
    print("MODEL %s tris=%d  min=(%.3f, %.3f, %.3f)  max=(%.3f, %.3f, %.3f)" % (name, shapes.triangle_count(),
            min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs),
            max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))


def build_pistol(path):
    common.reset_scene()
    shell = common.material("BlasterShell", SHELL_COLOR, roughness=0.4)
    dark = common.material("BlasterDark", DARK_COLOR, roughness=0.5)
    yellow = common.material("BlasterAccent", YELLOW_COLOR, roughness=0.4)
    glow = common.material("BlasterGlow", CYAN_COLOR, roughness=0.3, emission=CYAN_COLOR, emission_strength=2.8)
    z = PISTOL_BODY_Z
    parts = []
    # Рукоять: почти вся внутри кулака, наружу торчит пятка.
    grip = common.rounded_box("Grip", (0.04, 0.056, 0.15), (0.0, -0.018, -0.005), bevel=0.014, segments=2, mat=dark)
    shapes.rotate_about(grip, (0.0, 0.0, 0.06), "X", 14.0)
    parts.append(grip)
    # Корпус: пухлый «кирпичик» со скошенным носом.
    body = [(-0.04, z - 0.036), (0.085, z - 0.036), (0.112, z - 0.02), (0.112, z + 0.03), (0.09, z + 0.04),
            (-0.04, z + 0.04), (PISTOL_REAR_Y, z + 0.012), (PISTOL_REAR_Y, z - 0.012)]
    parts.append(shapes.extrude_profile("Body", body, 0.056, bevel=0.012, segments=2, mat=shell, plane="YZ"))
    # Бак энергии сзади и кожух ствола спереди.
    # Его радиус больше диагонали сечения корпуса у казённика: стык получается ровным кольцом.
    parts.append(y_lathe("Tank", [(0.0, PISTOL_REAR_Y - 0.008), (0.026, PISTOL_REAR_Y - 0.006), (0.042, PISTOL_REAR_Y + 0.002),
            (0.045, PISTOL_REAR_Y + 0.01), (0.042, PISTOL_REAR_Y + 0.016), (0.03, PISTOL_REAR_Y + 0.02)], yellow))
    shapes.move(parts[-1], (0.0, 0.0, z + 0.002))
    parts.append(y_lathe("TankKnob", [(0.0, PISTOL_REAR_Y - 0.016), (0.014, PISTOL_REAR_Y - 0.014),
            (0.016, PISTOL_REAR_Y - 0.004)], dark, segments=10))
    shapes.move(parts[-1], (0.0, 0.0, z + 0.002))
    barrel = y_lathe("Barrel", [(0.027, 0.1), (0.029, 0.112), (0.029, 0.15), (0.024, 0.156), (0.024, 0.166),
            (0.033, 0.174), (0.035, PISTOL_MUZZLE_Y - 0.004), (0.028, PISTOL_MUZZLE_Y), (0.02, PISTOL_MUZZLE_Y - 0.012),
            (0.0, PISTOL_MUZZLE_Y - 0.012)], yellow)
    parts.append(shapes.move(barrel, (0.0, 0.0, z)))
    for ring_y in (0.122, 0.14):
        ring = y_lathe("CoolingRing", [(0.027, ring_y - 0.006), (0.034, ring_y - 0.004), (0.034, ring_y + 0.004),
                (0.027, ring_y + 0.006)], dark)
        parts.append(shapes.move(ring, (0.0, 0.0, z)))
    core = y_lathe("MuzzleCore", [(0.0, PISTOL_MUZZLE_Y - 0.016), (0.02, PISTOL_MUZZLE_Y - 0.016),
            (0.02, PISTOL_MUZZLE_Y - 0.009), (0.0, PISTOL_MUZZLE_Y - 0.009)], glow, segments=10)
    parts.append(shapes.move(core, (0.0, 0.0, z)))
    # Светящиеся окошки заряда по бокам.
    for side in (-1.0, 1.0):
        window = shapes.extrude_profile("ChargeWindow", shapes.pill(0.078, 0.02, 3, (0.012, z + 0.006)), 0.006,
                (side * 0.028, 0.0, 0.0), mat=glow, plane="YZ")
        parts.append(window)
    # Прицельная планка и спусковая скоба.
    parts.append(common.rounded_box("Sight", (0.016, 0.1, 0.014), (0.0, 0.01, z + 0.044), bevel=0.005, segments=1,
            mat=dark))
    parts.append(common.rounded_box("SightFin", (0.012, 0.022, 0.024), (0.0, -0.035, z + 0.05), bevel=0.005,
            segments=1, mat=dark))
    guard = [(0.03, z - 0.03), (0.03, z - 0.074), (0.04, z - 0.086), (0.082, z - 0.086), (0.096, z - 0.07),
            (0.1, z - 0.03), (0.088, z - 0.03), (0.085, z - 0.066), (0.077, z - 0.074), (0.045, z - 0.074),
            (0.042, z - 0.066), (0.042, z - 0.03)]
    parts.append(shapes.extrude_profile("TriggerGuard", guard, 0.018, bevel=0.004, segments=1, mat=dark, plane="YZ"))
    parts.append(common.rounded_box("Trigger", (0.01, 0.01, 0.03), (0.0, 0.07, z - 0.05), bevel=0.004, segments=1,
            mat=yellow))
    for part in parts:
        shapes.freeze(part)
    common.join(parts, "Pistol")
    report("Pistol")
    export(path)


def build_knife(path):
    common.reset_scene()
    steel = common.material("KnifeSteel", STEEL_COLOR, roughness=0.22, metallic=0.55)
    edge = common.material("KnifeEdge", EDGE_COLOR, roughness=0.15, metallic=0.3)
    dark = common.material("KnifeHandle", DARK_COLOR, roughness=0.55)
    red = common.material("KnifeAccent", RED_COLOR, roughness=0.35, emission=RED_COLOR, emission_strength=0.3)
    parts = []
    # Рукоять прячется в кулаке; сзади торчит навершие, спереди — гарда.
    handle = y_lathe("Handle", [(0.0, KNIFE_POMMEL_Y + 0.012), (0.02, KNIFE_POMMEL_Y + 0.014), (0.024, -0.03),
            (0.021, 0.03), (0.023, KNIFE_GUARD_Y - 0.006), (0.0, KNIFE_GUARD_Y - 0.004)], dark, segments=10,
            squash=(0.8, 1.15))
    parts.append(handle)
    pommel = y_lathe("Pommel", [(0.0, KNIFE_POMMEL_Y), (0.02, KNIFE_POMMEL_Y + 0.002), (0.028, KNIFE_POMMEL_Y + 0.012),
            (0.028, KNIFE_POMMEL_Y + 0.022), (0.02, KNIFE_POMMEL_Y + 0.03)], red, segments=10, squash=(0.8, 1.15))
    parts.append(pommel)
    parts.append(common.rounded_box("Guard", (0.036, 0.02, 0.1), (0.0, KNIFE_GUARD_Y, -0.006), bevel=0.009, segments=2,
            mat=red))
    # Клинок: широкий «шеф-нож» с опущенной пяткой и хищным скосом к острию.
    heel = KNIFE_GUARD_Y + 0.006
    tip = KNIFE_TIP_Y
    blade = [(heel, 0.034), (tip - 0.07, 0.034), (tip - 0.03, 0.022), (tip, -0.008), (tip - 0.012, -0.024),
            (tip - 0.04, -0.04), (tip - 0.085, -0.05), (heel + 0.012, -0.052), (heel, -0.042)]
    parts.append(shapes.extrude_profile("Blade", blade, 0.012, bevel=0.004, segments=1, mat=steel, plane="YZ"))
    # Заточка: светлая кромка вдоль лезвия, чуть уже клинка.
    bevel_edge = [(heel + 0.004, -0.036), (tip - 0.085, -0.036), (tip - 0.045, -0.027), (tip - 0.018, -0.012),
            (tip + 0.003, -0.008), (tip - 0.01, -0.027), (tip - 0.04, -0.044), (tip - 0.085, -0.055),
            (heel + 0.012, -0.057), (heel + 0.002, -0.047)]
    parts.append(shapes.extrude_profile("BladeEdge", bevel_edge, 0.007, mat=edge, plane="YZ"))
    # Красная вставка-дол: выдаёт нож предателя издалека.
    for side in (-1.0, 1.0):
        parts.append(shapes.extrude_profile("Fuller", shapes.pill(0.1, 0.012, 3, ((heel + tip) * 0.5 - 0.02, 0.014)),
                0.004, (side * 0.006, 0.0, 0.0), mat=red, plane="YZ"))
    for part in parts:
        shapes.freeze(part)
    knife = common.join(parts, "Knife")
    knife["melee"] = True
    report("Knife")
    export(path)


def main():
    args = common.script_args()
    out_dir = os.path.abspath(args[0] if args else DEFAULT_OUT_DIR)
    os.makedirs(out_dir, exist_ok=True)
    build_pistol(os.path.join(out_dir, "pistol.glb"))
    build_knife(os.path.join(out_dir, "knife.glb"))


main()
