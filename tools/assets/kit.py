"""Модульный набор станции: пол, стены, колонны, потолок. Сетка 4 м, стены 3,2 м высотой и 0,2 м толщиной.

Запуск из корня репозитория:
    blender -b --python tools/assets/kit.py                     все детали -> assets/models/kit/*.glb
    blender -b --python tools/assets/kit.py -- wall pillar      только названные
    blender -b --python tools/assets/kit.py -- --prefabs        заодно переписать префабы scenes/maps/kit/*.tscn
После пересборки моделей: godot --headless --import, затем python3 tools/textures/apply_materials.py и снова
импорт — так новые модели получают материалы библиотеки resources/materials (у старых замены сохраняются).

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
- ceiling_duct — потолочная плитка с вентиляционным коробом и кабельным лотком вдоль локальной оси X
  (низ короба на высоте 2,84 м). Ставится вместо ceiling; соседние плитки продолжают короб, если стоят в ряд по X.
- Мелкие детали (болты, кабель-канал под карнизом, решётки в нижнем поясе, механика дверной рамы, решётка
  потолка) не выходят за прежние габариты деталей и не имеют столкновений.
- В префабе ceiling_light уже есть свой свет (узел Light — SpotLight3D без теней, см. PREFAB_EXTRAS внизу файла).
"""

import math
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

# Мелкие детали: крепёж панелей, кабель-канал под карнизом, отбойная планка, решётка в нижнем поясе.
BOLT_RADIUS = 0.017
BOLT_HEIGHT = 0.006
BOLT_INSET = 0.075
CONDUIT_Z = 2.91
CONDUIT_Y = 0.118
TRIM_Z = 0.315
VENT_WIDTH = 0.52
VENT_Z = 0.62
# Потолочная решётка (Т-профиль между плитами) выступает из плоскости потолка на 1,5 см.
CEILING_BAR = 0.045
CEILING_BAR_DROP = 0.015

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


def _bolt(model, x, side, z, depth=PANEL_THICKNESS / 2.0):
    """Головка винта на лицевой стороне панели; side = ±1 — с какой стороны стены."""
    model.add(cyl(BOLT_RADIUS, BOLT_HEIGHT * 2.0, (x, side * depth, z), "grey", axis="y", vertices=8))


def _panel_bolts(model, x0, x1, z0=PANEL_BOTTOM, z1=PANEL_TOP):
    """Крепёж по углам панели (у высокой панели — отдельно у нижней и у верхней части), с обеих сторон стены."""
    if x1 - x0 < 0.3:
        return
    if z0 < PANEL_SPLIT < z1:
        rows = (z0 + BOLT_INSET, PANEL_SPLIT - PANEL_SEAM / 2.0 - BOLT_INSET, (PANEL_SPLIT + z1) / 2.0)
    else:
        rows = ((z0 + z1) / 2.0,)
    for side in (-1.0, 1.0):
        for z in rows:
            for x in (x0 + BOLT_INSET, x1 - BOLT_INSET):
                _bolt(model, x, side, z)


def _conduit(model, x0, x1):
    """Кабель-канал в нише под карнизом: стальная труба, тонкий цветной кабель и хомуты через метр."""
    length = x1 - x0
    center = (x0 + x1) / 2.0
    for side in (-1.0, 1.0):
        model.add(cyl(0.017, length, (center, side * CONDUIT_Y, CONDUIT_Z), "grey", axis="x", vertices=8))
        model.add(cyl(0.008, length, (center, side * (CONDUIT_Y - 0.004), CONDUIT_Z - 0.027), "orange", axis="x",
                vertices=6))
        x = math.ceil(x0 - 0.499) + 0.5
        while x < x1 - 0.05:
            if x > x0 + 0.05:
                model.add(bar((0.035, 0.03, 0.062), (x, side * (CONDUIT_Y + 0.004), CONDUIT_Z - 0.008), "panel",
                        bevel=0.0))
            x += 1.0


def _kick_trim(model, x0, x1):
    """Стальная отбойная планка над плинтусом: ловит блик и отделяет плинтус от нижнего пояса."""
    model.add(bar((x1 - x0, 0.272, 0.03), ((x0 + x1) / 2.0, 0.0, TRIM_Z), "grey", bevel=0.008, segments=1))


def _wainscot_ribs(model, positions):
    """Вертикальные накладки нижнего пояса: стыки композитных листов."""
    z0, z1 = BANDS["wainscot"][0], BANDS["wainscot"][1]
    for x in positions:
        model.add(bar((0.05, 0.262, z1 - z0 - 0.06), (x, 0.0, (z0 + z1) / 2.0 + 0.015), "panel", axis="z", bevel=0.008,
                segments=1))


def _vent(model, x, side):
    """Вентиляционная решётка в нижнем поясе: рамка и наклонные ламели. side = ±1 — сторона стены."""
    face = side * 0.12
    model.add(bar((VENT_WIDTH + 0.06, 0.03, 0.30), (x, face, VENT_Z), "panel", axis="y", bevel=0.012, segments=1))
    model.add(box((VENT_WIDTH, 0.034, 0.24), (x, face, VENT_Z), "void", bevel=0.0))
    for index in range(5):
        z = VENT_Z - 0.09 + index * 0.045
        model.add(box((VENT_WIDTH - 0.02, 0.012, 0.04), (x, face + side * 0.014, z), "grey", bevel=0.0,
                rot=(side * math.radians(55.0), 0.0, 0.0)))
    for dx in (-VENT_WIDTH / 2.0 - 0.012, VENT_WIDTH / 2.0 + 0.012):
        for dz in (-0.12, 0.12):
            model.add(cyl(0.009, 0.036, (x + dx, face, VENT_Z + dz), "grey", axis="y", vertices=6))


def _wall_details(model, x0, x1, ribs, vents):
    """Общие детали сплошного участка стены от x0 до x1."""
    _kick_trim(model, x0, x1)
    _wainscot_ribs(model, ribs)
    for x, side in vents:
        _vent(model, x, side)


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


def _ceiling_grid(model):
    """Т-профиль подвесного потолка между плитами: крест через центр и половинки по краям клетки."""
    z = WALL_HEIGHT - CEILING_BAR_DROP + 0.012
    size_z = 0.024
    model.add(bar((GRID, CEILING_BAR, size_z), (0.0, 0.0, z), "wall_core", bevel=0.006, segments=1))
    for sign in (-1.0, 1.0):
        # Поперечины не доходят до продольного профиля: совпадающих граней нет.
        length = HALF - CEILING_BAR / 2.0
        model.add(bar((CEILING_BAR, length, size_z), (0.0, sign * (CEILING_BAR / 2.0 + length / 2.0), z - 0.002),
                "wall_core", axis="y", bevel=0.006, segments=1))
        edge = HALF - CEILING_BAR / 4.0
        model.add(bar((GRID, CEILING_BAR / 2.0, size_z), (0.0, sign * edge, z - 0.001), "wall_core", bevel=0.0))
        model.add(bar((CEILING_BAR / 2.0, GRID - CEILING_BAR, size_z), (sign * edge, 0.0, z - 0.003), "wall_core", axis="y",
                bevel=0.0))


def build_ceiling():
    model = Model("ceiling")
    model.add(bar((GRID, GRID, SLAB - 0.02), (0.0, 0.0, WALL_HEIGHT + SLAB / 2.0 + 0.01), "deep", bevel=0.0))
    _plates(model, WALL_HEIGHT, -0.06, ("mid", "mid"))
    _ceiling_grid(model)
    return model, None, [((GRID, GRID, SLAB), (0.0, 0.0, WALL_HEIGHT + SLAB / 2.0))]


def build_ceiling_light():
    model, _origins, boxes = build_ceiling()
    model.name = "ceiling_light"
    # Круглый светильник: белый корпус, стальной отражатель, утопленный рассеиватель и защитная решётка.
    bottom = WALL_HEIGHT - 0.10
    model.add(lathe([(0.62, WALL_HEIGHT + 0.02), (0.78, WALL_HEIGHT + 0.02), (0.78, bottom), (0.62, bottom)],
            (0.0, 0.0, 0.0), "white", closed=True, bevel=0.025, segments=32))
    model.add(lathe([(0.50, WALL_HEIGHT - 0.02), (0.50, WALL_HEIGHT - 0.035), (0.625, bottom + 0.012),
            (0.625, WALL_HEIGHT - 0.02)], (0.0, 0.0, 0.0), "grey", closed=True, segments=32))
    model.add(cyl(0.505, 0.05, (0.0, 0.0, WALL_HEIGHT - 0.01), "lamp", vertices=32))
    guard_z = bottom + 0.02
    model.add(lathe([(0.27, guard_z + 0.012), (0.295, guard_z + 0.012), (0.295, guard_z - 0.012), (0.27, guard_z - 0.012)],
            (0.0, 0.0, 0.0), "panel", closed=True, segments=32))
    for index in range(3):
        angle = math.radians(60.0 * index)
        model.add(box((1.24, 0.022, 0.022), (0.0, 0.0, guard_z), "panel", bevel=0.0, rot=(0.0, 0.0, angle)))
    for index in range(6):
        angle = math.radians(60.0 * index + 30.0)
        model.add(cyl(0.016, 0.012, (0.70 * math.cos(angle), 0.70 * math.sin(angle), bottom), "grey", vertices=8))
    return model, None, boxes


def build_ceiling_duct():
    """Потолочная плитка с коммуникациями: вентиляционный короб вдоль X и кабельный лоток. Новая деталь набора:
    ставится вместо ceiling там, где нужен «технический» потолок (коридоры, реакторная)."""
    model, _origins, boxes = build_ceiling()
    model.name = "ceiling_duct"
    duct_y, duct_w, duct_h = 1.05, 0.56, 0.30
    duct_z = WALL_HEIGHT - 0.06 - duct_h / 2.0
    model.add(bar((GRID, duct_w, duct_h), (0.0, duct_y, duct_z), "grey", bevel=0.02))
    # Фланцы стыков короба и подвесы.
    for x in (-1.0, 1.0):
        model.add(bar((0.05, duct_w + 0.05, duct_h + 0.05), (x, duct_y, duct_z), "panel", axis="x", bevel=0.008,
                segments=1))
    for x in (-1.6, 0.0, 1.6):
        model.add(bar((0.04, duct_w + 0.09, 0.012), (x, duct_y, duct_z - duct_h / 2.0 - 0.012), "panel", axis="x",
                bevel=0.0))
        for sign in (-1.0, 1.0):
            model.add(cyl(0.008, duct_h + 0.09, (x, duct_y + sign * (duct_w / 2.0 + 0.035), duct_z + 0.03), "grey",
                    vertices=6))
    # Приточная решётка снизу короба.
    model.add(box((0.62, 0.34, 0.02), (0.0, duct_y, duct_z - duct_h / 2.0 - 0.004), "panel", bevel=0.006, segments=1))
    for index in range(6):
        model.add(box((0.56, 0.012, 0.03), (0.0, duct_y - 0.125 + index * 0.05, duct_z - duct_h / 2.0 - 0.018), "grey",
                bevel=0.003, segments=1, rot=(math.radians(35.0), 0.0, 0.0)))
    # Кабельный лоток: перфорированный жёлоб и жгут кабелей.
    tray_y, tray_w = -1.2, 0.34
    tray_z = WALL_HEIGHT - 0.16
    model.add(bar((GRID, tray_w, 0.012), (0.0, tray_y, tray_z), "mid", bevel=0.0))
    for sign in (-1.0, 1.0):
        model.add(bar((GRID, 0.012, 0.06), (0.0, tray_y + sign * tray_w / 2.0, tray_z + 0.03), "grey", bevel=0.0))
    for x in (-1.5, 0.0, 1.5):
        for sign in (-1.0, 1.0):
            model.add(cyl(0.007, 0.16, (x, tray_y + sign * (tray_w / 2.0 + 0.012), tray_z + 0.08), "grey", vertices=6))
        model.add(bar((0.03, tray_w + 0.05, 0.012), (x, tray_y, tray_z - 0.012), "panel", axis="x", bevel=0.0))
    cables = (("deep", 0.022, -0.10), ("deep", 0.018, -0.05), ("orange", 0.014, -0.005), ("cyan", 0.012, 0.035),
            ("deep", 0.02, 0.085), ("red", 0.011, 0.125))
    for material, radius, offset in cables:
        model.add(cyl(radius, GRID, (0.0, tray_y + offset, tray_z + 0.006 + radius), material, axis="x", vertices=8))
    return model, None, boxes


def build_wall():
    model = Model("wall")
    _core(model, -HALF, HALF)
    for name in BANDS:
        _band(model, name, -HALF, HALF)
    for x0, x1 in ((-1.90, -0.05), (0.05, 1.90)):
        _panel(model, x0, x1)
        _panel_bolts(model, x0, x1)
    _conduit(model, -HALF, HALF)
    _wall_details(model, -HALF, HALF, (-1.0, 0.0, 1.0), ((-1.5, 1.0), (1.5, -1.0)))
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
        panel_x0, panel_x1 = sorted((sign * (outer + 0.05), sign * 1.90))
        _panel(model, panel_x0, panel_x1)
        _panel_bolts(model, panel_x0, panel_x1)
        _kick_trim(model, x0, x1)
        _wainscot_ribs(model, (sign * 1.42,))
        # Косяк и его тёмный башмак.
        # Косяк начинается внутри башмака: иначе их внутренние грани лежат в одной плоскости и мерцают.
        jamb_bottom = 0.20
        model.add(box((DOOR_FRAME, 0.36, header_top - jamb_bottom),
                (sign * (inner + DOOR_FRAME / 2.0), 0.0, (header_top + jamb_bottom) / 2.0), "yellow", bevel=0.03))
        model.add(box((0.20, 0.42, 0.30), (sign * (inner + 0.10), 0.0, 0.15), "panel", bevel=0.03))
        # Направляющая сдвижной двери в проёме и блок привода в верхнем углу рамы.
        model.add(bar((0.014, 0.12, DOOR_HEIGHT - 0.34), (sign * (inner - 0.004), 0.0, 0.32 + (DOOR_HEIGHT - 0.34) / 2.0),
                "grey", axis="z", bevel=0.004, segments=1))
        model.add(bar((0.02, 0.05, DOOR_HEIGHT - 0.40), (sign * (inner - 0.008), 0.0, 0.35 + (DOOR_HEIGHT - 0.40) / 2.0),
                "deep", axis="z", bevel=0.0))
        model.add(box((0.12, 0.40, 0.12), (sign * (inner + DOOR_FRAME / 2.0), 0.0, header_top - 0.07), "grey", bevel=0.015))
        for side in (-1.0, 1.0):
            for z in (0.55, 1.25, 1.95):
                model.add(cyl(0.014, 0.012, (sign * (inner + DOOR_FRAME / 2.0), side * 0.18, z), "grey", axis="y",
                        vertices=8))
            # Пульт двери — справа от проёма для того, кто стоит перед стеной.
            if sign * side < 0.0:
                continue
            panel_x = sign * (outer + 0.21)
            model.add(box((0.17, 0.03, 0.26), (panel_x, side * 0.132, 1.38), "panel", bevel=0.01, segments=1))
            model.add(box((0.12, 0.012, 0.085), (panel_x, side * 0.143, 1.44), "screen", bevel=0.0))
            model.add(cyl(0.02, 0.012, (panel_x - sign * 0.03, side * 0.143, 1.315), "glow_green", axis="y", vertices=8))
            model.add(cyl(0.02, 0.012, (panel_x + sign * 0.03, side * 0.143, 1.315), "red", axis="y", vertices=8))
    _core(model, -outer, outer, header_top, WALL_HEIGHT)
    _band(model, "cornice", -HALF, HALF)
    _conduit(model, -HALF, HALF)
    model.add(bar((DOOR_WIDTH, 0.32, DOOR_FRAME), (0.0, 0.0, DOOR_HEIGHT + DOOR_FRAME / 2.0), "yellow", bevel=0.03))
    # Короб привода двери над рамой и стальной рельс под перемычкой.
    model.add(bar((DOOR_WIDTH + 0.62, 0.37, 0.085), (0.0, 0.0, header_top + 0.05), "panel", bevel=0.015))
    model.add(bar((DOOR_WIDTH - 0.04, 0.07, 0.016), (0.0, 0.0, DOOR_HEIGHT - 0.006), "grey", bevel=0.004, segments=1))
    # Табличка-лампа над дверью с обеих сторон.
    model.add(box((0.96, PANEL_THICKNESS, 0.26), (0.0, 0.0, 2.755), "white", bevel=PANEL_BEVEL))
    model.add(box((0.56, 0.30, 0.13), (0.0, 0.0, 2.745), "glow_green", bevel=0.03))
    # Порожек закрывает шов плиток пола.
    model.add(bar((DOOR_WIDTH, 0.34, 0.012), (0.0, 0.0, 0.006), "grey", bevel=0.0))
    for x in (-0.45, 0.0, 0.45):
        model.add(bar((0.012, 0.30, 0.006), (x, 0.0, 0.014), "deep", axis="y", bevel=0.0))
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
    top_z0 = WINDOW_CENTER_Z + WINDOW_HEIGHT / 2.0 + WINDOW_FRAME + 0.05
    _panel(model, -frame_x - 0.05 + 0.10, frame_x + 0.05 - 0.10, top_z0, PANEL_TOP)
    _panel_bolts(model, -frame_x - 0.05 + 0.10, frame_x + 0.05 - 0.10, top_z0, PANEL_TOP)
    _conduit(model, -HALF, HALF)
    _wall_details(model, -HALF, HALF, (-1.0, 0.0, 1.0), ((-1.5, 1.0), (1.5, -1.0)))
    center = (0.0, WINDOW_CENTER_Z)
    outer = rounded_rect_points(WINDOW_WIDTH + 2.0 * WINDOW_FRAME, WINDOW_HEIGHT + 2.0 * WINDOW_FRAME, 0.45,
            steps=5, center=center)
    inner = rounded_rect_points(WINDOW_WIDTH, WINDOW_HEIGHT, 0.30, steps=5, center=center)
    # Рама на 1 см тоньше прежних 0,34 м: вместе с головками болтов габарит стены остаётся тем же.
    frame_depth = 0.33
    model.add(ring_prism(outer, inner, frame_depth, "yellow", plane="xz", offset=-frame_depth / 2.0, bevel=0.03))
    # Резиновый уплотнитель между рамой и стеклом.
    gasket = rounded_rect_points(WINDOW_WIDTH - 0.07, WINDOW_HEIGHT - 0.07, 0.265, steps=5, center=center)
    model.add(ring_prism(inner, gasket, 0.09, "rubber", plane="xz", offset=-0.045))
    model.add(prism(inner, 0.04, "glass", plane="xz", offset=-0.02))
    model.add(bar((0.07, 0.10, WINDOW_HEIGHT), (0.0, 0.0, WINDOW_CENTER_Z), "panel", axis="z", bevel=0.02))
    # Болты рамы: по середине её ширины, по прямым участкам контура.
    ring_x = WINDOW_WIDTH / 2.0 + WINDOW_FRAME / 2.0
    ring_z = WINDOW_HEIGHT / 2.0 + WINDOW_FRAME / 2.0
    spots = [(x, sign * ring_z) for x in (-0.84, -0.28, 0.28, 0.84) for sign in (-1.0, 1.0)]
    spots += [(sign * ring_x, z) for z in (-0.22, 0.22) for sign in (-1.0, 1.0)]
    for side in (-1.0, 1.0):
        for x, z in spots:
            model.add(cyl(0.02, 0.01, (x, side * frame_depth / 2.0, WINDOW_CENTER_Z + z), "grey", axis="y",
                    vertices=8))
    return model, None, [_wall_box(-HALF, HALF)]


def build_pillar():
    model = Model("pillar")
    model.add(box((0.50, 0.50, WALL_HEIGHT), (0.0, 0.0, WALL_HEIGHT / 2.0), "wall_core", bevel=0.06, segments=3))
    model.add(box((0.60, 0.60, 0.30), (0.0, 0.0, 0.15), "panel", bevel=0.04))
    model.add(box((0.60, 0.60, 0.25), (0.0, 0.0, WALL_HEIGHT - 0.125), "panel", bevel=0.04))
    rail_z0, rail_z1 = BANDS["rail"][0], BANDS["rail"][1]
    model.add(box((0.56, 0.56, rail_z1 - rail_z0), (0.0, 0.0, (rail_z0 + rail_z1) / 2.0), "cyan", bevel=0.03))
    # Накладки на гранях: светлая панель сверху и композит снизу, как на стенах, плюс крепёж и стальной поясок.
    upper_z0, upper_z1 = PANEL_BOTTOM + 0.02, PANEL_TOP - 0.02
    lower_z0, lower_z1 = 0.36, 0.90
    for size in ((0.30, 0.535), (0.535, 0.30)):
        model.add(box((size[0], size[1], upper_z1 - upper_z0), (0.0, 0.0, (upper_z0 + upper_z1) / 2.0), "white",
                bevel=0.02, segments=1))
        model.add(box((size[0], size[1], lower_z1 - lower_z0), (0.0, 0.0, (lower_z0 + lower_z1) / 2.0), "line",
                bevel=0.02, segments=1))
    model.add(box((0.575, 0.575, 0.03), (0.0, 0.0, TRIM_Z), "grey", bevel=0.008, segments=1))
    for axis in ("x", "y"):
        for sign in (-1.0, 1.0):
            for z in (upper_z0 + 0.07, upper_z1 - 0.07):
                for offset in (-0.09, 0.09):
                    loc = (sign * 0.2675, offset, z) if axis == "x" else (offset, sign * 0.2675, z)
                    model.add(cyl(0.014, BOLT_HEIGHT * 2.0, loc, "grey", axis=axis, vertices=8))
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
    "ceiling_duct": build_ceiling_duct,
    "wall": build_wall,
    "wall_doorway": build_wall_doorway,
    "wall_window": build_wall_window,
    "pillar": build_pillar,
    "railing": build_railing,
    "corridor_arch": build_corridor_arch,
}

# Светильник внутри ceiling_light: прожектор без теней светит строго вниз, яркость падает с расстоянием почти
# по закону обратных квадратов (spot_attenuation 2). Угол подобран так, чтобы пятно на полу (радиус 2 м)
# не выходило за клетку, — тогда свет без теней не пролезает под стеной в соседнюю комнату.
# Стены и тени даёт отдельный источник scenes/maps/lights/key_light.tscn (рецепт — в tests/visual/kit_preview.gd).
PREFAB_EXTRAS = {
    "ceiling_light": [
        "[node name=\"Light\" type=\"SpotLight3D\" parent=\".\"]",
        "transform = Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 3.02, 0)",
        "light_color = Color(1, 0.93, 0.82, 1)",
        "light_energy = 12.0",
        "light_specular = 0.5",
        "light_volumetric_fog_energy = 1.0",
        "spot_range = 5.5",
        "spot_attenuation = 2.0",
        "spot_angle = 33.0",
        "spot_angle_attenuation = 1.3",
        "",
    ],
}

if __name__ == "__main__":
    run_generator(BUILDERS, MODEL_DIR, PREFAB_DIR, prefab_extras=PREFAB_EXTRAS)
