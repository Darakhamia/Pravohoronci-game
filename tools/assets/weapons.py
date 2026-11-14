"""Генератор ручного оружия: компактный энергетический пистолет и боевой нож предателя.

Запуск из корня репозитория:
    blender -b --python tools/assets/weapons.py
    blender -b --python tools/assets/weapons.py -- <папка для .glb>

Пишет pistol.glb и knife.glb (по умолчанию в assets/models/weapons/).

Договорённости для предметов в руке:
- начало координат — в точке хвата, в центре кулака. Кулак персонажа (tools/assets/character.py,
  форма кисти Grip) оставляет под рукоять проём примерно 3.5 x 6 см и закрывает её на 5 см вверх
  и вниз от начала координат; указательный палец идёт на высоте 2.5–5 см — у пистолета там
  скоба и спуск (форма кисти Trigger кладёт палец на спуск, большой палец — вдоль рамки);
- ствол/клинок смотрит по +Y Blender (в Godot это -Z), верх — +Z;
- у ножа в свойствах узла записано melee = true (в Godot — метаданные extras): по ним
  PlayerVisuals и Viewmodel берут нож «молотковым» хватом и колют вместо отдачи.

Материалы — заглушки с именами: при импорте Godot подменяет их ресурсами из
resources/materials/characters/ (см. .glb.import и tools/textures/character_materials.py).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mathutils import Matrix

import character_shapes as shapes
from character_shapes import Piece

DEFAULT_OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models",
        "weapons")

GUNMETAL = "WeaponGunmetal"  # затвор, гарда
STEEL = "WeaponSteel"        # клинок, ствол, спуск
EDGE = "WeaponEdge"          # заточка: полированная сталь
POLYMER = "WeaponPolymer"    # рамка
GRIP = "WeaponGrip"          # прорезиненные накладки
ACCENT = "WeaponAccent"      # красное анодирование: примета ножа предателя
GLOW = "WeaponGlow"          # индикатор заряда
SIGHT = "WeaponSight"        # светящиеся точки прицела
MATERIALS = {
    GUNMETAL: ("3a3d44", 0.5, 1.0, None),
    STEEL: ("b9bcc2", 0.35, 1.0, None),
    EDGE: ("e8e9ec", 0.2, 1.0, None),
    POLYMER: ("202227", 0.6, 0.0, None),
    GRIP: ("18191c", 0.85, 0.0, None),
    ACCENT: ("b21a14", 0.4, 1.0, None),
    GLOW: ("3ddbd9", 0.3, 0.0, "3ddbd9"),
    SIGHT: ("7dff66", 0.3, 0.0, "7dff66"),
}
shapes.UV_SCALE.update({GUNMETAL: 5.0, STEEL: 4.0, EDGE: 4.0, POLYMER: 10.0, GRIP: 25.0, ACCENT: 4.0})

# --- Пистолет (ось ствола над точкой хвата) ---
BORE_Z = 0.082
SLIDE_REAR_Y = -0.07
SLIDE_FRONT_Y = 0.168        # полная длина с дульным срезом — около 0.25 м
SLIDE_HALF_WIDTH = 0.0148

# --- Нож ---
KNIFE_POMMEL_Y = -0.078
KNIFE_GUARD_Y = 0.055
KNIFE_TIP_Y = 0.252          # полная длина 0.33 м
BLADE_THICKNESS = 0.0046
BLADE_SPINE_Z = 0.017
BLADE_EDGE_Z = -0.019
BLADE_GRIND = 0.011          # высота спусков от режущей кромки


def make_materials():
    for name, (color, roughness, metallic, emission) in MATERIALS.items():
        shapes.make_material(name, color, roughness, metallic, emission, 2.5)


def lathe_y(profile, mat, segments, center=(0.0, 0.0, 0.0), **kwargs):
    """Тело вращения вокруг оси Y: profile = [(радиус, y), ...] от казённика к дулу."""
    geo = shapes.lathe(profile, mat, segments, **kwargs)
    geo.transform(Matrix.Rotation(math.radians(-90.0), 4, "X"))
    return geo.move(center)


def slab(outline, thickness, mat, bevel=0.0015):
    """Пластина в продольной плоскости: контур [(y, z), ...] против часовой, толщина по X."""
    return shapes.extrude(outline, thickness, mat, "YZ", bevel)


def build_pistol(path):
    shapes.reset_scene()
    make_materials()
    piece = Piece("Pistol")
    half = SLIDE_HALF_WIDTH
    front = SLIDE_FRONT_Y
    rear = SLIDE_REAR_Y
    # Рукоять: наклонена назад, сверху «бобровый хвост» над перепонкой ладони. Три пальца
    # обхватывают её под скобой, указательный лежит внутри скобы на спуске.
    piece.add(slab([(-0.044, -0.056), (0.006, -0.053), (0.047, 0.047), (-0.022, 0.047), (-0.03, 0.0)], 0.029, POLYMER, 0.004))
    piece.add(slab([(-0.038, -0.048), (0.004, -0.046), (0.036, 0.03), (-0.022, 0.03)], 0.0335, GRIP, 0.002))
    # Энергоячейка в пятке рукояти.
    piece.add(slab([(-0.049, -0.068), (0.009, -0.065), (0.011, -0.052), (-0.047, -0.055)], 0.033, GUNMETAL, 0.003))
    piece.add(shapes.box((0.016, 0.004, 0.0055), (0.0, -0.049, -0.0615), GLOW, 0.001, 1, 1))
    # Рамка с пылезащитной крышкой под стволом.
    piece.add(slab([(-0.048, 0.046), (0.108, 0.046), (0.112, 0.037), (0.16, 0.037), (0.165, 0.046), (0.165, 0.0665),
            (-0.062, 0.0665), (-0.075, 0.06), (-0.052, 0.054)], 0.0285, POLYMER, 0.002))
    # Подствольный модуль с фонарём-целеуказателем.
    piece.add(shapes.box((0.024, 0.056, 0.021), (0.0, 0.134, 0.027), GUNMETAL, 0.004, 1, 2))
    piece.add(lathe_y([(0.0, 0.158), (0.0075, 0.158), (0.0075, 0.1635), (0.0, 0.1635)], GLOW, 10, (0.0, 0.0, 0.027)))
    piece.add(shapes.box((0.027, 0.012, 0.007), (0.0, 0.126, 0.03), POLYMER, 0.002, 1, 1))
    # Затвор: гранёный верх, насечка, окно выброса.
    section = [(-half, 0.066), (half, 0.066), (half, 0.09), (0.0095, 0.0995), (-0.0095, 0.0995), (-half, 0.09)]
    piece.add(shapes.extrude(section, front - rear, GUNMETAL, "XZ", 0.0015, (front + rear) * 0.5))
    for index in range(6):
        piece.add(shapes.box((half * 2.0 + 0.0016, 0.0034, 0.02), (0.0, rear + 0.012 + index * 0.0068, 0.0785), POLYMER,
                0.0008, 1, 1))
    for index in range(4):
        piece.add(shapes.box((half * 2.0 + 0.0016, 0.0034, 0.015), (0.0, front - 0.03 + index * 0.0068, 0.0795), POLYMER,
                0.0008, 1, 1))
    piece.add(shapes.box((0.014, 0.036, 0.004), (0.005, 0.03, 0.0985), STEEL, 0.001, 1, 1))
    piece.add(shapes.box((0.004, 0.036, 0.012), (half, 0.03, 0.091), STEEL, 0.001, 1, 1))
    # Окна накопителя по бокам затвора: видно, как светится заряд.
    for side in (-1.0, 1.0):
        for index in range(4):
            piece.add(shapes.box((0.003, 0.012, 0.0065), (side * half, 0.07 + index * 0.017, 0.077), GLOW, 0.001, 1, 1))
        piece.add(shapes.box((0.0024, 0.074, 0.011), (side * (half - 0.0004), 0.0955, 0.077), POLYMER, 0.001, 1, 1))
    # Дульный срез: ствол с каналом и светящаяся направляющая под ним.
    piece.add(lathe_y([(0.0045, front - 0.004), (0.0078, front - 0.004), (0.0078, front + 0.006), (0.0045, front + 0.006)],
            STEEL, 12, (0.0, 0.0, BORE_Z), closed=True))
    piece.add(lathe_y([(0.0, front - 0.002), (0.0046, front - 0.002)], POLYMER, 10, (0.0, 0.0, BORE_Z)))
    piece.add(lathe_y([(0.0, front - 0.002), (0.0036, front - 0.002), (0.0036, front + 0.0015), (0.0, front + 0.0015)], GLOW, 8,
            (0.0, 0.0, 0.0715)))
    # Задняя пластина затвора с индикатором заряда: его видит стрелок.
    piece.add(shapes.box((0.023, 0.003, 0.022), (0.0, rear - 0.0006, 0.0785), POLYMER, 0.001, 1, 1))
    for index in range(3):
        piece.add(shapes.box((0.0046, 0.002, 0.0095), (-0.0064 + index * 0.0064, rear - 0.002, 0.0785), GLOW, 0.0006, 1, 1))
    # Прицел: целик с прорезью и мушка, на них светящиеся точки.
    for side in (-1.0, 1.0):
        piece.add(shapes.box((0.008, 0.009, 0.0075), (side * 0.007, rear + 0.012, 0.1025), GUNMETAL, 0.001, 1, 1))
        piece.add(shapes.box((0.003, 0.002, 0.003), (side * 0.007, rear + 0.0072, 0.1032), SIGHT, 0.0005, 1, 1))
    piece.add(shapes.box((0.023, 0.009, 0.004), (0.0, rear + 0.012, 0.1), GUNMETAL, 0.001, 1, 1))
    piece.add(slab([(front - 0.018, 0.0985), (front - 0.006, 0.0985), (front - 0.009, 0.1065), (front - 0.014, 0.1065)],
            0.0042, GUNMETAL, 0.0006))
    piece.add(shapes.box((0.003, 0.002, 0.003), (0.0, front - 0.0146, 0.1035), SIGHT, 0.0005, 1, 1))
    # Спусковая скоба (под ней — средний палец) и спуск.
    piece.add(slab([(0.03, 0.019), (0.097, 0.019), (0.108, 0.03), (0.108, 0.046), (0.102, 0.046), (0.102, 0.032),
            (0.094, 0.0255), (0.03, 0.0255)], 0.013, POLYMER, 0.0015))
    piece.add(slab([(0.066, 0.046), (0.071, 0.046), (0.0695, 0.038), (0.073, 0.0295), (0.069, 0.028), (0.064, 0.038)],
            0.0062, GUNMETAL, 0.001))
    # Рычаги: задержка затвора и предохранитель.
    piece.add(shapes.box((0.0035, 0.024, 0.0045), (-half - 0.0004, 0.022, 0.0615), GUNMETAL, 0.001, 1, 1))
    piece.add(lathe_y([(0.0, 0.0), (0.0042, 0.0), (0.0042, 0.003), (0.0, 0.003)], GUNMETAL, 8).rotate("Z", 90.0).move(
            (-half - 0.0005, -0.034, 0.058)))
    obj = shapes.build_object(piece)
    shapes.report()
    shapes.export_glb(path, extras=True)
    return obj


def _blade_station(y):
    """Сечение клинка на расстоянии y: (обух z, линия спусков z, кромка z, толщина)."""
    belly_from = 0.165
    clip_from = 0.176
    spine = BLADE_SPINE_Z
    edge = BLADE_EDGE_Z
    grind = BLADE_GRIND
    thickness = BLADE_THICKNESS
    if y > belly_from:
        t = (y - belly_from) / (KNIFE_TIP_Y - belly_from)
        edge += (0.003 - BLADE_EDGE_Z) * t * t
        grind *= 1.0 - 0.8 * t
    if y > clip_from:
        t = (y - clip_from) / (KNIFE_TIP_Y - clip_from)
        spine += (0.003 - BLADE_SPINE_Z) * (t ** 1.35)
        thickness *= 1.0 - 0.86 * t
    return spine, min(edge + grind, spine - 0.0005), edge, thickness


def build_blade():
    """Клинок с настоящим клиновидным сечением: плоскости — матовая сталь, спуски — полированная."""
    geo = shapes.Geo()
    stations = [KNIFE_GUARD_Y - 0.004, 0.09, 0.13, 0.165, 0.176, 0.19, 0.205, 0.22, 0.235, 0.246]
    rows = []
    for y in stations:
        spine, grind, edge, thickness = _blade_station(y)
        half = thickness * 0.5
        rows.append([geo.add_vert((-half, y, spine)), geo.add_vert((half, y, spine)), geo.add_vert((half, y, grind)),
                geo.add_vert((0.0, y, edge)), geo.add_vert((-half, y, grind))])
    tip = geo.add_vert((0.0, KNIFE_TIP_Y, 0.003))
    mats = (STEEL, STEEL, EDGE, EDGE, STEEL)
    for near, far in zip(rows, rows[1:]):
        for index in range(5):
            following = (index + 1) % 5
            geo.add_face((near[index], far[index], far[following], near[following]), mats[index])
    for index in range(5):
        following = (index + 1) % 5
        geo.add_face((rows[-1][index], tip, rows[-1][following]), mats[index])
    geo.add_face(tuple(reversed(rows[0])), STEEL)
    return geo.orient_outward()


def build_knife(path):
    shapes.reset_scene()
    make_materials()
    piece = Piece("Knife")
    oval = (0.8, 1.0)
    # Рукоять с выемками под пальцы: вращение вокруг Y, сечение — овал (уже по X).
    piece.add(lathe_y([(0.0, -0.058), (0.0135, -0.057), (0.0168, -0.046), (0.0148, -0.031), (0.017, -0.016),
            (0.0148, -0.001), (0.017, 0.014), (0.0148, 0.029), (0.0166, 0.041), (0.0155, 0.05), (0.0, 0.05)], GRIP, 14,
            squash=oval))
    # Навершие-стеклобой с красным кольцом и отверстием под темляк.
    piece.add(lathe_y([(0.0, KNIFE_POMMEL_Y), (0.007, KNIFE_POMMEL_Y + 0.001), (0.0155, KNIFE_POMMEL_Y + 0.008),
            (0.0175, KNIFE_POMMEL_Y + 0.014), (0.0175, -0.06), (0.0, -0.06)], GUNMETAL, 14, squash=oval))
    piece.add(lathe_y(_ring(-0.062, -0.056, 0.0182), ACCENT, 14, squash=oval, closed=True))
    piece.add(lathe_y([(0.0, 0.0), (0.0042, 0.0), (0.0042, 0.03), (0.0, 0.03)], POLYMER, 8).rotate("Z", 90.0).move(
            (0.015, KNIFE_POMMEL_Y + 0.011, 0.0)))
    # Гарда: стальная, нижний ус длиннее; за ней красное кольцо.
    piece.add(lathe_y(_ring(0.045, 0.051, 0.0182), ACCENT, 14, squash=oval, closed=True))
    piece.add(shapes.box((0.027, 0.0085, 0.066), (0.0, KNIFE_GUARD_Y - 0.0015, -0.005), GUNMETAL, 0.0035, 1, 2))
    piece.add(build_blade())
    # Дол: тёмная канавка вдоль обуха; насечка под большой палец.
    for side in (-1.0, 1.0):
        piece.add(shapes.box((0.0012, 0.092, 0.0042), (side * BLADE_THICKNESS * 0.5, 0.118, 0.0085), GUNMETAL, 0.0004, 1, 1))
    for index in range(5):
        piece.add(shapes.box((BLADE_THICKNESS + 0.0006, 0.003, 0.003), (0.0, 0.066 + index * 0.0062, BLADE_SPINE_Z),
                GUNMETAL, 0.0006, 1, 1))
    obj = shapes.build_object(piece)
    obj["melee"] = True
    shapes.report()
    shapes.export_glb(path, extras=True)
    return obj


def _ring(y_low, y_high, radius, thickness=0.006):
    inner = radius - thickness
    return [(inner, y_low), (radius - 0.001, y_low), (radius, y_low + 0.001), (radius, y_high - 0.001),
            (radius - 0.001, y_high), (inner, y_high)]


def main():
    args = shapes.script_args()
    out_dir = os.path.abspath(args[0] if args else DEFAULT_OUT_DIR)
    os.makedirs(out_dir, exist_ok=True)
    build_pistol(os.path.join(out_dir, "pistol.glb"))
    build_knife(os.path.join(out_dir, "knife.glb"))


main()
