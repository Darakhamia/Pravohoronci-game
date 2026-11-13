"""Собирает боевую карту scenes/maps/station.tscn из набора станции, реквизита и игровых префабов.

Обычный Python без Blender, запуск из корня репозитория:
    python3 tools/maps/station.py
Сцену руками не правим: меняем таблицы ниже и запускаем скрипт заново. В конце он сам проверяет
расстановку (предметы не пересекаются, проходы и места перед станциями свободны) и печатает замечания.

План (вид сверху, клетка 4 x 4 м, север — это -Z, центр клетки (i, j) — точка (4*i, 0, 4*j)):

         0  1  2  3  4  5  6  7  8  9
     0   .  .  .  O  O  O  .  .  .  .      V — Серверная      O — Офис
     1   V  V  c  O  O  O  .  L  L  .      L — Лаборатория    W — Склад
     2   V  V  c  c  c  c  c  L  L  .      M — Кают-компания  R — Реактор
     3   W  W  c  M  M  M  c  R  R  R      K — Каюты (тупик)  A — Шлюз (тупик)
     4   W  W  c  M  M  M  c  R  R  R      c — коридоры: кольцо вокруг кают-компании
     5   W  W  c  M  M  M  c  R  R  R          и три отростка-тамбура
     6   .  .  c  c  c  c  c  .  .  .
     7   K  K  c  .  .  .  c  A  A  .
     8   K  K  .  .  .  .  .  A  A  .

Стены, окна, проёмы и колонны выводятся из плана сами: между разными помещениями — стена
(или проём из DOORS), между помещением и пустотой — наружная стена (окно из WINDOWS).
Рецепт света — в tests/visual/kit_preview.gd; здесь он записан таблицами.
"""

import math
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTPUT = os.path.join(REPO_ROOT, "scenes", "maps", "station.tscn")

GRID = 4.0
HALF = GRID / 2.0
# На сколько лицевая поверхность стены отстоит от линии сетки: сюда вешаем настенные предметы.
WALL_SURFACE = 0.13
# Половина толщины стены с запасом: от неё отсчитываем зазор для напольных предметов.
WALL_HALF = 0.15
# Зазор между стеной и спинкой напольного предмета.
WALL_GAP = 0.04
# Группа узла с потолком: обход tests/visual/station_tour.gd прячет его для вида сверху.
CEILING_GROUP = "station_ceilings"
# Высота, на которой висят щитки проводки и аварийные лампы.
PANEL_Y = 1.3
ALARM_Y = 2.55
MARKER_Y = 0.05

# Повороты вокруг Y (градусы): куда смотрит перёд модели (-Z без поворота).
NORTH = 0.0
WEST = 90.0
SOUTH = 180.0
EAST = -90.0

def number(value):
    text = ("%.4f" % value).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


PLAN = [
    "...OOO....",
    "VVcOOO.LL.",
    "VVcccccLL.",
    "WWcMMMcRRR",
    "WWcMMMcRRR",
    "WWcMMMcRRR",
    "..ccccc...",
    "KKc...cAA.",
    "KK.....AA.",
]
VOID = "."
CORRIDOR = "c"
COLUMNS = len(PLAN[0])
ROWS = len(PLAN)

ROOM_NAMES = {
    "M": "Кают-компания", "O": "Офис", "V": "Серверная", "L": "Лаборатория",
    "R": "Реактор", "W": "Склад", "K": "Каюты", "A": "Шлюз",
}
# Цвет помещения: надпись на табличках и цветной акцент света.
ACCENTS = {
    "M": (1.0, 0.93, 0.8), "O": (1.0, 0.8, 0.28), "V": (0.3, 0.62, 1.0), "L": (0.76, 0.46, 1.0),
    "R": (1.0, 0.55, 0.15), "W": (0.4, 1.0, 0.5), "K": (1.0, 0.5, 0.76), "A": (0.25, 1.0, 0.9),
    CORRIDOR: (0.76, 0.9, 1.0),
}
NORTH_CORRIDOR = "Сев. коридор"
SOUTH_CORRIDOR = "Южн. коридор"
WEST_CORRIDOR = "Зап. коридор"
EAST_CORRIDOR = "Вост. коридор"


def corridor_name(cell):
    """Как называется коридор, в котором лежит клетка."""
    i, j = cell
    if j <= 2:
        return NORTH_CORRIDOR
    if j >= 6:
        return SOUTH_CORRIDOR
    return WEST_CORRIDOR if i == 2 else EAST_CORRIDOR


# Проёмы: пары соседних клеток.
DOORS = [
    ((1, 1), (2, 1)),  # Серверная — северный тамбур
    ((0, 2), (0, 3)),  # Серверная — Склад
    ((2, 1), (3, 1)),  # северный тамбур — Офис
    ((5, 1), (5, 2)),  # Офис — северный коридор
    ((4, 2), (4, 3)),  # северный коридор — Кают-компания
    ((2, 5), (3, 5)),  # западный коридор — Кают-компания
    ((5, 3), (6, 3)),  # Кают-компания — восточный коридор
    ((1, 4), (2, 4)),  # Склад — западный коридор
    ((6, 2), (7, 2)),  # северный коридор — Лаборатория
    ((8, 2), (8, 3)),  # Лаборатория — Реактор
    ((6, 4), (7, 4)),  # восточный коридор — Реактор
    ((1, 7), (2, 7)),  # Каюты — юго-западный тамбур
    ((6, 7), (7, 7)),  # юго-восточный тамбур — Шлюз
]
# Окна в наружных стенах: (клетка, сторона). В северных видна планета.
WINDOWS = [
    ((3, 0), "N"), ((4, 0), "N"), ((5, 0), "N"), ((5, 0), "E"),
    ((0, 1), "N"), ((1, 1), "N"), ((2, 1), "N"), ((6, 2), "N"),
    ((7, 1), "N"), ((8, 1), "N"),
    ((9, 3), "N"), ((9, 4), "E"),
    ((3, 6), "S"), ((4, 6), "S"), ((5, 6), "S"), ((2, 6), "W"), ((6, 6), "E"),
    ((2, 7), "S"), ((6, 7), "S"),
    ((0, 7), "W"), ((0, 8), "S"),
    ((7, 8), "S"), ((8, 8), "S"),
]
# Арки поперёк коридора: пары соседних клеток коридора.
ARCHES = [
    ((5, 2), (6, 2)),
    ((2, 3), (2, 4)),
    ((6, 4), (6, 5)),
    ((3, 6), (4, 6)),
]
# Плитки пола с полосатой кромкой: клетка -> куда смотрит кромка.
HAZARD_FLOORS = {
    (8, 3): SOUTH, (8, 5): NORTH, (7, 4): EAST, (9, 4): WEST,
    (7, 7): WEST, (7, 8): SOUTH, (8, 8): SOUTH,
    (6, 4): EAST, (6, 7): EAST,
}
# Клетки без потолочного светильника: так помещение темнее.
PLAIN_CEILINGS = [
    (8, 4),  # над ядром реактора светит само ядро
    (1, 3), (0, 4), (1, 5),  # Склад
    (1, 1), (0, 2),  # Серверная
    (1, 7), (0, 8),  # Каюты
    (8, 7),  # Шлюз
    (3, 2), (5, 2), (2, 3), (2, 5), (6, 3), (6, 5), (3, 6), (5, 6),  # коридоры
]

# Габариты моделей в своих координатах: (x_min, x_max, z_min, z_max, высота). Перёд — это -Z.
FOOTPRINTS = {
    "barrel": (-0.31, 0.31, -0.31, 0.31, 0.94), "bunk": (-1.02, 1.02, -0.76, 0.46, 1.75),
    "chair": (-0.31, 0.31, -0.33, 0.36, 1.15), "coffee_machine": (-0.38, 0.38, -0.29, 0.28, 1.46),
    "crate_large": (-0.5, 0.5, -0.5, 0.5, 1.0), "crate_small": (-0.3, 0.3, -0.3, 0.3, 0.6),
    "desk": (-0.75, 0.75, -0.38, 0.38, 1.32), "floor_lamp": (-0.24, 0.24, -0.24, 0.24, 1.62),
    "locker": (-0.47, 0.47, -0.56, 0.26, 1.92), "plant": (-0.34, 0.33, -0.36, 0.32, 1.2),
    "server_rack": (-0.37, 0.37, -0.54, 0.42, 2.0), "trash_bin": (-0.25, 0.36, -0.28, 0.25, 0.69),
    "vending_machine": (-0.52, 0.52, -0.38, 0.37, 1.9), "warning_sign": (-0.18, 0.18, -0.17, 0.17, 0.7),
    "water_cooler": (-0.21, 0.29, -0.28, 0.21, 1.52), "railing": (-2.0, 2.0, -0.08, 0.08, 1.05),
    # Стол круглый: в проверке считаем его вписанным квадратом.
    "meeting_room_table": (-1.2, 1.2, -1.2, 1.2, 1.04),
    "task_keypad": (-0.31, 0.31, -0.22, 0.22, 1.34), "task_calibrator": (-0.47, 0.61, -0.32, 0.32, 1.4),
    "task_fuel_dock": (-0.44, 0.61, -0.33, 0.34, 1.1), "canister_rack": (-0.67, 0.67, -0.24, 0.25, 1.3),
    "reactor_core": (-1.25, 1.25, -1.25, 1.25, 2.6), "reactor_panel": (-0.68, 0.68, -0.34, 0.34, 1.17),
    "weapon_pickup": (-0.46, 0.46, -0.22, 0.22, 0.9),
    # Трубы: по стене идёт горизонтальная нитка под потолком, на пол опирается только стояк.
    "pipes": (0.82, 1.08, -0.4, 0.0, 2.5),
}
# Настенные предметы, которые в проход не выступают: в проверке расстановки не участвуют.
FLAT_PROPS = ("vent_grate", "whiteboard", "task_wiring", "sabotage_alarm")

# ---------------------------------------------------------------------------------------------
# Расстановка. Запись «у стены»: ("wall", имя, клетка, сторона, сдвиг вдоль стены[, высота]) —
# предмет стоит спиной к стене клетки и смотрит в помещение; сдвиг — на восток (стены N и S)
# или на юг (стены W и E) от середины стены. Запись «свободно»: ("free", имя, x, z, поворот[, высота]).
# ---------------------------------------------------------------------------------------------

DECOR = [
    # Кают-компания: круглый стол с кнопкой, автоматы у южной стены
    ("free", "meeting_room_table", 16.0, 16.0, NORTH),
    ("free", "chair", 18.1, 16.0, WEST - 8.0), ("free", "chair", 17.05, 17.82, 30.0 + 12.0),
    ("free", "chair", 14.95, 17.82, -30.0), ("free", "chair", 13.9, 16.0, EAST + 20.0),
    ("free", "chair", 14.95, 14.18, -150.0 + 10.0), ("free", "chair", 17.07, 14.14, 150.0 + 25.0),
    ("wall", "vending_machine", (3, 5), "S", 1.0), ("wall", "coffee_machine", (4, 5), "S", -1.25),
    ("wall", "water_cooler", (4, 5), "S", -0.45), ("wall", "trash_bin", (4, 5), "S", 0.3),
    ("free", "plant", 10.75, 10.75, 20.0), ("free", "plant", 21.25, 21.25, 200.0),
    ("wall", "whiteboard", (5, 5), "E", 0.0), ("wall", "vent_grate", (3, 3), "N", 0.3),
    ("free", "warning_sign", 21.2, 17.0, 30.0), ("free", "floor_lamp", 21.35, 14.9, NORTH),
    ("wall", "locker", (3, 3), "W", 0.4), ("wall", "locker", (3, 4), "W", -0.6),

    # Офис: столы лицом к окнам с планетой
    ("wall", "desk", (3, 0), "N", 0.5), ("wall", "desk", (4, 0), "N", 0.0), ("wall", "desk", (5, 0), "N", -0.5),
    ("free", "chair", 12.45, -0.55, 12.0), ("free", "chair", 16.15, -0.5, -18.0), ("free", "chair", 19.0, 0.1, 150.0),
    ("free", "desk", 14.5, 1.5, 8.0), ("free", "chair", 14.45, 0.65, 190.0),
    ("wall", "whiteboard", (4, 1), "S", 0.0),
    ("wall", "coffee_machine", (5, 1), "E", -0.9), ("wall", "water_cooler", (5, 0), "E", 1.5),
    ("free", "plant", 10.72, -1.28, 0.0), ("wall", "locker", (3, 0), "W", 0.7),
    ("free", "floor_lamp", 21.4, -1.42, NORTH), ("free", "trash_bin", 14.25, -1.45, 30.0),
    ("free", "plant", 21.2, 5.2, 120.0), ("free", "trash_bin", 17.6, 5.45, 0.0),

    # Серверная: ряд стоек у западной стены и остров посередине
    ("wall", "server_rack", (0, 1), "W", 0.4), ("wall", "server_rack", (0, 1), "W", 1.2),
    ("wall", "server_rack", (0, 2), "W", -2.0), ("wall", "server_rack", (0, 2), "W", -1.2),
    ("wall", "server_rack", (0, 2), "W", -0.4),
    ("free", "server_rack", 1.6, 5.6, WEST), ("free", "server_rack", 1.6, 6.4, WEST), ("free", "server_rack", 1.6, 7.2, WEST),
    ("free", "server_rack", 2.46, 5.6, EAST), ("free", "server_rack", 2.46, 6.4, EAST), ("free", "server_rack", 2.46, 7.2, EAST),
    ("wall", "desk", (1, 1), "E", 2.0), ("free", "chair", 4.55, 6.05, EAST + 15.0),
    ("wall", "vent_grate", (1, 2), "S", 1.25), ("free", "trash_bin", 5.3, 2.72, 0.0),
    ("free", "crate_small", -1.3, 9.25, 20.0), ("free", "warning_sign", 3.5, 4.9, -70.0),

    # Склад: ящики грудами, проход зигзагом
    ("free", "crate_large", 5.15, 10.85, 0.0), ("free", "crate_large", 4.0, 10.8, 6.0),
    ("free", "crate_small", 5.1, 10.85, 25.0, 1.0), ("free", "crate_large", 5.2, 11.97, -5.0),
    ("free", "crate_small", 2.95, 10.65, 40.0),
    ("free", "crate_large", 2.7, 13.6, 12.0), ("free", "crate_large", 1.55, 13.4, -4.0),
    ("free", "crate_small", 2.1, 13.5, 30.0, 1.0), ("free", "warning_sign", 3.7, 14.4, 160.0),
    ("free", "barrel", -1.4, 21.3, 0.0), ("free", "barrel", -0.65, 21.35, 50.0), ("free", "barrel", -1.35, 20.5, 110.0),
    ("free", "crate_large", 5.15, 21.15, 0.0), ("free", "crate_small", 5.3, 20.2, -12.0),
    ("free", "crate_small", 5.15, 21.15, 40.0, 1.0), ("free", "crate_large", 3.95, 21.2, 15.0),
    ("free", "crate_large", -1.3, 12.9, 4.0), ("free", "crate_small", -1.45, 13.85, -20.0),
    ("wall", "pipes", (1, 5), "E", 0.0), ("wall", "locker", (1, 3), "E", 1.2),
    ("wall", "vent_grate", (0, 5), "W", -1.0),

    # Реактор: ядро посередине, поручни по бокам, пульт с юга
    ("free", "railing", 29.9, 16.0, 90.0), ("free", "railing", 34.1, 16.0, 90.0),
    ("wall", "pipes", (7, 3), "N", 0.0), ("wall", "pipes", (7, 5), "S", 0.0),
    ("free", "barrel", 37.3, 10.7, 0.0), ("free", "barrel", 36.55, 10.65, 70.0),
    ("free", "warning_sign", 30.5, 13.35, 200.0),
    # Цветок с глазом вырос у самого ядра и смотрит на входящих.
    ("free", "plant", 32.0, 14.2, NORTH),
    ("wall", "locker", (7, 3), "W", -0.5), ("wall", "locker", (7, 3), "W", 0.5),
    ("free", "crate_large", 37.05, 21.05, 10.0), ("wall", "vent_grate", (8, 5), "S", 0.0),

    # Лаборатория: стенд посередине, «образцы» у окна
    ("free", "desk", 29.3, 5.8, SOUTH), ("free", "desk", 30.85, 5.8, SOUTH), ("free", "chair", 29.45, 6.75, 15.0),
    ("free", "plant", 27.0, 2.55, 0.0), ("free", "plant", 27.95, 2.5, 90.0), ("free", "plant", 28.9, 2.58, 200.0),
    ("free", "warning_sign", 28.0, 3.4, SOUTH),
    ("free", "barrel", 33.35, 9.35, 0.0), ("free", "barrel", 33.3, 8.55, 80.0),
    ("wall", "whiteboard", (8, 2), "E", -0.7), ("wall", "server_rack", (7, 1), "W", 1.0),
    ("wall", "locker", (7, 2), "S", 0.6), ("wall", "locker", (7, 2), "S", 1.6),
    ("free", "floor_lamp", 33.42, 2.5, NORTH),

    # Шлюз: скафандровые шкафчики, груз, полосатый пол
    ("wall", "locker", (7, 7), "N", -0.2), ("wall", "locker", (7, 7), "N", 0.8),
    ("free", "crate_large", 33.15, 33.15, 0.0), ("free", "crate_small", 32.2, 33.4, 20.0),
    ("free", "crate_small", 33.15, 33.15, 35.0, 1.0),
    ("free", "barrel", 26.6, 30.6, 0.0), ("free", "barrel", 26.65, 31.4, 60.0),
    ("wall", "pipes", (8, 7), "E", 0.0), ("free", "warning_sign", 29.3, 31.0, 15.0),
    ("wall", "vent_grate", (8, 7), "N", 1.3),

    # Каюты: койки, шкафчики, ящик вместо стола
    ("wall", "bunk", (0, 7), "N", 0.0), ("wall", "bunk", (1, 7), "N", -1.3), ("wall", "bunk", (0, 8), "W", 0.4),
    ("wall", "locker", (1, 8), "S", -0.9), ("wall", "locker", (1, 8), "S", 0.1),
    ("free", "floor_lamp", 5.4, 26.6, NORTH), ("free", "plant", -1.42, 29.0, 60.0),
    ("free", "crate_small", 0.5, 29.7, 10.0), ("free", "chair", 0.55, 28.9, SOUTH + 8.0),
    ("free", "chair", -0.3, 29.8, EAST - 12.0), ("free", "trash_bin", 5.25, 33.3, 0.0),

    # Коридоры: только у стен, середина свободна
    ("wall", "pipes", (3, 2), "N", 0.0), ("wall", "vent_grate", (5, 2), "S", 0.0),
    ("free", "plant", 25.3, 6.7, 0.0), ("free", "trash_bin", 6.6, 9.45, 90.0),
    ("wall", "vent_grate", (2, 3), "W", 0.0), ("wall", "pipes", (2, 4), "E", 0.0),
    ("wall", "pipes", (6, 3), "E", 0.0), ("free", "warning_sign", 25.3, 17.5, -25.0),
    ("wall", "vent_grate", (6, 5), "W", 0.0),
    ("free", "plant", 10.7, 22.7, 0.0), ("free", "crate_large", 20.2, 22.75, 5.0), ("free", "crate_small", 21.15, 22.62, -15.0),
    ("free", "warning_sign", 13.4, 25.25, 20.0), ("free", "trash_bin", 25.2, 25.2, 200.0),
    ("free", "barrel", 9.35, 29.35, 0.0), ("free", "crate_small", 22.72, 29.25, 30.0),
    # Кто-то поставил стул к окну южного коридора и смотрит в космос. Или смотрел.
    ("free", "chair", 17.6, 25.3, SOUTH - 6.0), ("free", "plant", 18.45, 25.35, 0.0),
    ("free", "plant", 9.3, 2.7, 0.0),
]

# Игровые префабы: запись как в DECOR, в конце — свойства экземпляра.
PISTOL = {"weapon": "res://resources/items/pistol.tres", "ammo": 6}


def task(title, location):
    return {"title": title, "location": location}


GAMEPLAY = [
    # Кают-компания
    ("free", "emergency_button", 16.0, 16.0, SOUTH, {}),
    # Реактор
    ("free", "reactor_core", 32.0, 16.0, NORTH, {}),
    ("free", "reactor_panel", 32.0, 19.3, SOUTH, {}),
    ("wall", "task_fuel_dock", (9, 3), "E", 0.8, task("Заправить реактор", "Реактор")),
    ("wall", "task_fuel_dock", (9, 5), "E", -0.8, task("Заправить реактор", "Реактор")),
    ("wall", "task_calibrator", (7, 5), "W", 0.6, task("Откалибровать давление", "Реактор")),
    # Склад
    ("wall", "canister_rack", (0, 5), "S", 2.0, {}),
    ("wall", "task_wiring", (0, 4), "W", 0.0, task("Починить проводку", "Склад")),
    # Серверная
    ("wall", "task_keypad", (1, 2), "S", -0.6, task("Перезагрузить сервер", "Серверная")),
    ("wall", "task_wiring", (1, 2), "E", 0.0, task("Переподключить кабели", "Серверная")),
    ("wall", "weapon_pickup", (0, 1), "N", 1.0, PISTOL),
    # Офис
    ("wall", "task_keypad", (3, 1), "S", 0.6, task("Ввести код доступа", "Офис")),
    ("wall", "task_calibrator", (5, 0), "E", 0.0, task("Настроить кондиционер", "Офис")),
    # Лаборатория
    ("wall", "task_calibrator", (8, 1), "E", 0.4, task("Откалибровать датчик", "Лаборатория")),
    ("wall", "task_wiring", (7, 1), "W", 0.0, task("Починить анализатор", "Лаборатория")),
    ("wall", "weapon_pickup", (8, 1), "N", 0.5, PISTOL),
    # Шлюз
    ("wall", "task_wiring", (8, 7), "N", 0.0, task("Починить замок шлюза", "Шлюз")),
    ("wall", "task_keypad", (8, 8), "E", -0.4, task("Ввести код шлюза", "Шлюз")),
    ("wall", "weapon_pickup", (7, 8), "S", -0.6, PISTOL),
    # Каюты
    ("wall", "task_wiring", (1, 8), "E", 0.0, task("Починить розетку", "Каюты")),
    ("wall", "weapon_pickup", (0, 8), "S", 1.0, PISTOL),
    # Южный коридор
    ("wall", "task_wiring", (4, 6), "N", 0.0, task("Починить освещение", SOUTH_CORRIDOR)),
]

# Аварийные лампы: (клетка, сторона, сдвиг вдоль стены) — на стене под потолком.
ALARMS = [
    ((4, 2), "N", -1.0), ((3, 6), "N", 0.0), ((2, 3), "E", 0.0), ((6, 5), "W", 0.0),
    ((4, 5), "S", 0.0), ((8, 5), "S", 0.0), ((0, 3), "W", 0.0), ((3, 0), "W", 0.0),
    ((7, 2), "S", 0.0), ((7, 7), "N", 0.0),
]

# Указатели поперёк коридора: (x, z, поворот, текст спереди, цвет, текст сзади, цвет).
# «Спереди» — сторона, куда смотрит перёд префаба; стрелка показывает на дверь.
BANNERS = [
    (16.0, 8.0, WEST, "Кают-компания →", "M", "← Кают-компания", "M"),
    (20.0, 8.0, WEST, "← Офис", "O", "Офис →", "O"),
    (8.0, 16.0, NORTH, "Склад →", "W", "← Склад", "W"),
    (8.0, 20.0, NORTH, "← Кают-компания", "M", "Кают-компания →", "M"),
    (24.0, 12.0, NORTH, "Кают-компания →", "M", "← Кают-компания", "M"),
    (24.0, 16.0, NORTH, "← Реактор", "R", "Реактор →", "R"),
    (10.0, 24.0, WEST, SOUTH_CORRIDOR, CORRIDOR, "← Каюты", "K"),
    (22.0, 24.0, WEST, "Шлюз →", "A", SOUTH_CORRIDOR, CORRIDOR),
    (8.0, 26.0, NORTH, "Каюты →", "K", WEST_CORRIDOR, CORRIDOR),
    (24.0, 26.0, NORTH, "← Шлюз", "A", EAST_CORRIDOR, CORRIDOR),
]
# Дополнительные таблички на глухих стенах: (клетка, сторона, текст, цвет).
EXTRA_SIGNS = [
    ((2, 2), "W", "Серверная →", "V"),
]

WARM = "Color(1, 0.95, 0.86, 1)"
COLD = "Color(0.86, 0.93, 1, 1)"


def color(rgb):
    return "Color(%s, %s, %s, 1)" % tuple(number(value) for value in rgb)


def key_light(name, x, y, z, light_color, energy, reach):
    """Источник с тенями: один на большую комнату."""
    return (name, (x, y, z), dict(light_color=light_color, light_energy=energy, omni_range=reach,
            omni_attenuation=1.0, shadow_enabled="true", shadow_bias=0.06))


def accent_light(name, x, y, z, room, energy, reach):
    """Цветной акцент без теней: до внутренних стен не достаёт (наружные не в счёт — за ними космос)."""
    return (name, (x, y, z), dict(light_color=color(ACCENTS[room]), light_energy=energy, omni_range=reach,
            omni_attenuation=0.8))


LIGHTS = [
    key_light("MeetingKey", 16.0, 2.9, 16.0, WARM, 1.5, 9.5),
    key_light("OfficeKey", 16.0, 2.8, 2.2, WARM, 1.5, 9.5),
    key_light("ReactorKey", 32.0, 2.95, 19.6, COLD, 1.2, 9.5),
    key_light("StorageKey", 2.0, 2.9, 16.0, "Color(0.82, 1, 0.88, 1)", 1.2, 9.0),
    accent_light("ReactorGlow", 32.0, 1.35, 16.0, "R", 3.0, 3.5),
    accent_light("OfficeAccent", 16.0, 2.2, 2.0, "O", 1.6, 3.6),
    accent_light("StorageAccent", 2.0, 2.0, 18.0, "W", 2.0, 3.6),
    accent_light("ServerAccent", 2.0, 2.2, 6.0, "V", 2.6, 3.6),
    accent_light("ServerCorner", 0.2, 1.8, 4.2, "V", 2.2, 3.6),
    accent_light("LabAccent", 30.0, 2.2, 6.0, "L", 2.6, 3.6),
    accent_light("LabCorner", 31.8, 1.8, 4.2, "L", 2.2, 3.6),
    accent_light("AirlockAccent", 30.0, 2.2, 30.0, "A", 2.4, 3.6),
    accent_light("AirlockCorner", 31.8, 1.8, 31.8, "A", 2.2, 3.6),
    accent_light("CabinsAccent", 2.0, 2.2, 30.0, "K", 2.4, 3.6),
    accent_light("CabinsCorner", 0.2, 1.8, 31.8, "K", 2.2, 3.6),
]

MEETING_CENTER = (16.0, 16.0)
SEAT_RADIUS = 3.0
SPAWN_RADIUS = 4.3
SEAT_COUNT = 8
# Камера для игроков без аватара: из угла кают-компании на стол.
CAMERA_POSITION = (20.7, 2.55, 20.7)
CAMERA_TARGET = (16.0, 0.7, 16.0)

# Границы для призрака и высота возврата упавших.
GHOST_BOUNDS = "AABB(-1.7, 0.3, -1.7, 39.4, 2.6, 35.4)"
KILL_PLANE_Y = -10.0

# Обход для проверки проходимости (tests/unit/test_station_map.gd): середина каждого помещения,
# каждый проём, все коридоры — и назад в начало. Между соседними точками должна пройти капсула игрока.
NAV_TOUR = [
    (16.0, 12.6), (16.0, 10.0), (16.0, 8.0),  # кают-компания -> северный коридор
    (20.0, 8.0), (20.0, 6.0), (20.0, 4.4), (17.6, 2.6), (12.0, 4.0),  # Офис
    (10.0, 4.0), (8.0, 4.0), (6.0, 4.0), (4.0, 4.0), (0.0, 4.0), (0.0, 6.0), (0.0, 8.6),  # тамбур, Серверная
    (0.0, 10.0), (0.0, 12.0), (0.0, 15.0), (2.5, 16.0), (4.0, 16.0),  # Склад
    (6.0, 16.0), (8.0, 16.0), (8.0, 20.0), (10.0, 20.0), (12.0, 20.0),  # западный коридор -> кают-компания
    (16.0, 19.8), (20.0, 19.4), (20.0, 12.0), (22.0, 12.0), (24.0, 12.0),  # вокруг стола -> восточный коридор
    (24.0, 16.0), (26.0, 16.0), (28.0, 16.0),  # Реактор
    (28.0, 20.9), (35.6, 20.9), (35.6, 12.0), (32.0, 12.0), (28.0, 12.0), (28.0, 16.0), (28.0, 12.0), (32.0, 12.0),
    (32.0, 10.0), (32.0, 8.4), (28.0, 8.2), (26.0, 8.0), (24.0, 8.0),  # Лаборатория -> северный коридор
    (24.0, 24.0), (24.0, 28.0), (26.0, 28.0), (28.0, 28.0), (30.0, 30.0),  # восточный коридор, Шлюз
    (28.0, 28.0), (26.0, 28.0), (24.0, 28.0), (24.0, 24.0),
    (8.0, 24.0), (8.0, 28.0), (6.0, 28.0), (4.0, 28.4), (2.6, 30.4),  # южный коридор, Каюты
    (4.0, 28.4), (6.0, 28.0), (8.0, 28.0), (8.0, 24.0),
    (8.0, 8.0), (16.0, 8.0), (16.0, 10.0), (16.0, 12.6),  # западный и северный коридоры -> кают-компания
]

# Проверка расстановки: радиус капсулы игрока с запасом и глубина свободного места перед станцией.
NAV_CLEARANCE = 0.4
FRONT_CLEARANCE = 1.2
DOOR_HALF_WIDTH = 0.7

SIDE_FACING = {"N": SOUTH, "S": NORTH, "W": EAST, "E": WEST}
SIDE_STEP = {"N": (0, -1), "S": (0, 1), "W": (-1, 0), "E": (1, 0)}


def transform(x, y, z, yaw_deg=0.0):
    angle = math.radians(yaw_deg)
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    values = (cos_a, 0.0, sin_a, 0.0, 1.0, 0.0, -sin_a, 0.0, cos_a, x, y, z)
    return "Transform3D(%s)" % ", ".join(number(value) for value in values)


def look_transform(position, target):
    """Преобразование камеры: -Z смотрит из position в target."""
    forward = [target[k] - position[k] for k in range(3)]
    length = math.sqrt(sum(value * value for value in forward))
    back = [-value / length for value in forward]
    right = [back[2], 0.0, -back[0]]
    right_length = math.hypot(right[0], right[2])
    right = [value / right_length for value in right]
    up = [back[1] * right[2] - back[2] * right[1], back[2] * right[0] - back[0] * right[2],
            back[0] * right[1] - back[1] * right[0]]
    values = (right[0], up[0], back[0], right[1], up[1], back[1], right[2], up[2], back[2]) + tuple(position)
    return "Transform3D(%s)" % ", ".join(number(value) for value in values)


def region(cell):
    i, j = cell
    if 0 <= j < ROWS and 0 <= i < COLUMNS:
        return PLAN[j][i]
    return VOID


def all_cells():
    return [(i, j) for j in range(ROWS) for i in range(COLUMNS) if region((i, j)) != VOID]


def neighbour(cell, side):
    step = SIDE_STEP[side]
    return (cell[0] + step[0], cell[1] + step[1])


def is_door(a, b):
    return (a, b) in DOORS or (b, a) in DOORS


def is_window(a, b):
    for cell, side in WINDOWS:
        if (cell == a and neighbour(cell, side) == b) or (cell == b and neighbour(cell, side) == a):
            return True
    return False


def border_kind(a, b):
    """Что стоит на границе двух соседних клеток: None, "wall", "wall_window" или "wall_doorway"."""
    region_a, region_b = region(a), region(b)
    if region_a == VOID and region_b == VOID:
        return None
    if is_door(a, b):
        return "wall_doorway"
    if region_a == VOID or region_b == VOID:
        return "wall_window" if is_window(a, b) else "wall"
    return None if region_a == region_b else "wall"


def wall_point(cell, side, along, distance):
    """Точка у стены клетки: distance — от линии сетки внутрь клетки."""
    center_x, center_z = cell[0] * GRID, cell[1] * GRID
    if side == "N":
        return (center_x + along, center_z - HALF + distance)
    if side == "S":
        return (center_x + along, center_z + HALF - distance)
    if side == "W":
        return (center_x - HALF + distance, center_z + along)
    return (center_x + HALF - distance, center_z + along)


def resolve(entry):
    """Запись таблицы -> (имя, x, y, z, поворот, свойства)."""
    properties = entry[-1] if isinstance(entry[-1], dict) else {}
    values = entry[:-1] if isinstance(entry[-1], dict) else entry
    name = values[1]
    if values[0] == "wall":
        cell, side, along = values[2], values[3], values[4]
        height = values[5] if len(values) > 5 else 0.0
        if name in FLAT_PROPS or name == "pipes":
            distance = WALL_SURFACE
        else:
            distance = WALL_HALF + WALL_GAP + FOOTPRINTS[name][3]
        if name == "task_wiring":
            height = PANEL_Y
        x, z = wall_point(cell, side, along, distance)
        return (name, x, height, z, SIDE_FACING[side], properties)
    height = values[5] if len(values) > 5 else 0.0
    return (name, values[2], height, values[3], values[4], properties)


def world_rect(name, x, z, yaw_deg):
    """Прямоугольник на полу, который занимает предмет: (x_min, x_max, z_min, z_max)."""
    x_min, x_max, z_min, z_max, _height = FOOTPRINTS[name]
    angle = math.radians(yaw_deg)
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    xs, zs = [], []
    for local_x in (x_min, x_max):
        for local_z in (z_min, z_max):
            xs.append(x + local_x * cos_a + local_z * sin_a)
            zs.append(z - local_x * sin_a + local_z * cos_a)
    return (min(xs), max(xs), min(zs), max(zs))


def front_rect(x, z, yaw_deg, depth_from, half_width):
    """Место, где стоит игрок перед станцией: полоса от переда предмета на FRONT_CLEARANCE вперёд."""
    angle = math.radians(yaw_deg)
    forward = (-math.sin(angle), -math.cos(angle))
    side = (math.cos(angle), -math.sin(angle))
    xs, zs = [], []
    for along in (depth_from, depth_from + FRONT_CLEARANCE):
        for across in (-half_width, half_width):
            xs.append(x + forward[0] * along + side[0] * across)
            zs.append(z + forward[1] * along + side[1] * across)
    return (min(xs), max(xs), min(zs), max(zs))


def rects_overlap(a, b, margin=0.0):
    return a[0] < b[1] - margin and b[0] < a[1] - margin and a[2] < b[3] - margin and b[2] < a[3] - margin


def segment_rect_distance(start, end, rect):
    """Грубо: наименьшее расстояние от отрезка до прямоугольника (по точкам отрезка)."""
    best = 1e9
    steps = max(2, int(math.hypot(end[0] - start[0], end[1] - start[1]) / 0.1))
    for step in range(steps + 1):
        t = step / steps
        px, pz = start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t
        dx = max(rect[0] - px, 0.0, px - rect[1])
        dz = max(rect[2] - pz, 0.0, pz - rect[3])
        best = min(best, math.hypot(dx, dz))
    return best


class SceneWriter:
    def __init__(self):
        self.resources = {}
        self.header = []
        self.body = []
        self.names = {}

    def resource(self, kind, path):
        if path not in self.resources:
            identifier = "%d_%s" % (len(self.resources) + 1, os.path.splitext(os.path.basename(path))[0])
            self.resources[path] = identifier
            self.header.append("[ext_resource type=\"%s\" path=\"%s\" id=\"%s\"]" % (kind, path, identifier))
        return "ExtResource(\"%s\")" % self.resources[path]

    def unique_name(self, base):
        count = self.names.get(base, 0) + 1
        self.names[base] = count
        return base if count == 1 else "%s%d" % (base, count)

    def node(self, name, kind, parent, properties=None, group=None):
        line = "[node name=\"%s\" type=\"%s\"%s%s]" % (name, kind, "" if parent is None else " parent=\"%s\"" % parent,
                "" if group is None else " groups=[\"%s\"]" % group)
        self.body.append(line)
        self._properties(properties)

    def instance(self, parent, base_name, path, x, y, z, yaw_deg, properties=None):
        if not os.path.exists(os.path.join(REPO_ROOT, path.replace("res://", ""))):
            raise SystemExit("нет файла %s" % path)
        name = self.unique_name(base_name)
        self.body.append("[node name=\"%s\" parent=\"%s\" instance=%s]" % (name, parent,
                self.resource("PackedScene", path)))
        self.body.append("transform = %s" % transform(x, y, z, yaw_deg))
        self._properties(properties)
        return name

    def override(self, name, parent, properties):
        """Меняет свойства узла внутри экземпляра префаба (например, текст таблички)."""
        self.body.append("[node name=\"%s\" parent=\"%s\"]" % (name, parent))
        self._properties(properties)

    def _properties(self, properties):
        for key, value in (properties or {}).items():
            self.body.append("%s = %s" % (key, value if isinstance(value, str) else number(value)))
        self.body.append("")

    def text(self):
        return "\n".join(["[gd_scene format=3]", ""] + self.header + [""] + self.body)


def pascal(name):
    return "".join(part.capitalize() for part in name.split("_"))


def quoted(text):
    return "\"%s\"" % text


def kit(name):
    return "res://scenes/maps/kit/%s.tscn" % name


def prop(name):
    return "res://scenes/maps/props/%s.tscn" % name


def item(name):
    return "res://scenes/items/%s.tscn" % name


def build_walls():
    """Стены и колонны по плану: [(деталь, x, z, поворот)], [(x, z)]."""
    walls = []
    # Сегменты стен у каждой вершины сетки: вершина (vi, vj) лежит в точке (4*vi - 2, 4*vj - 2).
    vertex_sides = {}

    def touch(vertex, direction):
        vertex_sides.setdefault(vertex, set()).add(direction)

    for j in range(ROWS + 1):
        for i in range(COLUMNS):
            kind = border_kind((i, j - 1), (i, j))
            if kind is not None:
                walls.append((kind, i * GRID, j * GRID - HALF, 0.0))
                touch((i, j), "E")
                touch((i + 1, j), "W")
    for j in range(ROWS):
        for i in range(COLUMNS + 1):
            kind = border_kind((i - 1, j), (i, j))
            if kind is not None:
                walls.append((kind, i * GRID - HALF, j * GRID, 90.0))
                touch((i, j), "S")
                touch((i, j + 1), "N")
    pillars = set()
    for vertex, sides in vertex_sides.items():
        # Прямой стык двух стен колонной не закрываем; угол, тройник, крест и торец — закрываем.
        if sides not in ({"N", "S"}, {"W", "E"}):
            pillars.add(vertex)
    arches = []
    for a, b in ARCHES:
        if a[0] == b[0]:
            # Клетки друг над другом: коридор идёт вдоль Z, арка стоит вдоль X.
            row = max(a[1], b[1])
            arches.append(("corridor_arch", a[0] * GRID, row * GRID - HALF, 0.0))
            pillars.update([(a[0], row), (a[0] + 1, row)])
        else:
            column = max(a[0], b[0])
            arches.append(("corridor_arch", column * GRID - HALF, a[1] * GRID, 90.0))
            pillars.update([(column, a[1]), (column, a[1] + 1)])
    points = sorted((vi * GRID - HALF, vj * GRID - HALF) for vi, vj in pillars)
    return walls, arches, points


def door_signs():
    """Таблички над проёмами: с каждой стороны написано, куда ведёт дверь."""
    signs = []
    for a, b in DOORS:
        for viewer, target in ((a, b), (b, a)):
            target_region = region(target)
            text = corridor_name(target) if target_region == CORRIDOR else ROOM_NAMES[target_region]
            if viewer[0] == target[0]:
                side = "S" if target[1] > viewer[1] else "N"
            else:
                side = "E" if target[0] > viewer[0] else "W"
            signs.append((viewer, side, text, target_region))
    return signs + EXTRA_SIGNS


def ring_markers(radius, count, offset_deg):
    """Точки по кругу вокруг стола, -Z каждой смотрит в центр."""
    markers = []
    for index in range(count):
        angle = math.radians(offset_deg + index * 360.0 / count)
        x = MEETING_CENTER[0] + radius * math.sin(angle)
        z = MEETING_CENTER[1] - radius * math.cos(angle)
        yaw = math.degrees(math.atan2(x - MEETING_CENTER[0], z - MEETING_CENTER[1]))
        markers.append((x, z, yaw))
    return markers


def validate(decor, gameplay, pillars):
    """Печатает замечания к расстановке: пересечения, занятые проходы и места перед станциями."""
    problems = []
    solids = []
    for name, x, y, z, yaw, _properties in decor + gameplay:
        if name in FLAT_PROPS or name not in FOOTPRINTS:
            continue
        solids.append((name, world_rect(name, x, z, yaw), y, y + FOOTPRINTS[name][4]))
    # Кнопка стоит в отверстии стола — это не пересечение.
    nested = {frozenset(("meeting_room_table", "emergency_button"))}
    for first in range(len(solids)):
        for second in range(first + 1, len(solids)):
            a, b = solids[first], solids[second]
            if frozenset((a[0], b[0])) in nested:
                continue
            if rects_overlap(a[1], b[1], 0.02) and a[2] < b[3] - 0.02 and b[2] < a[3] - 0.02:
                problems.append("пересекаются %s и %s около (%.1f, %.1f)" % (a[0], b[0], a[1][0], a[1][2]))
    for x, z in pillars:
        rect = (x - 0.3, x + 0.3, z - 0.3, z + 0.3)
        for name, solid, bottom, _top in solids:
            if bottom < 0.1 and rects_overlap(rect, solid, 0.02):
                problems.append("%s стоит в колонне (%.0f, %.0f)" % (name, x, z))
    keep_clear = []
    for a, b in DOORS:
        middle = ((a[0] + b[0]) * HALF, (a[1] + b[1]) * HALF)
        if a[0] == b[0]:
            keep_clear.append(("проём", (middle[0] - DOOR_HALF_WIDTH, middle[0] + DOOR_HALF_WIDTH,
                    middle[1] - FRONT_CLEARANCE, middle[1] + FRONT_CLEARANCE)))
        else:
            keep_clear.append(("проём", (middle[0] - FRONT_CLEARANCE, middle[0] + FRONT_CLEARANCE,
                    middle[1] - DOOR_HALF_WIDTH, middle[1] + DOOR_HALF_WIDTH)))
    for name, x, _y, z, yaw, _properties in gameplay:
        if name in ("reactor_core", "emergency_button", "sabotage_alarm"):
            continue
        depth = 0.0 if name == "task_wiring" else -FOOTPRINTS[name][2]
        keep_clear.append((name, front_rect(x, z, yaw, depth + 0.02, 0.45)))
    for label, zone in keep_clear:
        for name, solid, bottom, _top in solids:
            if bottom < 1.8 and name != label and rects_overlap(zone, solid, 0.02):
                problems.append("%s мешает: %s около (%.1f, %.1f)" % (name, label, zone[0], zone[2]))
    for index in range(len(NAV_TOUR) - 1):
        for name, solid, bottom, _top in solids:
            if bottom < 1.9 and segment_rect_distance(NAV_TOUR[index], NAV_TOUR[index + 1], solid) < NAV_CLEARANCE:
                problems.append("%s стоит на обходе между %s и %s" % (name, NAV_TOUR[index], NAV_TOUR[index + 1]))
    for problem in sorted(set(problems)):
        print("ЗАМЕЧАНИЕ:", problem)
    return len(set(problems))


def main():
    scene = SceneWriter()
    script = scene.resource("Script", "res://scripts/gameplay/game_map.gd")
    environment = scene.resource("Environment", "res://resources/maps/station_environment.tres")
    scene.node("Station", "Node3D", None, {"script": script, "kill_plane_y": KILL_PLANE_Y,
            "ghost_bounds": GHOST_BOUNDS})
    scene.node("WorldEnvironment", "WorldEnvironment", ".", {"environment": environment})

    walls, arches, pillars = build_walls()
    cells = all_cells()
    scene.node("Structure", "Node3D", ".")
    scene.node("Floors", "Node3D", "Structure")
    for cell in cells:
        x, z = cell[0] * GRID, cell[1] * GRID
        if cell in HAZARD_FLOORS:
            scene.instance("Structure/Floors", "FloorHazard", kit("floor_hazard"), x, 0, z, HAZARD_FLOORS[cell])
        else:
            scene.instance("Structure/Floors", "Floor", kit("floor"), x, 0, z, 0)
    scene.node("Walls", "Node3D", "Structure")
    for name, x, z, yaw in walls + arches:
        scene.instance("Structure/Walls", pascal(name), kit(name), x, 0, z, yaw)
    scene.node("Pillars", "Node3D", "Structure")
    for x, z in pillars:
        scene.instance("Structure/Pillars", "Pillar", kit("pillar"), x, 0, z, 0)

    scene.node("Ceilings", "Node3D", ".", group=CEILING_GROUP)
    for cell in cells:
        name = "ceiling" if cell in PLAIN_CEILINGS else "ceiling_light"
        scene.instance("Ceilings", pascal(name), kit(name), cell[0] * GRID, 0, cell[1] * GRID, 0)

    decor = [resolve(entry) for entry in DECOR]
    scene.node("Decor", "Node3D", ".")
    for name, x, y, z, yaw, _properties in decor:
        path = kit(name) if name == "railing" else prop(name)
        scene.instance("Decor", pascal(name), path, x, y, z, yaw)

    scene.node("Signs", "Node3D", ".")
    for cell, side, text, target_region in door_signs():
        x, z = wall_point(cell, side, 0.0, WALL_SURFACE)
        name = scene.instance("Signs", "SignDoor", prop("sign_door"), x, 0, z, SIDE_FACING[side])
        scene.override("Label", "Signs/" + name, {"text": quoted(text), "modulate": color(ACCENTS[target_region])})
    for x, z, yaw, front_text, front_region, back_text, back_region in BANNERS:
        name = scene.instance("Signs", "SignBanner", prop("sign_banner"), x, 0, z, yaw)
        scene.override("LabelFront", "Signs/" + name, {"text": quoted(front_text),
                "modulate": color(ACCENTS[front_region])})
        scene.override("LabelBack", "Signs/" + name, {"text": quoted(back_text),
                "modulate": color(ACCENTS[back_region])})

    gameplay = [resolve(entry) for entry in GAMEPLAY]
    scene.node("Gameplay", "Node3D", ".")
    for name, x, y, z, yaw, properties in gameplay:
        values = {}
        for key, value in properties.items():
            if key == "weapon":
                values[key] = scene.resource("Resource", value)
            elif isinstance(value, str):
                values[key] = quoted(value)
            else:
                values[key] = value
        scene.instance("Gameplay", pascal(name), item(name), x, y, z, yaw, values)
    scene.node("Alarms", "Node3D", ".")
    for cell, side, along in ALARMS:
        x, z = wall_point(cell, side, along, WALL_SURFACE)
        scene.instance("Alarms", "SabotageAlarm", item("sabotage_alarm"), x, ALARM_Y, z, SIDE_FACING[side])

    scene.node("Lights", "Node3D", ".")
    for name, position, properties in LIGHTS:
        values = {"transform": transform(*position)}
        values.update(properties)
        scene.node(name, "OmniLight3D", "Lights", values)

    scene.node("SpawnPoints", "Node3D", ".")
    for index, (x, z, yaw) in enumerate(ring_markers(SPAWN_RADIUS, SEAT_COUNT, 0.0)):
        scene.node("SpawnPoint%d" % (index + 1), "Marker3D", "SpawnPoints", {"transform": transform(x, MARKER_Y, z, yaw)})
    scene.node("MeetingSeats", "Node3D", ".")
    for index, (x, z, yaw) in enumerate(ring_markers(SEAT_RADIUS, SEAT_COUNT, 180.0 / SEAT_COUNT)):
        scene.node("Seat%d" % (index + 1), "Marker3D", "MeetingSeats", {"transform": transform(x, MARKER_Y, z, yaw)})
    scene.node("NavCheck", "Node3D", ".")
    for index, (x, z) in enumerate(NAV_TOUR):
        scene.node("Nav%02d" % (index + 1), "Marker3D", "NavCheck", {"transform": transform(x, 0, z)})

    scene.node("Players", "Node3D", ".")
    scene.node("PlayerSpawner", "MultiplayerSpawner", ".", {
        "_spawnable_scenes": "PackedStringArray(\"res://scenes/characters/player.tscn\")",
        "spawn_path": "NodePath(\"../Players\")",
    })
    scene.node("Camera3D", "Camera3D", ".", {"transform": look_transform(CAMERA_POSITION, CAMERA_TARGET),
            "current": "true", "fov": 75.0})

    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(scene.text())
    problem_count = validate(decor, gameplay, pillars)
    print("WROTE %s: клеток %d, стен %d, колонн %d, декора %d, игровых предметов %d, замечаний %d" % (
            OUTPUT, len(cells), len(walls), len(pillars), len(decor), len(gameplay) + len(ALARMS), problem_count))


if __name__ == "__main__":
    main()
