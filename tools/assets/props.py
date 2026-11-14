"""Реквизит станции: игровые станции (задания, реактор, канистры, кнопка собрания) и декор.

Запуск из корня репозитория:
    blender -b --python tools/assets/props.py                       все модели -> assets/models/props/*.glb
    blender -b --python tools/assets/props.py -- canister barrel    только названные
    blender -b --python tools/assets/props.py -- --prefabs          заодно переписать префабы декора
                                                                    scenes/maps/props/*.tscn

Общие правила: низ на Z = 0, начало координат — центр основания на полу, перёд смотрит по +Y Blender (-Z Godot).
У мебели перёд — сторона, с которой к ней подходит человек. Исключения:
- task_panel: начало координат в центре ЗАДНЕЙ стенки (щиток вешают на стену на высоте около 1,3 м);
- настенный декор (pipes, vent_grate, whiteboard): начало координат на плоскости стены на уровне пола,
  высота подвеса уже заложена в модель.

Игровой реквизит (GAMEPLAY_BUILDERS) префабов не получает: их собирает игровой код. Подвижные части у таких
моделей — отдельные узлы с началом координат в точке вращения (оси указаны для Godot):
- task_calibrator: Needle (стрелка, вращать вокруг локальной Z), Lever (рычаг, вокруг локальной X);
- reactor_core: Glow (светящееся ядро — можно менять материал или масштаб);
- reactor_panel: Wheel (вентиль, вращать вокруг локальной Y);
- emergency_button: Button (гриб кнопки, утапливать по локальной Y), Cover (крышка, откидывать вокруг локальной X);
- canister_dock: гнездо для канистры — точка (0, 0.745, 0) в координатах Godot.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from environment_lib import (Frame, Model, arc_points, ball, bar, bolt, box, cyl, lathe, prism,  # noqa: E402
        ring_prism, rounded_rect_points, run_generator, torus, tube)
import environment_decor  # noqa: E402

MODEL_DIR = "assets/models/props"
PREFAB_DIR = "scenes/maps/props"


def _polar(radius, angle_deg, z=0.0):
    angle = math.radians(angle_deg)
    return (radius * math.cos(angle), radius * math.sin(angle), z)


# ---------- Задания ----------

def build_task_panel():
    """Настенный щиток с открытым люком и проводами, 0,8 x 0,6 м. Начало координат — центр задней стенки."""
    model = Model("task_panel")
    model.add(box((0.88, 0.04, 0.68), (0.0, 0.02, 0.0), "panel", bevel=0.008))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            model.add(bolt((sx * 0.415, 0.042, sz * 0.315), axis="y", radius=0.011))
    model.add(box((0.80, 0.10, 0.60), (0.0, 0.06, 0.0), "grey", bevel=0.018, segments=3))
    # Крышка корпуса на четырёх винтах, по краю — тёмный шов.
    seam_outer = rounded_rect_points(0.77, 0.57, 0.03)
    seam_inner = rounded_rect_points(0.76, 0.56, 0.028)
    model.add(ring_prism(seam_outer, seam_inner, 0.002, "rubber", plane="xz", offset=0.110))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            model.add(bolt((sx * 0.355, 0.112, sz * 0.265), axis="y", radius=0.009, material="chrome", depth=0.006))
    hatch_x = -0.13
    model.add(box((0.44, 0.02, 0.44), (hatch_x, 0.105, 0.0), "rubber", bevel=0.0))
    outer = rounded_rect_points(0.52, 0.52, 0.07, center=(hatch_x, 0.0))
    inner = rounded_rect_points(0.42, 0.42, 0.04, center=(hatch_x, 0.0))
    model.add(ring_prism(outer, inner, 0.035, "yellow", plane="xz", offset=0.10, bevel=0.006))
    # Клеммные колодки и провода: три целых и один оборванный с искрой.
    terminals = [hatch_x - 0.135, hatch_x - 0.045, hatch_x + 0.045, hatch_x + 0.135]
    for z in (0.16, -0.16):
        model.add(box((0.38, 0.018, 0.06), (hatch_x, 0.122, z), "white", bevel=0.005))
        for x in terminals:
            model.add(cyl(0.017, 0.016, (x, 0.135, z), "grey", axis="y", bevel=0.003, vertices=12))
            model.add(bar((0.022, 0.004, 0.004), (x, 0.144, z), "rubber", bevel=0.0))

    def wire(top, bottom, material, bulge):
        x0, x1 = terminals[top], terminals[bottom]
        model.add(tube([(x0, 0.14, 0.16), (x0, 0.14 + bulge * 0.7, 0.09), ((x0 + x1) / 2.0, 0.14 + bulge, 0.0),
                (x1, 0.14 + bulge * 0.7, -0.09), (x1, 0.14, -0.16)], 0.011, material))

    wire(0, 2, "cyan", 0.07)
    wire(1, 0, "green", 0.045)
    wire(3, 3, "yellow", 0.03)
    model.add(tube([(terminals[2], 0.14, 0.16), (terminals[2] + 0.01, 0.19, 0.10), (terminals[2] + 0.05, 0.23, 0.05)],
            0.011, "red"))
    model.add(tube([(terminals[1], 0.14, -0.16), (terminals[1] + 0.02, 0.19, -0.11), (terminals[1] + 0.07, 0.24, -0.09)],
            0.011, "red"))
    for tip in ((terminals[2] + 0.055, 0.235, 0.045), (terminals[1] + 0.075, 0.245, -0.088)):
        model.add(cyl(0.006, 0.02, tip, "chrome", axis="y", vertices=8))
        model.add(ball(0.018, (tip[0], tip[1] + 0.012, tip[2]), "glow_yellow"))
    # Дверца люка распахнута влево, висит на двух петлях.
    hinge_x = hatch_x - 0.24
    angle = math.radians(108.0)
    door_center = (hinge_x + 0.22 * math.cos(angle), 0.135 + 0.22 * math.sin(angle), 0.0)
    model.add(box((0.46, 0.022, 0.46), door_center, "yellow", bevel=0.008, rot=(0.0, 0.0, angle)))
    handle = (hinge_x + 0.38 * math.cos(angle) - 0.03, 0.135 + 0.38 * math.sin(angle), 0.0)
    model.add(box((0.03, 0.05, 0.12), handle, "rubber", bevel=0.01, rot=(0.0, 0.0, angle)))
    for z in (0.15, -0.15):
        model.add(cyl(0.016, 0.08, (hinge_x, 0.13, z), "grey", vertices=12))
    # Правая колонка: лампочки в оправах и табличка с полосами.
    for z, material in ((0.19, "glow_green"), (0.10, "glow_yellow"), (0.01, "glow_red")):
        model.add(cyl(0.034, 0.012, (0.27, 0.114, z), "chrome", axis="y", bevel=0.003, vertices=16))
        model.add(cyl(0.025, 0.03, (0.27, 0.118, z), material, axis="y", bevel=0.008, vertices=16))
    model.add(box((0.16, 0.008, 0.12), (0.27, 0.112, -0.16), "yellow", bevel=0.003))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            model.add(bolt((0.27 + sx * 0.068, 0.116, -0.16 + sz * 0.048), axis="y", radius=0.004, depth=0.003))
    for index in range(3):
        x = 0.215 + 0.04 * index
        model.add(prism([(x, -0.2), (x + 0.018, -0.2), (x + 0.04, -0.12), (x + 0.022, -0.12)], 0.003, "rubber",
                plane="xz", offset=0.116))
    model.add(cyl(0.028, 0.03, (0.2, 0.06, -0.31), "grey", bevel=0.005, vertices=12))
    return model, None, []


def build_task_keypad():
    """Стойка-терминал с экраном и цифровой клавиатурой, высота 1,3 м."""
    model = Model("task_keypad")
    model.add(box((0.52, 0.44, 0.05), (0.0, 0.0, 0.035), "panel", bevel=0.012))
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            model.add(cyl(0.03, 0.012, (sx * 0.21, sy * 0.17, 0.006), "rubber", vertices=10))
            model.add(bolt((sx * 0.21, sy * 0.17, 0.062), radius=0.013))
    model.add(box((0.20, 0.16, 0.86), (0.0, -0.04, 0.48), "white", bevel=0.02, segments=3))
    model.add(box((0.23, 0.19, 0.08), (0.0, -0.04, 0.24), "yellow", bevel=0.012))
    # Сервисная крышка на стойке и шильдик.
    model.add(box((0.14, 0.006, 0.30), (0.0, 0.041, 0.52), "white", bevel=0.002))
    for sx in (-1.0, 1.0):
        for z in (0.39, 0.65):
            model.add(bolt((sx * 0.055, 0.045, z), axis="y", radius=0.006, material="chrome", depth=0.004))
    model.add(box((0.09, 0.004, 0.035), (0.0, 0.045, 0.74), "chrome", bevel=0.0015))
    model.add(tube([(0.0, -0.12, 0.30), (0.0, -0.17, 0.22), (0.02, -0.19, 0.08), (0.06, -0.21, 0.02)], 0.012, "rubber"))
    head = Frame((0.0, 0.01, 1.0), (math.radians(24.0), 0.0, 0.0))
    model.add(box((0.58, 0.13, 0.62), head.at(0.0, 0.0, 0.0), "line", bevel=0.025, segments=3, rot=head.rot))
    model.add(box((0.62, 0.05, 0.10), head.at(0.0, 0.05, 0.30), "yellow", bevel=0.012, rot=head.rot))
    for sx in (-1.0, 1.0):
        for z in (-0.27, 0.22):
            model.add(cyl(0.008, 0.006, head.at(sx * 0.262, 0.066, z), "chrome", rot=head.rot_axis("y"), vertices=8))
    model.add(box((0.48, 0.02, 0.25), head.at(0.0, 0.065, 0.13), "rubber", bevel=0.006, rot=head.rot))
    model.add(box((0.43, 0.02, 0.20), head.at(0.0, 0.071, 0.13), "screen", bevel=0.004, rot=head.rot))
    for index in range(4):
        model.add(box((0.045, 0.012, 0.045), head.at(-0.105 + 0.07 * index, 0.08, 0.13), "glow_cyan", bevel=0.004,
                rot=head.rot))
    model.add(box((0.37, 0.012, 0.31), head.at(0.0, 0.064, -0.153), "grey", bevel=0.004, rot=head.rot))
    for row in range(4):
        for column in range(3):
            material = "white"
            if row == 3 and column == 2:
                material = "red"
            if row == 3 and column == 0:
                material = "green"
            model.add(box((0.095, 0.03, 0.058), head.at(-0.115 + 0.115 * column, 0.072, -0.045 - 0.072 * row),
                    material, bevel=0.008, rot=head.rot))
    return model, None, []


def build_task_calibrator():
    """Калибратор: шкаф в крашеной эмали с большой шкалой под стеклом и рычагом, высота 1,4 м."""
    model = Model("task_calibrator")
    model.add(box((0.90, 0.60, 0.07), (0.0, 0.0, 0.055), "panel", bevel=0.012))
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            model.add(cyl(0.045, 0.03, (sx * 0.38, sy * 0.23, 0.015), "rubber", bevel=0.006, vertices=12))
    model.add(box((0.86, 0.56, 0.80), (0.0, 0.0, 0.49), "enamel_violet", bevel=0.03, segments=3))
    model.add(box((0.92, 0.62, 0.06), (0.0, 0.0, 0.905), "white", bevel=0.014))
    # Стыки панелей корпуса, винты по углам лицевой панели, ручки для переноски, шильдик.
    for z in (0.345, 0.76):
        model.add(bar((0.862, 0.562, 0.006), (0.0, 0.0, z), "rubber", axis="z", bevel=0.0))
    for sx in (-1.0, 1.0):
        for z in (0.14, 0.31, 0.39, 0.72, 0.80, 0.85):
            model.add(bolt((sx * 0.385, 0.281, z), axis="y", radius=0.01, material="chrome", depth=0.006))
    model.add(tube([(-0.435, 0.12, 0.66), (-0.475, 0.12, 0.64), (-0.475, -0.12, 0.64), (-0.435, -0.12, 0.66)], 0.012,
            "chrome", smooth=False))
    model.add(box((0.20, 0.006, 0.075), (0.23, 0.282, 0.80), "yellow", bevel=0.002))
    for index in range(3):
        model.add(bar((0.15, 0.003, 0.008), (0.23, 0.286, 0.78 + 0.02 * index), "rubber", bevel=0.0))
    # Шкала под стеклом в хромированной оправе.
    dial_z = 1.10
    model.add(cyl(0.30, 0.18, (0.0, 0.02, dial_z), "white", axis="y", bevel=0.02, vertices=32))
    model.add(cyl(0.245, 0.02, (0.0, 0.105, dial_z), "panel", axis="y", vertices=32))
    for start, end, material in ((30.0, 80.0, "glow_green"), (83.0, 112.0, "glow_yellow"), (115.0, 150.0, "glow_red")):
        model.add(prism(arc_points(0.15, 0.215, start, end, center=(0.0, dial_z)), 0.012, material, plane="xz",
                offset=0.112))
    for angle in range(30, 151, 10):
        major = angle % 30 == 0
        radius = 0.118 if major else 0.128
        x, z = radius * math.cos(math.radians(angle)), radius * math.sin(math.radians(angle))
        model.add(box((0.006, 0.004, 0.034 if major else 0.016), (x, 0.117, dial_z + z), "white", bevel=0.0,
                rot=(0.0, -math.radians(angle - 90.0), 0.0)))
    model.add(prism([(-0.022, dial_z - 0.03), (0.022, dial_z - 0.03), (0.006, dial_z + 0.20), (-0.006, dial_z + 0.20)],
            0.014, "red", plane="xz", offset=0.128), "Needle")
    model.add(cyl(0.035, 0.03, (0.0, 0.137, dial_z), "yellow", axis="y", bevel=0.008, vertices=16), "Needle")
    model.add(torus(0.262, 0.022, (0.0, 0.118, dial_z), "chrome", axis="y", major_segments=32))
    model.add(cyl(0.25, 0.004, (0.0, 0.158, dial_z), "glass", axis="y", vertices=32))
    # Рычаг справа.
    pivot = (0.47, 0.0, 0.62)
    model.add(box((0.12, 0.26, 0.26), (0.45, 0.0, 0.62), "panel", bevel=0.02))
    model.add(bar((0.004, 0.03, 0.20), (0.512, 0.0, 0.62), "rubber", axis="x", bevel=0.0))
    model.add(cyl(0.05, 0.06, (0.52, 0.0, 0.62), "yellow", axis="x", bevel=0.01, vertices=16))
    tilt = math.radians(-28.0)
    direction = (0.0, -math.sin(tilt), math.cos(tilt))
    model.add(cyl(0.02, 0.40, (0.54, direction[1] * 0.20, 0.62 + direction[2] * 0.20), "chrome", rot=(tilt, 0.0, 0.0),
            vertices=12), "Lever")
    model.add(ball(0.06, (0.54, direction[1] * 0.42, 0.62 + direction[2] * 0.42), "red"), "Lever")
    # Передняя панель.
    model.add(box((0.46, 0.02, 0.13), (-0.12, 0.285, 0.67), "rubber", bevel=0.006))
    model.add(box((0.41, 0.02, 0.085), (-0.12, 0.291, 0.67), "screen", bevel=0.004))
    for x, material in ((-0.29, "glow_green"), (-0.15, "yellow"), (-0.01, "red")):
        model.add(cyl(0.056, 0.012, (x, 0.284, 0.46), "chrome", axis="y", bevel=0.003, vertices=16))
        model.add(cyl(0.044, 0.05, (x, 0.287, 0.46), material, axis="y", bevel=0.012, vertices=16))
    for index in range(4):
        model.add(box((0.24, 0.02, 0.028), (0.23, 0.281, 0.43 + 0.06 * index), "rubber", bevel=0.006))
    # Сзади — решётка охлаждения.
    for index in range(5):
        model.add(box((0.46, 0.02, 0.035), (0.0, -0.281, 0.40 + 0.065 * index), "rubber", bevel=0.006))
    # Труба с лампочкой на макушке.
    model.add(cyl(0.065, 0.02, (-0.33, -0.13, 0.945), "grey", bevel=0.005, vertices=16))
    model.add(cyl(0.045, 0.22, (-0.33, -0.13, 1.03), "grey", bevel=0.008, vertices=16))
    model.add(ball(0.045, (-0.33, -0.13, 1.16), "glow_red"))
    origins = {"Needle": (0.0, 0.13, dial_z), "Lever": pivot}
    return model, origins, []


# ---------- Канистры ----------

def _canister_parts(origin=(0.0, 0.0, 0.0), segments=24):
    """Детали одной канистры (высота 0,44 м), низ в точке origin. segments — число граней по кругу."""
    ox, oy, oz = origin
    parts = [lathe([(0.0, 0.0), (0.125, 0.0), (0.15, 0.025), (0.15, 0.30), (0.125, 0.345), (0.065, 0.365),
            (0.065, 0.39), (0.0, 0.39)], (ox, oy, oz), "orange", bevel=0.012, segments=segments)]
    for z in (0.075, 0.25):
        parts.append(cyl(0.158, 0.035, (ox, oy, oz + z), "panel", bevel=0.01, vertices=segments))
    parts.append(cyl(0.075, 0.055, (ox, oy, oz + 0.412), "yellow", bevel=0.014, vertices=16))
    parts.append(tube([(ox, oy - 0.14, oz + 0.30), (ox, oy - 0.215, oz + 0.29), (ox, oy - 0.23, oz + 0.20),
            (ox, oy - 0.215, oz + 0.11), (ox, oy - 0.14, oz + 0.10)], 0.018, "panel", steps=3))
    parts.append(box((0.06, 0.03, 0.115), (ox, oy + 0.143, oz + 0.163), "glow_green", bevel=0.012))
    return parts


def build_canister():
    """Топливная канистра, которую носят в руках: высота 0,44 м, начало координат — центр дна."""
    model = Model("canister")
    model.extend(_canister_parts())
    return model, None, []


def build_canister_rack():
    """Стеллаж, с которого берут канистры."""
    model = Model("canister_rack")
    for sign in (-1.0, 1.0):
        model.add(box((0.09, 0.46, 1.22), (sign * 0.62, 0.0, 0.61), "panel", bevel=0.03))
    model.add(box((1.22, 0.04, 1.10), (0.0, -0.20, 0.59), "mid", bevel=0.01))
    for z in (0.14, 0.62):
        model.add(box((1.20, 0.44, 0.06), (0.0, 0.0, z), "line", bevel=0.02))
        model.add(bar((1.20, 0.05, 0.05), (0.0, 0.215, z + 0.04), "yellow", bevel=0.015))
    for x in (-0.38, 0.0, 0.38):
        model.extend(_canister_parts((x, 0.0, 0.65), segments=16))
    model.extend(_canister_parts((-0.38, 0.0, 0.17), segments=16))
    model.extend(_canister_parts((0.38, 0.0, 0.17), segments=16))
    # Табличка с каплей топлива.
    model.add(box((1.33, 0.06, 0.20), (0.0, 0.0, 1.20), "yellow", bevel=0.03))
    drop = [(0.0, 1.27), (0.035, 1.21), (0.045, 1.175), (0.03, 1.145), (0.0, 1.135), (-0.03, 1.145), (-0.045, 1.175),
            (-0.035, 1.21)]
    model.add(prism(drop, 0.012, "deep", plane="xz", offset=0.026))
    for x in (-0.36, 0.36):
        model.add(prism([(x - 0.07, 1.14), (x - 0.03, 1.14), (x + 0.07, 1.26), (x + 0.03, 1.26)], 0.012, "deep",
                plane="xz", offset=0.026))
    return model, None, []


def build_canister_dock():
    """Заправочный порт: гнездо для канистры на высоте 0,745 м."""
    model = Model("canister_dock")
    model.add(box((0.86, 0.66, 0.07), (0.0, 0.0, 0.055), "panel", bevel=0.012))
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            model.add(cyl(0.045, 0.03, (sx * 0.36, sy * 0.26, 0.015), "rubber", bevel=0.006, vertices=12))
    model.add(box((0.80, 0.60, 0.46), (0.0, 0.0, 0.31), "line", bevel=0.025, segments=3))
    model.add(box((0.84, 0.64, 0.20), (0.0, 0.0, 0.63), "white", bevel=0.025, segments=3))
    for sx in (-1.0, 1.0):
        for z in (0.14, 0.48):
            model.add(bolt((sx * 0.36, 0.301, z), axis="y", radius=0.01, material="chrome", depth=0.006))
    # Башня чуть шире и глубже белого корпуса: совпадающие грани разных цветов мерцали бы.
    model.add(box((0.87, 0.23, 1.10), (0.0, -0.225, 0.55), "line", bevel=0.05, segments=3))
    # Гнездо.
    model.add(lathe([(0.17, 0.70), (0.25, 0.70), (0.25, 0.79), (0.17, 0.79)], (0.0, 0.06, 0.0), "yellow", closed=True,
            bevel=0.018))
    model.add(cyl(0.17, 0.02, (0.0, 0.06, 0.735), "void"))
    model.add(torus(0.21, 0.016, (0.0, 0.06, 0.792), "glow_cyan"))
    # Стрелка «ставь сюда» и шкала заполнения.
    arrow = [(-0.05, 1.03), (0.05, 1.03), (0.05, 0.93), (0.11, 0.93), (0.0, 0.83), (-0.11, 0.93), (-0.05, 0.93)]
    model.add(prism(arrow, 0.014, "glow_yellow", plane="xz", offset=-0.122))
    for index in range(5):
        material = "glow_green" if index < 2 else "deep"
        model.add(box((0.10, 0.02, 0.05), (0.29, -0.118, 0.72 + 0.068 * index), material, bevel=0.008))
        model.add(box((0.10, 0.02, 0.05), (-0.29, -0.118, 0.72 + 0.068 * index), material, bevel=0.008))
    # Шланг и передняя панель.
    model.add(tube([(0.42, -0.22, 0.92), (0.54, -0.22, 0.84), (0.58, -0.10, 0.50), (0.52, 0.05, 0.22), (0.42, 0.10, 0.20)],
            0.032, "orange"))
    model.add(cyl(0.05, 0.05, (0.43, -0.22, 0.92), "grey", axis="x", vertices=12))
    model.add(cyl(0.05, 0.05, (0.42, 0.10, 0.20), "grey", axis="x", vertices=12))
    model.add(box((0.36, 0.02, 0.10), (-0.14, 0.302, 0.36), "screen", bevel=0.006))
    model.add(cyl(0.045, 0.04, (0.20, 0.30, 0.36), "glow_green", axis="y", bevel=0.01, vertices=16))
    for x in (-0.24, 0.0, 0.24):
        model.add(prism([(x - 0.11, 0.535), (x - 0.03, 0.535), (x + 0.05, 0.725), (x - 0.03, 0.725)], 0.01, "yellow",
                plane="xz", offset=0.318))
    return model, None, []


# ---------- Реактор ----------

def build_reactor_core():
    """Ядро реактора в клетке, высота 2,6 м: светящийся шар — то самое, что взорвётся."""
    model = Model("reactor_core")
    model.add(lathe([(0.0, 0.0), (1.14, 0.0), (1.20, 0.06), (1.20, 0.24), (1.02, 0.34), (0.0, 0.34)], (0.0, 0.0, 0.0),
            "line", bevel=0.02, segments=36))
    for index in range(12):
        angle = 30.0 * index
        material = "yellow" if index % 2 == 0 else "deep"
        x, y, _z = _polar(1.195, angle + 15.0)
        model.add(box((0.6, 0.04, 0.14), (x, y, 0.15), material, bevel=0.012, rot=(0.0, 0.0, math.radians(angle + 105.0))))
    model.add(torus(0.88, 0.03, (0.0, 0.0, 0.345), "glow_cyan", major_segments=36))
    model.add(lathe([(0.0, 0.34), (0.62, 0.34), (0.62, 0.46), (0.44, 0.60), (0.44, 0.72), (0.0, 0.72)], (0.0, 0.0, 0.0),
            "white", bevel=0.02))
    # Ядро и энергетический столб.
    core_z = 1.35
    model.add(ball(0.46, (0.0, 0.0, core_z), "core"), "Glow")
    model.add(cyl(0.07, 1.30, (0.0, 0.0, core_z), "glow_orange", vertices=16), "Glow")
    for z in (core_z - 0.52, core_z + 0.52):
        model.add(torus(0.13, 0.035, (0.0, 0.0, z), "glow_orange"), "Glow")
    # Клетка.
    for index in range(6):
        angle = 60.0 * index
        model.add(tube([_polar(0.44, angle, 0.70), _polar(0.70, angle, 0.98), _polar(0.80, angle, core_z),
                _polar(0.70, angle, 1.72), _polar(0.44, angle, 2.00)], 0.045, "panel"))
    model.add(torus(0.80, 0.05, (0.0, 0.0, core_z), "yellow", major_segments=36))
    for z in (0.98, 1.72):
        model.add(torus(0.70, 0.032, (0.0, 0.0, z), "panel", major_segments=36))
    # Верхний колпак с маячком.
    model.add(lathe([(0.0, 1.98), (0.44, 1.98), (0.44, 2.06), (0.58, 2.16), (0.58, 2.28), (0.30, 2.36), (0.30, 2.44),
            (0.16, 2.50), (0.0, 2.50)], (0.0, 0.0, 0.0), "white", bevel=0.02))
    model.add(cyl(0.60, 0.07, (0.0, 0.0, 2.22), "yellow", bevel=0.02))
    model.add(cyl(0.085, 0.10, (0.0, 0.0, 2.55), "glow_red", bevel=0.035, vertices=16))
    # Трубы охлаждения.
    for angle in (30.0, 150.0, 270.0):
        model.add(tube([_polar(1.0, angle, 0.30), _polar(1.03, angle, 1.20), _polar(1.0, angle, 1.95),
                _polar(0.82, angle, 2.24), _polar(0.50, angle, 2.22)], 0.06, "cyan"))
        x, y, _z = _polar(1.0, angle)
        model.add(cyl(0.10, 0.10, (x, y, 0.36), "grey", bevel=0.02, vertices=16))
    return model, {"Glow": (0.0, 0.0, core_z)}, []


def build_reactor_panel():
    """Пульт остановки реактора с большим красным вентилем, высота 1,1 м."""
    model = Model("reactor_panel")
    model.add(box((1.36, 0.58, 0.07), (0.0, -0.05, 0.055), "panel", bevel=0.012))
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            model.add(cyl(0.045, 0.03, (sx * 0.60, -0.05 + sy * 0.22, 0.015), "rubber", bevel=0.006, vertices=12))
    model.add(box((1.28, 0.50, 0.74), (0.0, -0.05, 0.45), "line", bevel=0.025, segments=3))
    # Съёмные панели корпуса: шов и винты по углам спереди и сзади.
    model.add(bar((1.282, 0.502, 0.006), (0.0, -0.05, 0.62), "void", axis="z", bevel=0.0))
    for sx in (-1.0, 1.0):
        for z in (0.14, 0.56, 0.68, 0.78):
            for y in (0.201, -0.301):
                model.add(bolt((sx * 0.60, y, z), axis="y", radius=0.01, material="chrome", depth=0.006))
    model.add(bar((1.30, 0.03, 0.10), (0.0, 0.205, 0.30), "yellow", bevel=0.01))
    # Задняя стенка смотрит на реактор: полоса и решётка, чтобы пульт не был глухим ящиком.
    model.add(bar((1.30, 0.03, 0.10), (0.0, -0.305, 0.30), "yellow", bevel=0.01))
    for index in range(4):
        model.add(box((0.50, 0.02, 0.035), (0.0, -0.303, 0.48 + 0.07 * index), "deep", bevel=0.008))
    desk = Frame((0.0, 0.02, 0.86), (math.radians(-24.0), 0.0, 0.0))
    model.add(box((1.36, 0.66, 0.14), desk.at(0.0, 0.0, 0.0), "white", bevel=0.05, segments=3, rot=desk.rot))
    # Вентиль.
    wheel_center = desk.at(-0.32, 0.0, 0.19)
    model.add(cyl(0.035, 0.14, desk.at(-0.32, 0.0, 0.12), "chrome", rot=desk.rot, vertices=12))
    model.add(cyl(0.11, 0.03, desk.at(-0.32, 0.0, 0.08), "panel", rot=desk.rot, bevel=0.01))
    model.add(torus(0.21, 0.04, wheel_center, "red", rot=desk.rot), "Wheel")
    for index in range(3):
        spoke = desk.rot_local((0.0, math.pi / 2.0, math.radians(60.0 * index)))
        model.add(cyl(0.02, 0.40, wheel_center, "red", rot=spoke, vertices=10), "Wheel")
    model.add(cyl(0.06, 0.07, wheel_center, "yellow", rot=desk.rot, bevel=0.015, vertices=16), "Wheel")
    # Кнопки, экран и аварийная лампа.
    for index, material in enumerate(("glow_green", "yellow", "glow_red")):
        model.add(cyl(0.064, 0.012, desk.at(0.14 + 0.16 * index, 0.16, 0.074), "chrome", rot=desk.rot, bevel=0.003,
                vertices=16))
        model.add(cyl(0.05, 0.05, desk.at(0.14 + 0.16 * index, 0.16, 0.08), material, rot=desk.rot, bevel=0.012,
                vertices=16))
    for sx in (-1.0, 1.0):
        for y in (-0.28, 0.28):
            model.add(cyl(0.011, 0.008, desk.at(sx * 0.63, y, 0.072), "chrome", rot=desk.rot, vertices=8))
    model.add(box((0.50, 0.26, 0.02), desk.at(0.30, -0.12, 0.072), "deep", bevel=0.008, rot=desk.rot))
    model.add(box((0.45, 0.21, 0.02), desk.at(0.30, -0.12, 0.078), "screen", bevel=0.006, rot=desk.rot))
    warning = [(-0.07, 0.06), (0.07, 0.06), (0.0, -0.07)]
    triangle = prism(warning, 0.012, "glow_red", plane="xy", offset=0.0)
    triangle.location = desk.at(0.30, -0.12, 0.086)
    triangle.rotation_euler = desk.rot
    model.add(triangle)
    for x in (-0.52, 0.52):
        model.add(box((0.10, 0.03, 0.34), (x, 0.205, 0.50), "deep", bevel=0.01))
    return model, {"Wheel": (wheel_center, desk.rot)}, []


# ---------- Собрание ----------

def build_emergency_button():
    """Красная кнопка-гриб под откидной крышкой на тумбе, высота 1,0 м."""
    model = Model("emergency_button")
    model.add(lathe([(0.0, 0.0), (0.30, 0.0), (0.33, 0.03), (0.33, 0.08), (0.21, 0.15), (0.17, 0.50), (0.17, 0.73),
            (0.24, 0.79), (0.0, 0.79)], (0.0, 0.0, 0.0), "yellow", bevel=0.012))
    for z in (0.30, 0.45, 0.60):
        model.add(cyl(0.185, 0.06, (0.0, 0.0, z), "deep", bevel=0.01))
    plate_top = 0.84
    model.add(box((0.46, 0.46, 0.06), (0.0, 0.0, plate_top - 0.03), "panel", bevel=0.025))
    model.add(lathe([(0.0, plate_top), (0.085, plate_top), (0.085, plate_top + 0.03), (0.15, plate_top + 0.03),
            (0.15, plate_top + 0.06), (0.10, plate_top + 0.10), (0.0, plate_top + 0.11)], (0.0, 0.0, 0.0), "button_red",
            bevel=0.008), "Button")
    model.add(cyl(0.17, 0.012, (0.0, 0.0, plate_top + 0.006), "yellow"))
    # Крышка: прозрачный колпак на жёлтой рамке с петлёй сзади.
    hinge = (0.0, -0.20, plate_top + 0.012)
    model.add(box((0.38, 0.38, 0.15), (0.0, 0.0, plate_top + 0.085), "cover", bevel=0.05, segments=3), "Cover")
    outer = rounded_rect_points(0.42, 0.42, 0.07)
    inner = rounded_rect_points(0.34, 0.34, 0.04)
    model.add(ring_prism(outer, inner, 0.03, "yellow", plane="xy", offset=plate_top, bevel=0.008), "Cover")
    model.add(box((0.10, 0.05, 0.022), (0.0, 0.225, plate_top + 0.014), "yellow", bevel=0.008), "Cover")
    model.add(cyl(0.02, 0.24, (0.0, -0.205, plate_top + 0.014), "panel", axis="x", vertices=12))
    return model, {"Button": (0.0, 0.0, plate_top), "Cover": hinge}, []


def build_meeting_table():
    """Круглый стол собраний: диаметр 3,2 м, высота 0,8 м, в середине отверстие под тумбу с кнопкой.
    Столешница из светлого пластика на четырёх стальных опорах."""
    model = Model("meeting_table")
    model.add(lathe([(0.52, 0.755), (1.60, 0.755), (1.60, 0.80), (0.52, 0.80)], (0.0, 0.0, 0.0), "laminate", closed=True,
            bevel=0.006, segments=64))
    model.add(lathe([(0.53, 0.72), (1.585, 0.72), (1.585, 0.757), (0.53, 0.757)], (0.0, 0.0, 0.0), "line", closed=True,
            segments=64))
    model.add(lathe([(1.36, 0.60), (1.50, 0.60), (1.50, 0.73), (1.36, 0.73)], (0.0, 0.0, 0.0), "line", closed=True,
            bevel=0.012, segments=48))
    model.add(lathe([(0.52, 0.56), (0.64, 0.56), (0.64, 0.73), (0.52, 0.73)], (0.0, 0.0, 0.0), "line", closed=True,
            bevel=0.012, segments=32))
    model.add(lathe([(0.535, 0.795), (0.615, 0.795), (0.615, 0.812), (0.535, 0.812)], (0.0, 0.0, 0.0), "glow_cyan",
            closed=True, segments=32))
    # Кромка-бампер и стыки четырёх секций столешницы.
    model.add(lathe([(1.585, 0.762), (1.606, 0.765), (1.612, 0.7775), (1.606, 0.79), (1.585, 0.793)], (0.0, 0.0, 0.0),
            "yellow", closed=True, segments=64))
    for index in range(4):
        angle = 90.0 * index
        x, y, _z = _polar(1.07, angle)
        model.add(box((1.03, 0.004, 0.002), (x, y, 0.8008), "rubber", bevel=0.0, rot=(0.0, 0.0, math.radians(angle))))
        # Лючок с розетками у каждой секции.
        x, y, _z = _polar(1.02, angle + 45.0)
        rot = (0.0, 0.0, math.radians(angle + 45.0))
        model.add(box((0.10, 0.20, 0.004), (x, y, 0.801), "grey", bevel=0.0015, rot=rot))
        model.add(box((0.012, 0.16, 0.002), (x, y, 0.8035), "rubber", bevel=0.0, rot=rot))
    # Опоры: стальная колонна, фланец под столешницей и башмак на болтах.
    for index in range(4):
        angle = 45.0 + 90.0 * index
        x, y, _z = _polar(1.18, angle)
        model.add(cyl(0.065, 0.66, (x, y, 0.39), "grey", vertices=20))
        model.add(cyl(0.13, 0.025, (x, y, 0.7075), "panel", bevel=0.006, vertices=20))
        model.add(lathe([(0.0, 0.0), (0.17, 0.0), (0.175, 0.006), (0.175, 0.03), (0.09, 0.055), (0.085, 0.075),
                (0.0, 0.075)], (x, y, 0.0), "yellow", bevel=0.004, segments=20))
        for bolt_index in range(4):
            bx, by, _z = _polar(0.14, angle + 45.0 + 90.0 * bolt_index)
            model.add(bolt((x + bx, y + by, 0.036), radius=0.013))
    # Мелочи на столе: кружки, бумаги, ноутбук и пончик.
    top = 0.80
    model.extend(environment_decor.mug_parts((0.95, 0.55, top), "red"))
    model.extend(environment_decor.mug_parts((-0.55, -1.05, top), "cyan"))
    for index, turn in enumerate((12.0, -8.0, 30.0)):
        model.add(box((0.21, 0.30, 0.002), (-0.85 + 0.012 * index, 0.72, top + 0.002 + 0.002 * index), "white", bevel=0.0,
                rot=(0.0, 0.0, math.radians(turn + 50.0))))
    model.add(cyl(0.005, 0.14, (-0.62, 0.62, top + 0.006), "cyan", axis="x", vertices=8,
            rot=(0.0, math.pi / 2.0, math.radians(35.0))))
    laptop = Frame((0.25, -1.08, top), (0.0, 0.0, math.radians(190.0)))
    model.add(box((0.34, 0.24, 0.016), laptop.at(0.0, 0.0, 0.008), "grey", bevel=0.005, rot=laptop.rot))
    model.add(box((0.29, 0.10, 0.002), laptop.at(0.0, -0.035, 0.0165), "rubber", bevel=0.0, rot=laptop.rot))
    model.add(box((0.10, 0.065, 0.002), laptop.at(0.0, 0.072, 0.0165), "panel", bevel=0.0, rot=laptop.rot))
    lid = Frame(laptop.at(0.0, -0.115, 0.016), (math.radians(15.0), 0.0, math.radians(190.0)))
    model.add(box((0.34, 0.012, 0.23), lid.at(0.0, 0.0, 0.115), "grey", bevel=0.004, rot=lid.rot))
    model.add(box((0.325, 0.004, 0.215), lid.at(0.0, 0.007, 0.115), "rubber", bevel=0.0, rot=lid.rot))
    model.add(box((0.30, 0.004, 0.19), lid.at(0.0, 0.009, 0.118), "screen", bevel=0.0, rot=lid.rot))
    model.add(torus(0.05, 0.026, (-1.05, -0.35, top + 0.026), "wood", major_segments=16, minor_segments=8))
    model.add(torus(0.05, 0.022, (-1.05, -0.35, top + 0.036), "red", major_segments=16, minor_segments=8))
    model.add(cyl(0.085, 0.004, (-1.05, -0.35, top + 0.002), "white", vertices=16))
    return model, None, []


def build_weapon_pedestal():
    """Подсвеченная стойка для оружия: плоский верх на высоте 0,9 м."""
    model = Model("weapon_pedestal")
    model.add(box((0.62, 0.42, 0.06), (0.0, 0.0, 0.05), "panel", bevel=0.012))
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            model.add(cyl(0.035, 0.024, (sx * 0.25, sy * 0.15, 0.012), "rubber", bevel=0.005, vertices=12))
            model.add(bolt((sx * 0.27, sy * 0.17, 0.082), radius=0.011))
    model.add(box((0.26, 0.20, 0.74), (0.0, 0.0, 0.44), "white", bevel=0.03, segments=3))
    model.add(box((0.86, 0.38, 0.035), (0.0, 0.0, 0.812), "glow_cyan", bevel=0.012))
    model.add(box((0.92, 0.44, 0.075), (0.0, 0.0, 0.8625), "line", bevel=0.025))
    model.add(box((0.30, 0.24, 0.05), (0.0, 0.0, 0.775), "line", bevel=0.02))
    diamond = [(0.0, 0.50), (0.05, 0.56), (0.0, 0.62), (-0.05, 0.56)]
    model.add(prism(diamond, 0.012, "glow_yellow", plane="xz", offset=0.098))
    for x in (-0.22, 0.22):
        model.add(cyl(0.035, 0.03, (x, 0.0, 0.09), "glow_cyan", bevel=0.008, vertices=12))
    return model, None, []


GAMEPLAY_BUILDERS = {
    "task_panel": build_task_panel,
    "task_keypad": build_task_keypad,
    "task_calibrator": build_task_calibrator,
    "canister": build_canister,
    "canister_rack": build_canister_rack,
    "canister_dock": build_canister_dock,
    "reactor_core": build_reactor_core,
    "reactor_panel": build_reactor_panel,
    "emergency_button": build_emergency_button,
    "meeting_table": build_meeting_table,
    "weapon_pedestal": build_weapon_pedestal,
}

BUILDERS = dict(GAMEPLAY_BUILDERS)
BUILDERS.update(environment_decor.BUILDERS)

if __name__ == "__main__":
    run_generator(BUILDERS, MODEL_DIR, PREFAB_DIR, prefab_names=set(environment_decor.BUILDERS))
