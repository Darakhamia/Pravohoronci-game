"""Модульный набор станции: пол, стены, колонны, потолок. Сетка 4 м, стены 3,2 м высотой и 0,2 м толщиной.

Запуск из корня репозитория:
    blender -b --python tools/assets/kit.py                     все детали -> assets/models/kit/*.glb
    blender -b --python tools/assets/kit.py -- wall pillar      только названные
    blender -b --python tools/assets/kit.py -- --prefabs        заодно переписать префабы scenes/maps/kit/*.tscn

ГДЕ НАЧАЛО КООРДИНАТ (одинаково у всех деталей, координаты Godot: Y вверх)
- Карта делится на клетки 4 x 4 м. Центр клетки (i, j) — точка (4 * i, 0, 4 * j), пол на Y = 0.
- Плитки (floor, floor_hazard, ceiling, ceiling_light): начало координат в центре клетки НА УРОВНЕ ПОЛА.
  Потолочные плитки ставятся в ту же точку, что и пол: их геометрия уже поднята на 3,2 м.
- Стены (wall, wall_doorway, wall_window), перила (railing) и арка (corridor_arch): начало координат в середине
  основания, деталь тянется на 4 м вдоль локальной оси X и стоит ровно на границе двух клеток
  (середина ребра клетки: (4 * i, 0, 4 * j ± 2) без поворота или (4 * i ± 2, 0, 4 * j) с поворотом на 90° вокруг Y).
  Стены симметричны: лицевой стороны у них нет.
- Колонна (pillar): начало координат в узле сетки (углу клетки), например (4 * i + 2, 0, 4 * j + 2).
  Колонну ставят в каждый узел, где стены сходятся углом или буквой «Т»; в прямом пролёте она необязательна,
  но с ней ритм стены приятнее. Стены заходят в колонну на 0,25 м, поэтому щелей и мерцания граней нет.
- У floor_hazard полосатая кромка лежит у края -Z; поворотом вокруг Y её направляют к двери.
- В префабе ceiling_light уже есть свой свет (SpotLight3D без теней, см. PREFAB_EXTRAS внизу файла).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from environment_lib import (Model, bar, box, clip_polygon_x, cyl, lathe, prism, ring_prism,  # noqa: E402
        rounded_rect_points, run_generator)

MODEL_DIR = "assets/models/kit"
PREFAB_DIR = "scenes/maps/kit"

GRID = 4.0
HALF = GRID / 2.0
WALL_HEIGHT = 3.2
WALL_THICKNESS = 0.2
# Толщина коробки столкновений стены: чуть больше самой стены, по плинтусу.
WALL_COLLISION = 0.28
SLAB = 0.2

# Горизонтальные пояса стены: имя -> (низ, верх, толщина, материал, фаска).
BANDS = {
    "skirting": (0.0, 0.30, 0.30, "panel", 0.03),
    "wainscot": (0.30, 0.95, 0.24, "line", 0.0),
    "rail": (0.95, 1.07, 0.30, "cyan", 0.03),
    "cornice": (2.95, WALL_HEIGHT, 0.30, "panel", 0.03),
}
LOWER_BANDS = ("skirting", "wainscot", "rail")
# Светлые панели верхней части стены.
PANEL_BOTTOM = 1.15
PANEL_TOP = 2.87
PANEL_THICKNESS = 0.26
PANEL_BEVEL = 0.04
# Высота горизонтального шва между нижней и верхней панелью и его ширина.
PANEL_SPLIT = 2.36
PANEL_SEAM = 0.06

DOOR_WIDTH = 1.4
DOOR_HEIGHT = 2.4
DOOR_FRAME = 0.14

WINDOW_WIDTH = 2.3
WINDOW_HEIGHT = 1.2
WINDOW_CENTER_Z = 1.9
WINDOW_FRAME = 0.17

PLATE_GAP = 0.04
PLATE = HALF - PLATE_GAP
HAZARD_BAND = 0.58
HAZARD_STRIPE = 0.29


def _core(model, x0, x1, z0=0.0, z1=WALL_HEIGHT):
    model.add(bar((x1 - x0, WALL_THICKNESS, z1 - z0), ((x0 + x1) / 2.0, 0.0, (z0 + z1) / 2.0), "wall_core",
            bevel=0.0))


def _band(model, name, x0, x1):
    z0, z1, thickness, material, bevel = BANDS[name]
    model.add(bar((x1 - x0, thickness, z1 - z0), ((x0 + x1) / 2.0, 0.0, (z0 + z1) / 2.0), material, bevel=bevel))


def _panel(model, x0, x1, z0=PANEL_BOTTOM, z1=PANEL_TOP):
    """Светлая панель; высокая панель делится швом на большую нижнюю часть и узкую верхнюю."""
    if z0 < PANEL_SPLIT < z1:
        spans = ((z0, PANEL_SPLIT - PANEL_SEAM / 2.0), (PANEL_SPLIT + PANEL_SEAM / 2.0, z1))
    else:
        spans = ((z0, z1),)
    for bottom, top in spans:
        model.add(box((x1 - x0, PANEL_THICKNESS, top - bottom), ((x0 + x1) / 2.0, 0.0, (bottom + top) / 2.0), "white",
                bevel=PANEL_BEVEL))


def _wall_box(x0, x1, z0=0.0, z1=WALL_HEIGHT):
    return ((x1 - x0, WALL_COLLISION, z1 - z0), ((x0 + x1) / 2.0, 0.0, (z0 + z1) / 2.0))


def _plates(model, top, thickness, materials, y_rows=None):
    """Четыре плиты 2 x 2 м со швами; top — высота лицевой стороны, thickness < 0 — плиты смотрят вниз."""
    rows = y_rows or ((-HALF, 0.0), (0.0, HALF))
    for row, (y0, y1) in enumerate(rows):
        for column, x0 in enumerate((-HALF, 0.0)):
            size = (PLATE, (y1 - y0) - PLATE_GAP, abs(thickness))
            center = (x0 + HALF / 2.0, (y0 + y1) / 2.0, top - thickness / 2.0)
            model.add(box(size, center, materials[(row + column) % 2], bevel=0.015, segments=1))


def build_floor():
    model = Model("floor")
    model.add(bar((GRID, GRID, SLAB - 0.02), (0.0, 0.0, -SLAB / 2.0 - 0.01), "deep", bevel=0.0))
    _plates(model, 0.0, 0.06, ("floor_a", "floor_b"))
    return model, None, [((GRID, GRID, SLAB), (0.0, 0.0, -SLAB / 2.0))]


def build_floor_hazard():
    model = Model("floor_hazard")
    model.add(bar((GRID, GRID, SLAB - 0.02), (0.0, 0.0, -SLAB / 2.0 - 0.01), "deep", bevel=0.0))
    band_y0 = HALF - PLATE_GAP / 2.0 - HAZARD_BAND
    _plates(model, 0.0, 0.06, ("floor_a", "floor_b"), y_rows=((-HALF, 0.0), (0.0, band_y0)))
    x_min = -HALF + PLATE_GAP / 2.0
    x_max = HALF - PLATE_GAP / 2.0
    index = 0
    x = x_min - HAZARD_BAND
    while x < x_max:
        stripe = [(x, band_y0), (x + HAZARD_STRIPE, band_y0), (x + HAZARD_STRIPE + HAZARD_BAND, band_y0 + HAZARD_BAND),
                (x + HAZARD_BAND, band_y0 + HAZARD_BAND)]
        clipped = clip_polygon_x(stripe, x_min, x_max)
        if len(clipped) >= 3:
            model.add(prism(clipped, 0.06, "yellow" if index % 2 == 0 else "deep", plane="xy", offset=-0.06))
        x += HAZARD_STRIPE
        index += 1
    return model, None, [((GRID, GRID, SLAB), (0.0, 0.0, -SLAB / 2.0))]


def build_ceiling():
    model = Model("ceiling")
    model.add(bar((GRID, GRID, SLAB - 0.02), (0.0, 0.0, WALL_HEIGHT + SLAB / 2.0 + 0.01), "deep", bevel=0.0))
    _plates(model, WALL_HEIGHT, -0.06, ("mid", "mid"))
    return model, None, [((GRID, GRID, SLAB), (0.0, 0.0, WALL_HEIGHT + SLAB / 2.0))]


def build_ceiling_light():
    model, _origins, boxes = build_ceiling()
    model.name = "ceiling_light"
    # Круглый светильник: белое кольцо и светящийся диск, выступает из потолка на 10 см.
    model.add(lathe([(0.54, WALL_HEIGHT + 0.02), (0.78, WALL_HEIGHT + 0.02), (0.78, WALL_HEIGHT - 0.10),
            (0.54, WALL_HEIGHT - 0.10)], (0.0, 0.0, 0.0), "white", closed=True, bevel=0.025, segments=32))
    model.add(cyl(0.56, 0.08, (0.0, 0.0, WALL_HEIGHT - 0.03), "lamp", vertices=32))
    return model, None, boxes


def build_wall():
    model = Model("wall")
    _core(model, -HALF, HALF)
    for name in BANDS:
        _band(model, name, -HALF, HALF)
    _panel(model, -1.90, -0.05)
    _panel(model, 0.05, 1.90)
    return model, None, [_wall_box(-HALF, HALF)]


def build_wall_doorway():
    model = Model("wall_doorway")
    inner = DOOR_WIDTH / 2.0
    outer = inner + DOOR_FRAME
    header_top = DOOR_HEIGHT + DOOR_FRAME
    for sign in (-1.0, 1.0):
        x0, x1 = sorted((sign * outer, sign * HALF))
        _core(model, x0, x1)
        for name in LOWER_BANDS:
            _band(model, name, x0, x1)
        _panel(model, *sorted((sign * (outer + 0.05), sign * 1.90)))
        # Косяк и его тёмный башмак.
        # Косяк начинается внутри башмака: иначе их внутренние грани лежат в одной плоскости и мерцают.
        jamb_bottom = 0.20
        model.add(box((DOOR_FRAME, 0.36, header_top - jamb_bottom),
                (sign * (inner + DOOR_FRAME / 2.0), 0.0, (header_top + jamb_bottom) / 2.0), "yellow", bevel=0.03))
        model.add(box((0.20, 0.42, 0.30), (sign * (inner + 0.10), 0.0, 0.15), "panel", bevel=0.03))
    _core(model, -outer, outer, header_top, WALL_HEIGHT)
    _band(model, "cornice", -HALF, HALF)
    model.add(bar((DOOR_WIDTH, 0.32, DOOR_FRAME), (0.0, 0.0, DOOR_HEIGHT + DOOR_FRAME / 2.0), "yellow", bevel=0.03))
    # Табличка-лампа над дверью с обеих сторон.
    model.add(box((0.96, PANEL_THICKNESS, 0.30), (0.0, 0.0, 2.745), "white", bevel=PANEL_BEVEL))
    model.add(box((0.56, 0.30, 0.13), (0.0, 0.0, 2.745), "glow_green", bevel=0.03))
    # Порожек закрывает шов плиток пола.
    model.add(bar((DOOR_WIDTH, 0.34, 0.012), (0.0, 0.0, 0.006), "grey", bevel=0.0))
    boxes = [_wall_box(-HALF, -inner), _wall_box(inner, HALF), _wall_box(-inner, inner, DOOR_HEIGHT, WALL_HEIGHT)]
    return model, None, boxes


def build_wall_window():
    model = Model("wall_window")
    hole_x = WINDOW_WIDTH / 2.0 + 0.03
    hole_z0 = WINDOW_CENTER_Z - WINDOW_HEIGHT / 2.0 - 0.03
    hole_z1 = WINDOW_CENTER_Z + WINDOW_HEIGHT / 2.0 + 0.03
    _core(model, -HALF, -hole_x)
    _core(model, hole_x, HALF)
    _core(model, -hole_x, hole_x, 0.0, hole_z0)
    _core(model, -hole_x, hole_x, hole_z1, WALL_HEIGHT)
    for name in BANDS:
        _band(model, name, -HALF, HALF)
    frame_x = WINDOW_WIDTH / 2.0 + WINDOW_FRAME
    _panel(model, -1.90, -frame_x - 0.05)
    _panel(model, frame_x + 0.05, 1.90)
    _panel(model, -frame_x - 0.05 + 0.10, frame_x + 0.05 - 0.10, WINDOW_CENTER_Z + WINDOW_HEIGHT / 2.0 + WINDOW_FRAME + 0.05,
            PANEL_TOP)
    center = (0.0, WINDOW_CENTER_Z)
    outer = rounded_rect_points(WINDOW_WIDTH + 2.0 * WINDOW_FRAME, WINDOW_HEIGHT + 2.0 * WINDOW_FRAME, 0.45,
            steps=5, center=center)
    inner = rounded_rect_points(WINDOW_WIDTH, WINDOW_HEIGHT, 0.30, steps=5, center=center)
    model.add(ring_prism(outer, inner, 0.34, "yellow", plane="xz", offset=-0.17, bevel=0.03))
    model.add(prism(inner, 0.04, "glass", plane="xz", offset=-0.02))
    model.add(bar((0.07, 0.10, WINDOW_HEIGHT), (0.0, 0.0, WINDOW_CENTER_Z), "panel", axis="z", bevel=0.02))
    return model, None, [_wall_box(-HALF, HALF)]


def build_pillar():
    model = Model("pillar")
    model.add(box((0.50, 0.50, WALL_HEIGHT), (0.0, 0.0, WALL_HEIGHT / 2.0), "wall_core", bevel=0.06, segments=3))
    model.add(box((0.60, 0.60, 0.30), (0.0, 0.0, 0.15), "panel", bevel=0.04))
    model.add(box((0.60, 0.60, 0.25), (0.0, 0.0, WALL_HEIGHT - 0.125), "panel", bevel=0.04))
    rail_z0, rail_z1 = BANDS["rail"][0], BANDS["rail"][1]
    model.add(box((0.56, 0.56, rail_z1 - rail_z0), (0.0, 0.0, (rail_z0 + rail_z1) / 2.0), "cyan", bevel=0.03))
    return model, None, [((0.5, 0.5, WALL_HEIGHT), (0.0, 0.0, WALL_HEIGHT / 2.0))]


def build_railing():
    model = Model("railing")
    for x in (-GRID / 3.0, 0.0, GRID / 3.0):
        model.add(box((0.12, 0.14, 1.0), (x, 0.0, 0.5), "panel", bevel=0.03))
    # Поручень со скруглёнными торцами: и отдельный пролёт, и цепочка пролётов выглядят законченно.
    model.add(box((GRID, 0.16, 0.10), (0.0, 0.0, 1.0), "yellow", bevel=0.035))
    model.add(bar((GRID, 0.10, 0.20), (0.0, 0.0, 0.10), "panel", bevel=0.03))
    model.add(bar((GRID, 0.03, 0.72), (0.0, 0.0, 0.57), "glass", bevel=0.0))
    return model, None, [((GRID, 0.16, 1.05), (0.0, 0.0, 0.525))]


def build_corridor_arch():
    model = Model("corridor_arch")
    leg_x = 1.70
    # Глубина 0,58 м — между пояском колонны (0,56 м) и её башмаком с шапкой (0,6 м): арку ставят между
    # двух колонн, и совпадающие грани разных цветов мерцали бы.
    depth = 0.58
    for sign in (-1.0, 1.0):
        model.add(box((0.32, depth, 2.90), (sign * leg_x, 0.0, 1.45), "wall_core", bevel=0.05))
        model.add(box((0.40, depth + 0.08, 0.34), (sign * leg_x, 0.0, 0.17), "panel", bevel=0.04))
        haunch = [(sign * 1.54, 2.90), (sign * 1.54, 2.30), (sign * 0.94, 2.90)]
        model.add(prism(haunch, depth - 0.10, "panel", plane="xz", offset=-(depth - 0.10) / 2.0, bevel=0.02))
        model.add(box((0.04, 0.14, 1.80), (sign * 1.53, 0.0, 1.30), "glow_cyan", bevel=0.015))
    model.add(bar((3.72, depth, 0.34), (0.0, 0.0, 3.03), "wall_core", bevel=0.05))
    model.add(bar((1.60, 0.14, 0.04), (0.0, 0.0, 2.85), "glow_cyan", bevel=0.015))
    boxes = [((0.32, depth, 2.90), (-leg_x, 0.0, 1.45)), ((0.32, depth, 2.90), (leg_x, 0.0, 1.45)),
            ((3.72, depth, 0.34), (0.0, 0.0, 3.03))]
    return model, None, boxes


BUILDERS = {
    "floor": build_floor,
    "floor_hazard": build_floor_hazard,
    "ceiling": build_ceiling,
    "ceiling_light": build_ceiling_light,
    "wall": build_wall,
    "wall_doorway": build_wall_doorway,
    "wall_window": build_wall_window,
    "pillar": build_pillar,
    "railing": build_railing,
    "corridor_arch": build_corridor_arch,
}

# Светильник внутри ceiling_light: прожектор без теней светит строго вниз. Угол подобран так, чтобы пятно
# на полу (радиус 2 м) не выходило за клетку, — тогда свет не пролезает под стеной в соседнюю комнату.
PREFAB_EXTRAS = {
    "ceiling_light": [
        "[node name=\"Light\" type=\"SpotLight3D\" parent=\".\"]",
        "transform = Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 3.05, 0)",
        "light_color = Color(1, 0.95, 0.86, 1)",
        "light_energy = 2.2",
        "light_specular = 0.3",
        "spot_range = 4.2",
        "spot_attenuation = 0.6",
        "spot_angle = 33.0",
        "spot_angle_attenuation = 0.7",
        "",
    ],
}

if __name__ == "__main__":
    run_generator(BUILDERS, MODEL_DIR, PREFAB_DIR, prefab_extras=PREFAB_EXTRAS)
