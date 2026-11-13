"""Декор станции-офиса: мебель, техника, ящики, трубы. Модуль импортирует props.py; сам он не запускается.

Каждая функция build_* возвращает (Model, origins, коробки столкновений). Коробки — (размер, центр)
в координатах Blender; из них props.py --prefabs пишет префабы scenes/maps/props/*.tscn.
Перёд модели смотрит по +Y. У мебели перёд — сторона, с которой подходит человек.
Настенные детали (pipes, vent_grate, whiteboard): начало координат на плоскости стены на уровне пола.
"""

import math

from environment_lib import (Frame, Model, ball, bar, box, cone, cyl, lathe, pill, prism, ring_prism,
        rounded_rect_points, torus, tube)


def _polar(radius, angle_deg, z=0.0):
    angle = math.radians(angle_deg)
    return (radius * math.cos(angle), radius * math.sin(angle), z)


def mug_parts(origin, material):
    """Кружка с ручкой, дно в точке origin."""
    x, y, z = origin
    return [lathe([(0.0, z), (0.042, z), (0.05, z + 0.10), (0.036, z + 0.10), (0.034, z + 0.085), (0.0, z + 0.085)],
            (x, y, 0.0), material, segments=16),
            torus(0.028, 0.009, (x + 0.058, y, z + 0.052), material, axis="y", major_segments=12, minor_segments=6)]


def build_desk():
    """Офисный стол с монитором (на экране падающий график), клавиатурой, кружкой и резиновой уткой."""
    model = Model("desk")
    model.add(box((1.50, 0.75, 0.06), (0.0, 0.0, 0.72), "white", bevel=0.025))
    for sign in (-1.0, 1.0):
        model.add(box((0.07, 0.66, 0.70), (sign * 0.68, 0.0, 0.35), "line", bevel=0.025))
    model.add(box((1.30, 0.03, 0.42), (0.0, -0.30, 0.47), "line", bevel=0.01))
    model.add(box((0.42, 0.60, 0.56), (0.42, 0.0, 0.41), "grey", bevel=0.03))
    for z in (0.55, 0.30):
        model.add(box((0.36, 0.03, 0.22), (0.42, 0.30, z), "white", bevel=0.012))
        model.add(box((0.14, 0.035, 0.035), (0.42, 0.325, z + 0.04), "yellow", bevel=0.012))
    # Монитор.
    model.add(cyl(0.13, 0.02, (-0.20, -0.14, 0.76), "panel", bevel=0.008))
    model.add(box((0.06, 0.04, 0.22), (-0.20, -0.17, 0.86), "panel", bevel=0.012))
    model.add(box((0.68, 0.05, 0.42), (-0.20, -0.14, 1.11), "panel", bevel=0.03))
    model.add(box((0.61, 0.012, 0.35), (-0.20, -0.112, 1.11), "screen", bevel=0.006))
    for index, (height, material) in enumerate(((0.22, "glow_green"), (0.15, "glow_yellow"), (0.09, "glow_orange"),
            (0.04, "glow_red"))):
        model.add(box((0.075, 0.01, height), (-0.01 - 0.125 * index, -0.104, 0.97 + height / 2.0), material, bevel=0.004))
    # Клавиатура, мышь, кружка, утка, бумаги.
    model.add(box((0.42, 0.15, 0.022), (-0.20, 0.14, 0.761), "panel", bevel=0.008))
    model.add(ball(0.035, (0.11, 0.15, 0.765), "white", scale=(0.8, 1.25, 0.6)))
    model.extend(mug_parts((0.50, 0.16, 0.75), "yellow"))
    duck = (0.50, -0.17, 0.75)
    model.add(ball(0.06, (duck[0], duck[1], duck[2] + 0.05), "yellow", scale=(1.0, 1.25, 0.85)))
    model.add(ball(0.042, (duck[0], duck[1] + 0.045, duck[2] + 0.115), "yellow"))
    model.add(cone(0.02, 0.006, 0.04, (duck[0], duck[1] + 0.095, duck[2] + 0.11), "orange", axis="y", vertices=10))
    for sign in (-1.0, 1.0):
        model.add(ball(0.008, (duck[0] + sign * 0.022, duck[1] + 0.078, duck[2] + 0.128), "deep"))
    for index, turn in enumerate((6.0, -12.0)):
        model.add(box((0.21, 0.30, 0.004), (-0.56, 0.12, 0.753 + 0.004 * index), "white", bevel=0.0,
                rot=(0.0, 0.0, math.radians(turn))))
    return model, None, [((1.50, 0.75, 0.75), (0.0, 0.0, 0.375)), ((0.68, 0.10, 0.57), (-0.20, -0.14, 1.035))]


def build_chair():
    """Офисное кресло на пяти лучах. Перёд (+Y) — куда смотрит сидящий."""
    model = Model("chair")
    for index in range(5):
        angle = 72.0 * index + 90.0
        x, y, _z = _polar(0.15, angle)
        model.add(box((0.30, 0.06, 0.045), (x, y, 0.075), "panel", bevel=0.02, rot=(0.0, 0.0, math.radians(angle))))
        x, y, _z = _polar(0.29, angle)
        model.add(ball(0.036, (x, y, 0.036), "deep"))
    model.add(cyl(0.035, 0.32, (0.0, 0.0, 0.25), "grey", vertices=12))
    model.add(cyl(0.08, 0.05, (0.0, 0.0, 0.405), "panel", bevel=0.012, vertices=16))
    model.add(box((0.50, 0.48, 0.11), (0.0, 0.02, 0.475), "violet", bevel=0.05, segments=3))
    lean = math.radians(8.0)
    model.add(box((0.08, 0.05, 0.36), (0.0, -0.245, 0.62), "panel", bevel=0.02, rot=(lean, 0.0, 0.0)))
    model.add(box((0.48, 0.10, 0.50), (0.0, -0.285, 0.90), "violet", bevel=0.05, segments=3, rot=(lean, 0.0, 0.0)))
    for sign in (-1.0, 1.0):
        model.add(box((0.05, 0.28, 0.045), (sign * 0.275, 0.0, 0.68), "panel", bevel=0.018))
        model.add(box((0.04, 0.05, 0.20), (sign * 0.275, -0.06, 0.58), "panel", bevel=0.015))
    return model, None, [((0.58, 0.58, 1.14), (0.0, -0.03, 0.57))]


def build_water_cooler():
    """Кулер с бутылью, в которой живёт золотая рыбка."""
    model = Model("water_cooler")
    model.add(box((0.42, 0.42, 0.08), (0.0, 0.0, 0.04), "panel", bevel=0.03))
    model.add(box((0.38, 0.38, 0.94), (0.0, 0.0, 0.53), "white", bevel=0.06, segments=3))
    model.add(box((0.27, 0.03, 0.30), (0.0, 0.185, 0.66), "line", bevel=0.02))
    for sign, material in ((-1.0, "red"), (1.0, "cyan")):
        model.add(cyl(0.024, 0.06, (sign * 0.065, 0.215, 0.74), material, axis="y", bevel=0.006, vertices=12))
        model.add(box((0.02, 0.02, 0.05), (sign * 0.065, 0.235, 0.715), material, bevel=0.006))
    model.add(box((0.27, 0.11, 0.025), (0.0, 0.225, 0.50), "grey", bevel=0.008))
    model.add(cyl(0.13, 0.06, (0.0, 0.0, 1.02), "line", bevel=0.015))
    model.add(lathe([(0.0, 1.03), (0.07, 1.03), (0.09, 1.07), (0.175, 1.14), (0.175, 1.46), (0.14, 1.52), (0.0, 1.52)],
            (0.0, 0.0, 0.0), "water", bevel=0.012))
    # Рыбка.
    model.add(ball(0.045, (0.02, 0.03, 1.31), "orange", scale=(1.5, 0.75, 1.0)))
    model.add(prism([(-0.05, 1.31), (-0.11, 1.36), (-0.10, 1.31), (-0.11, 1.26)], 0.012, "orange", plane="xz", offset=0.024))
    model.add(ball(0.016, (0.062, 0.058, 1.322), "white"))
    model.add(ball(0.008, (0.068, 0.070, 1.322), "deep"))
    model.add(cyl(0.048, 0.30, (0.238, 0.04, 0.78), "grey", bevel=0.012, vertices=16))
    return model, None, [((0.42, 0.42, 1.52), (0.0, 0.0, 0.76))]


def build_vending_machine():
    """Торговый автомат: светящаяся витрина с банками, одна банка застряла."""
    model = Model("vending_machine")
    model.add(box((1.00, 0.10, 1.90), (0.0, -0.30, 0.95), "red", bevel=0.04))
    model.add(box((0.07, 0.70, 1.90), (0.465, 0.0, 0.95), "red", bevel=0.03))
    model.add(box((0.30, 0.70, 1.90), (-0.35, 0.0, 0.95), "red", bevel=0.04))
    model.add(box((1.00, 0.70, 0.22), (0.0, 0.0, 1.79), "red", bevel=0.04))
    model.add(box((1.00, 0.70, 0.56), (0.0, 0.0, 0.28), "red", bevel=0.04))
    model.add(box((1.04, 0.74, 0.08), (0.0, 0.0, 0.04), "panel", bevel=0.03))
    window_x = 0.115
    model.add(box((0.64, 0.02, 1.14), (window_x, -0.24, 1.12), "lamp_soft", bevel=0.0))
    cans = ("cyan", "yellow", "green", "orange", "violet", "white")
    for row in range(4):
        z = 0.58 + 0.285 * row
        model.add(box((0.64, 0.52, 0.03), (window_x, 0.02, z), "grey", bevel=0.008))
        for column in range(4):
            if row == 2 and column == 1:
                continue
            material = cans[(row * 3 + column) % len(cans)]
            model.add(cyl(0.055, 0.15, (window_x - 0.225 + 0.15 * column, 0.14, z + 0.09), material, bevel=0.012,
                    vertices=14))
    # Застрявшая банка.
    model.add(cyl(0.055, 0.15, (window_x - 0.05, 0.24, 1.02), "red", bevel=0.012, vertices=14,
            rot=(math.radians(20.0), math.radians(55.0), 0.0)))
    model.add(box((0.64, 0.02, 1.14), (window_x, 0.325, 1.12), "glass", bevel=0.0))
    # Колонка управления.
    model.add(box((0.20, 0.02, 0.12), (-0.35, 0.352, 1.45), "screen", bevel=0.006))
    for row in range(3):
        for column in range(2):
            model.add(box((0.07, 0.03, 0.06), (-0.39 + 0.085 * column, 0.352, 1.26 - 0.08 * row), "white", bevel=0.012))
    model.add(box((0.10, 0.03, 0.025), (-0.35, 0.352, 0.98), "deep", bevel=0.006))
    model.add(cyl(0.04, 0.04, (-0.35, 0.352, 0.86), "glow_green", axis="y", bevel=0.01, vertices=16))
    model.add(box((0.56, 0.03, 0.20), (window_x, 0.345, 0.30), "deep", bevel=0.02))
    model.add(box((0.50, 0.03, 0.06), (window_x, 0.36, 0.385), "grey", bevel=0.015))
    model.add(box((0.92, 0.03, 0.13), (0.0, 0.35, 1.795), "glow_yellow", bevel=0.02))
    return model, None, [((1.04, 0.74, 1.90), (0.0, 0.0, 0.95))]


def build_plant():
    """Фикус в горшке. Один стебель заканчивается глазом и присматривает за офисом."""
    model = Model("plant")
    model.add(lathe([(0.0, 0.0), (0.17, 0.0), (0.23, 0.33), (0.26, 0.33), (0.26, 0.40), (0.0, 0.40)], (0.0, 0.0, 0.0),
            "white", bevel=0.015))
    model.add(cyl(0.262, 0.035, (0.0, 0.0, 0.36), "orange", bevel=0.01))
    model.add(cyl(0.21, 0.02, (0.0, 0.0, 0.40), "deep"))
    model.add(cyl(0.03, 0.30, (0.0, 0.0, 0.54), "leaf", vertices=10))
    base_z = 0.60
    leaves = ((0.0, 38.0, 0.52), (60.0, 55.0, 0.44), (125.0, 32.0, 0.56), (185.0, 60.0, 0.42), (245.0, 40.0, 0.50),
            (305.0, 58.0, 0.46), (30.0, 12.0, 0.58), (210.0, 15.0, 0.52))
    for yaw_deg, tilt_deg, length in leaves:
        tilt = math.radians(tilt_deg)
        yaw = math.radians(yaw_deg)
        direction = (math.sin(yaw) * math.sin(tilt), -math.cos(yaw) * math.sin(tilt), math.cos(tilt))
        center = (direction[0] * length * 0.5, direction[1] * length * 0.5, base_z + direction[2] * length * 0.5)
        model.add(ball(0.5, center, "leaf", scale=(0.30, 0.07, length), rot=(tilt, 0.0, yaw)))
    # Стебель с глазом.
    eye = (0.10, 0.20, 1.12)
    model.add(tube([(0.02, 0.02, 0.42), (-0.04, 0.10, 0.75), (0.04, 0.16, 1.00), eye], 0.02, "leaf"))
    model.add(ball(0.075, eye, "white"))
    model.add(ball(0.04, (eye[0] + 0.012, eye[1] + 0.045, eye[2] - 0.006), "cyan"))
    model.add(ball(0.022, (eye[0] + 0.017, eye[1] + 0.066, eye[2] - 0.009), "deep"))
    return model, None, [((0.50, 0.50, 1.10), (0.0, 0.0, 0.55))]


def _crate(model, size, body_material):
    """Пластиковый ящик со стороной size: цветной корпус, тёмные уголки, белая бирка."""
    half = size / 2.0
    corner = size * 0.2
    model.add(box((size * 0.94, size * 0.94, size * 0.94), (0.0, 0.0, half), body_material, bevel=size * 0.05, segments=3))
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            for sz in (-1.0, 1.0):
                offset = half - corner / 2.0
                model.add(box((corner, corner, corner), (sx * offset, sy * offset, half + sz * offset), "panel",
                        bevel=size * 0.035))
    model.add(box((size * 0.42, size * 0.03, size * 0.28), (0.0, half * 0.95, half), "white", bevel=size * 0.02))
    arrow = [(-0.05 * size, half - 0.08 * size), (0.05 * size, half - 0.08 * size), (0.05 * size, half + 0.0 * size),
            (0.11 * size, half), (0.0, half + 0.10 * size), (-0.11 * size, half)]
    model.add(prism(arrow, size * 0.012, "red", plane="xz", offset=half * 0.95 + size * 0.015))
    for sign in (-1.0, 1.0):
        model.add(box((size * 0.03, size * 0.30, size * 0.09), (sign * half * 0.95, 0.0, half + size * 0.12), "deep",
                bevel=size * 0.012))
    return [((size, size, size), (0.0, 0.0, half))]


def build_crate_small():
    """Ящик 0,6 м."""
    model = Model("crate_small")
    return model, None, _crate(model, 0.6, "violet")


def build_crate_large():
    """Ящик 1,0 м."""
    model = Model("crate_large")
    return model, None, _crate(model, 1.0, "green")


def build_barrel():
    """Бочка со светящейся зелёной жижей, которая переливается через край."""
    model = Model("barrel")
    model.add(lathe([(0.0, 0.0), (0.26, 0.0), (0.30, 0.04), (0.30, 0.86), (0.27, 0.90), (0.24, 0.90), (0.24, 0.84),
            (0.0, 0.84)], (0.0, 0.0, 0.0), "yellow", bevel=0.012))
    for z in (0.30, 0.60):
        model.add(cyl(0.312, 0.05, (0.0, 0.0, z), "panel", bevel=0.015))
    model.add(cyl(0.245, 0.04, (0.0, 0.0, 0.87), "glow_green"))
    for x, y, radius in ((0.08, 0.05, 0.05), (-0.10, -0.04, 0.035), (0.0, -0.13, 0.028)):
        model.add(ball(radius, (x, y, 0.89), "glow_green"))
    # Потёк по стенке и лужица.
    model.add(pill(0.045, 0.34, (0.12, 0.275, 0.76), "glow_green"))
    model.add(pill(0.03, 0.20, (0.04, 0.293, 0.82), "glow_green"))
    model.add(ball(0.11, (0.17, 0.40, 0.012), "glow_green", scale=(1.0, 0.8, 0.1)))
    # Предупреждающий треугольник.
    for z0, z1, half_bottom, half_top in ((0.40, 0.56, 0.11, 0.0),):
        sign_frame = Frame((0.0, 0.30, 0.0), (0.0, 0.0, math.radians(-38.0)))
        triangle = prism([(-half_bottom, z0), (half_bottom, z0), (half_top, z1 + 0.03)], 0.012, "deep", plane="xz",
                offset=0.0)
        triangle.location = _polar(0.302, 52.0)
        triangle.rotation_euler = sign_frame.rot
        model.add(triangle)
    return model, None, [((0.62, 0.62, 0.92), (0.0, 0.0, 0.46))]


def build_locker():
    """Двойной шкафчик: из приоткрытой дверцы высовывается щупальце."""
    model = Model("locker")
    model.add(box((0.94, 0.52, 0.06), (0.0, 0.0, 0.03), "panel", bevel=0.02))
    model.add(box((0.90, 0.50, 1.86), (0.0, 0.0, 0.97), "line", bevel=0.035))
    model.add(box((0.94, 0.52, 0.06), (0.0, 0.0, 1.89), "panel", bevel=0.02))
    door_z = 0.97
    model.add(box((0.41, 0.035, 1.72), (-0.22, 0.25, door_z), "cyan", bevel=0.015))
    for index in range(3):
        model.add(box((0.22, 0.02, 0.03), (-0.22, 0.262, 1.58 - 0.07 * index), "deep", bevel=0.008))
    model.add(box((0.035, 0.04, 0.14), (-0.07, 0.275, 1.0), "white", bevel=0.012))
    model.add(box((0.41, 0.02, 1.72), (0.22, 0.225, door_z), "deep", bevel=0.0))
    # Правая дверца приоткрыта.
    hinge = (0.43, 0.25)
    swing = math.radians(32.0)
    center = (hinge[0] - 0.205 * math.cos(swing), hinge[1] + 0.205 * math.sin(swing), door_z)
    model.add(box((0.41, 0.035, 1.72), center, "cyan", bevel=0.015, rot=(0.0, 0.0, -swing)))
    door = Frame(center, (0.0, 0.0, -swing))
    for index in range(3):
        model.add(box((0.22, 0.02, 0.03), door.at(0.0, 0.013, 0.61 - 0.07 * index), "deep", bevel=0.008, rot=door.rot))
    model.add(box((0.035, 0.04, 0.14), door.at(-0.15, 0.025, 0.03), "white", bevel=0.012, rot=door.rot))
    # Щупальце.
    path = [(0.18, 0.18, 0.62), (0.10, 0.34, 0.60), (0.06, 0.46, 0.50), (0.10, 0.52, 0.36), (0.18, 0.50, 0.28),
            (0.20, 0.44, 0.33)]
    model.add(tube(path, 0.04, "violet"))
    model.add(ball(0.04, path[-1], "violet"))
    for point in ((0.065, 0.49, 0.47), (0.10, 0.545, 0.36)):
        model.add(ball(0.018, point, "red"))
    return model, None, [((0.94, 0.52, 1.92), (0.0, 0.0, 0.96))]


def build_server_rack():
    """Серверная стойка с рядами лампочек; один сервер горит красным."""
    model = Model("server_rack")
    model.add(box((0.74, 0.84, 0.08), (0.0, 0.0, 0.04), "deep", bevel=0.02))
    model.add(box((0.70, 0.80, 1.92), (0.0, 0.0, 1.02), "panel", bevel=0.04))
    for sign in (-1.0, 1.0):
        model.add(bar((0.035, 0.03, 1.80), (sign * 0.33, 0.40, 1.02), "cyan", axis="z", bevel=0.01))
    for index in range(7):
        z = 0.30 + 0.24 * index
        broken = index == 4
        model.add(box((0.56, 0.03, 0.20), (0.0, 0.405, z), "line", bevel=0.015))
        for led in range(4):
            material = "glow_red" if broken else ("glow_green" if (index + led) % 3 else "glow_cyan")
            model.add(box((0.035, 0.02, 0.035), (-0.21 + 0.06 * led, 0.42, z + 0.04), material, bevel=0.006))
        model.add(box((0.20, 0.02, 0.03), (0.13, 0.42, z + 0.04), "deep", bevel=0.006))
        model.add(box((0.44, 0.02, 0.025), (0.0, 0.42, z - 0.045), "deep", bevel=0.006))
    model.add(tube([(0.20, 0.42, 1.30), (0.26, 0.50, 1.05), (0.22, 0.52, 0.72), (0.12, 0.43, 0.58)], 0.016, "yellow"))
    model.add(box((0.50, 0.50, 0.03), (0.0, 0.0, 1.985), "line", bevel=0.01))
    return model, None, [((0.74, 0.84, 2.0), (0.0, 0.0, 1.0))]


def build_pipes():
    """Трубы вдоль стены, модуль 4 м: начало координат на плоскости стены на уровне пола."""
    model = Model("pipes")
    big_z, small_z = 2.52, 2.24
    model.add(cyl(0.10, 4.0, (0.0, 0.16, big_z), "cyan", axis="x"))
    model.add(cyl(0.055, 4.0, (0.0, 0.11, small_z), "yellow", axis="x", vertices=16))
    for x in (-4.0 / 3.0, 0.0, 4.0 / 3.0):
        model.add(box((0.10, 0.26, 0.56), (x - 0.35, 0.12, 2.40), "panel", bevel=0.03))
    for x in (-1.9, 1.9):
        model.add(cyl(0.135, 0.07, (x, 0.16, big_z), "grey", axis="x", bevel=0.012))
    # Отвод вниз с вентилем и манометром.
    drop_x = 0.95
    model.add(cyl(0.07, big_z - 0.02, (drop_x, 0.16, (big_z - 0.02) / 2.0 + 0.02), "cyan", vertices=16))
    model.add(ball(0.125, (drop_x, 0.16, big_z), "grey"))
    model.add(cyl(0.11, 0.08, (drop_x, 0.16, 0.04), "grey", bevel=0.015))
    model.add(cyl(0.10, 0.07, (drop_x, 0.16, 1.62), "grey", bevel=0.012))
    model.add(cyl(0.03, 0.14, (drop_x, 0.27, 1.25), "grey", axis="y", vertices=12))
    model.add(torus(0.13, 0.026, (drop_x, 0.33, 1.25), "red", axis="y"))
    for index in range(2):
        model.add(cyl(0.016, 0.26, (drop_x, 0.33, 1.25), "red", rot=(0.0, math.radians(90.0 * index + 45.0), 0.0),
                vertices=8))
    model.add(cyl(0.085, 0.05, (drop_x, 0.25, 1.95), "white", axis="y", bevel=0.012))
    model.add(cyl(0.065, 0.012, (drop_x, 0.277, 1.95), "deep", axis="y"))
    model.add(prism([(drop_x - 0.008, 1.95), (drop_x + 0.008, 1.95), (drop_x + 0.035, 1.995)], 0.008, "red", plane="xz",
            offset=0.281))
    model.add(cyl(0.025, 0.10, (drop_x, 0.20, 1.95), "grey", axis="y", vertices=10))
    return model, None, [((4.0, 0.28, 0.60), (0.0, 0.14, 2.40)), ((0.26, 0.40, 2.5), (drop_x, 0.20, 1.25))]


def build_vent_grate():
    """Вентиляционная решётка у пола: одна ламель выломана, из темноты смотрят два глаза."""
    model = Model("vent_grate")
    center_z = 0.62
    model.add(box((0.90, 0.05, 0.50), (0.0, 0.0, center_z), "deep", bevel=0.0))
    outer = rounded_rect_points(1.00, 0.60, 0.08, center=(0.0, center_z))
    inner = rounded_rect_points(0.84, 0.44, 0.04, center=(0.0, center_z))
    model.add(ring_prism(outer, inner, 0.08, "grey", plane="xz", offset=-0.02, bevel=0.015))
    slat_tilt = math.radians(-28.0)
    for index in range(5):
        if index == 2:
            continue
        model.add(box((0.86, 0.012, 0.085), (0.0, 0.035, center_z - 0.17 + 0.085 * index), "line", bevel=0.004,
                rot=(slat_tilt, 0.0, 0.0)))
    # Выломанная ламель висит на одном винте.
    model.add(box((0.86, 0.012, 0.085), (0.10, 0.06, center_z - 0.06), "line", bevel=0.004,
            rot=(slat_tilt, math.radians(-16.0), 0.0)))
    for sign in (-1.0, 1.0):
        model.add(ball(0.035, (sign * 0.06 - 0.12, 0.028, center_z + 0.005), "glow_yellow", scale=(1.0, 0.4, 1.0)))
        model.add(ball(0.014, (sign * 0.06 - 0.115, 0.042, center_z + 0.005), "deep"))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            model.add(cyl(0.018, 0.02, (sx * 0.44, 0.06, center_z + sz * 0.24), "white", axis="y", vertices=10))
    return model, None, [((1.00, 0.08, 0.60), (0.0, 0.04, center_z))]


def build_warning_sign():
    """Раскладная табличка «осторожно»: восклицательный знак с обеих сторон."""
    model = Model("warning_sign")
    lean = math.radians(14.0)
    for sign in (-1.0, 1.0):
        side = Frame((0.0, sign * 0.165, 0.0), (lean, 0.0, 0.0 if sign > 0 else math.pi))
        rot = side.rot
        model.add(box((0.34, 0.025, 0.70), side.at(0.0, 0.0, 0.35), "yellow", bevel=0.012, rot=rot))
        triangle_outer = [(-0.12, 0.26), (0.12, 0.26), (0.0, 0.50)]
        triangle_inner = [(-0.075, 0.285), (0.075, 0.285), (0.0, 0.445)]
        for points, material, offset in ((triangle_outer, "deep", 0.012), (triangle_inner, "yellow", 0.016)):
            part = prism(points, 0.006, material, plane="xz", offset=offset)
            part.location = side.at(0.0, 0.0, 0.0)
            part.rotation_euler = rot
            model.add(part)
        model.add(box((0.022, 0.008, 0.07), side.at(0.0, 0.024, 0.365), "deep", bevel=0.0, rot=rot))
        model.add(box((0.022, 0.008, 0.022), side.at(0.0, 0.024, 0.305), "deep", bevel=0.0, rot=rot))
        model.add(box((0.20, 0.008, 0.035), side.at(0.0, 0.016, 0.15), "deep", bevel=0.0, rot=rot))
    model.add(cyl(0.02, 0.36, (0.0, 0.0, 0.685), "panel", axis="x", vertices=10))
    return model, None, [((0.36, 0.40, 0.70), (0.0, 0.0, 0.35))]


def build_floor_lamp():
    """Торшер с жёлтым абажуром."""
    model = Model("floor_lamp")
    model.add(lathe([(0.0, 0.0), (0.18, 0.0), (0.20, 0.02), (0.20, 0.04), (0.05, 0.07), (0.0, 0.07)], (0.0, 0.0, 0.0),
            "panel", bevel=0.008))
    model.add(cyl(0.02, 1.32, (0.0, 0.0, 0.72), "grey", vertices=10))
    model.add(lathe([(0.21, 1.26), (0.235, 1.26), (0.14, 1.62), (0.115, 1.62)], (0.0, 0.0, 0.0), "shade", closed=True))
    model.add(cyl(0.118, 0.012, (0.0, 0.0, 1.615), "shade"))
    model.add(ball(0.085, (0.0, 0.0, 1.36), "lamp"))
    model.add(cyl(0.21, 0.01, (0.0, 0.0, 1.27), "lamp"))
    return model, None, [((0.40, 0.40, 1.62), (0.0, 0.0, 0.81))]


def build_whiteboard():
    """Настенная доска: рухнувший график, человечек с вопросом и счётчик «дней без происшествий: 0»."""
    model = Model("whiteboard")
    center_z = 1.72
    model.add(box((1.90, 0.05, 1.12), (0.0, 0.025, center_z), "grey", bevel=0.02))
    model.add(box((1.78, 0.02, 1.00), (0.0, 0.045, center_z), "white", bevel=0.004))
    model.add(box((1.30, 0.09, 0.03), (0.0, 0.085, center_z - 0.56), "grey", bevel=0.01))
    for x, material in ((-0.3, "red"), (-0.15, "cyan"), (0.0, "green")):
        model.add(cyl(0.012, 0.11, (x, 0.09, center_z - 0.535), material, axis="x", vertices=8))
    ink = 0.057
    def stroke(points, material="deep", radius=0.009):
        # Зритель стоит перед доской и видит +X слева, поэтому рисунок задан «как на бумаге» и отражён.
        model.add(tube([(-x, ink, center_z + z) for x, z in points], radius, material, smooth=False, sides=4))
    # График: оси и линия, которая падает за нижний край.
    stroke([(-0.80, 0.38), (-0.80, -0.30), (-0.10, -0.30)])
    stroke([(-0.76, -0.10), (-0.62, 0.12), (-0.50, 0.04), (-0.38, 0.30), (-0.26, 0.22), (-0.14, -0.38)], "red", 0.012)
    model.add(prism([(0.19, center_z - 0.36), (0.09, center_z - 0.36), (0.14, center_z - 0.44)], 0.012, "red",
            plane="xz", offset=ink - 0.006))
    # Человечек с вопросом.
    model.add(torus(0.07, 0.009, (-0.22, ink, center_z + 0.22), "deep", axis="y", major_segments=16, minor_segments=4))
    stroke([(0.22, 0.15), (0.22, -0.08)])
    stroke([(0.10, 0.08), (0.22, 0.03), (0.34, 0.10)])
    stroke([(0.13, -0.26), (0.22, -0.08), (0.31, -0.26)])
    stroke([(0.36, 0.34), (0.40, 0.40), (0.46, 0.38), (0.46, 0.32), (0.41, 0.27), (0.41, 0.23)], "cyan", 0.01)
    model.add(ball(0.014, (-0.41, ink, center_z + 0.18), "cyan"))
    # Счётчик: палочки зачёркнуты, рядом жирный красный ноль.
    for index in range(4):
        stroke([(0.56 + 0.05 * index, -0.12), (0.56 + 0.05 * index, -0.30)])
    stroke([(0.53, -0.27), (0.74, -0.15)], "red", 0.011)
    model.add(torus(0.10, 0.02, (-0.68, ink, center_z + 0.18), "red", axis="y", major_segments=20, minor_segments=4,
            rot=None))
    return model, None, [((1.90, 0.12, 1.14), (0.0, 0.06, center_z))]


def build_bunk():
    """Двухъярусная койка: внизу кто-то спит под одеялом, на полу тапочки."""
    model = Model("bunk")
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            model.add(box((0.09, 0.09, 1.75), (sx * 0.98, sy * 0.42, 0.875), "line", bevel=0.03))
    for z in (0.34, 1.16):
        model.add(box((1.96, 0.86, 0.10), (0.0, 0.0, z), "line", bevel=0.03))
        model.add(box((1.84, 0.80, 0.14), (0.0, 0.0, z + 0.11), "white", bevel=0.05, segments=3))
        model.add(box((0.46, 0.60, 0.11), (-0.64, 0.0, z + 0.215), "yellow", bevel=0.05, segments=3))
    model.add(box((1.20, 0.84, 0.10), (0.30, 0.0, 0.53), "cyan", bevel=0.045, segments=3))
    model.add(ball(0.5, (0.22, 0.0, 0.56), "cyan", scale=(1.05, 0.52, 0.34)))
    model.add(box((1.20, 0.84, 0.10), (0.30, 0.0, 1.35), "violet", bevel=0.045, segments=3))
    for sy in (-1.0, 1.0):
        model.add(bar((1.96, 0.05, 0.07), (0.0, sy * 0.42, 1.52), "line", bevel=0.02))
    # Лестница справа спереди.
    for x in (0.52, 0.86):
        model.add(box((0.05, 0.05, 1.30), (x, 0.47, 0.65), "yellow", bevel=0.02))
    for index in range(4):
        model.add(box((0.34, 0.045, 0.045), (0.69, 0.47, 0.22 + 0.30 * index), "yellow", bevel=0.018))
    for index, x in enumerate((-0.30, -0.12)):
        model.add(box((0.11, 0.24, 0.07), (x, 0.62, 0.035), "red", bevel=0.03,
                rot=(0.0, 0.0, math.radians(8.0 - 20.0 * index))))
        model.add(ball(0.035, (x + 0.01 - 0.03 * index, 0.72, 0.085), "white"))
    return model, None, [((2.05, 0.93, 1.75), (0.0, 0.0, 0.875))]


def build_coffee_machine():
    """Кофейный уголок: тумба, кофемашина с чашкой и башня немытых кружек."""
    model = Model("coffee_machine")
    model.add(box((0.74, 0.54, 0.08), (0.0, 0.0, 0.04), "panel", bevel=0.03))
    model.add(box((0.70, 0.50, 0.78), (0.0, 0.0, 0.47), "line", bevel=0.04))
    model.add(box((0.76, 0.56, 0.05), (0.0, 0.0, 0.875), "white", bevel=0.02))
    for sign in (-1.0, 1.0):
        model.add(box((0.30, 0.02, 0.62), (sign * 0.165, 0.252, 0.46), "mid", bevel=0.012))
        model.add(box((0.03, 0.03, 0.14), (sign * 0.05, 0.27, 0.56), "yellow", bevel=0.01))
    top = 0.90
    machine_x = -0.13
    model.add(box((0.36, 0.30, 0.10), (machine_x, -0.06, top + 0.05), "red", bevel=0.035))
    model.add(box((0.36, 0.14, 0.44), (machine_x, -0.14, top + 0.22), "red", bevel=0.04))
    model.add(box((0.36, 0.32, 0.14), (machine_x, -0.05, top + 0.42), "red", bevel=0.045))
    model.add(box((0.26, 0.02, 0.07), (machine_x, 0.112, top + 0.43), "screen", bevel=0.006))
    model.add(cyl(0.022, 0.05, (machine_x, 0.02, top + 0.33), "grey", vertices=10))
    model.add(box((0.24, 0.20, 0.012), (machine_x, 0.0, top + 0.106), "grey", bevel=0.004))
    model.extend(mug_parts((machine_x, 0.02, top + 0.112), "white"))
    model.add(cyl(0.035, 0.008, (machine_x, 0.02, top + 0.20), "wood", vertices=14))
    model.add(cyl(0.03, 0.03, (machine_x + 0.12, 0.115, top + 0.36), "glow_green", axis="y", bevel=0.008, vertices=12))
    for index, material in enumerate(("yellow", "cyan", "white", "violet")):
        wobble = 0.012 * (1 if index % 2 else -1)
        model.extend(mug_parts((0.22 + wobble, 0.04, top + 0.088 * index), material))
    return model, None, [((0.76, 0.56, 1.46), (0.0, 0.0, 0.73))]


def build_trash_bin():
    """Переполненная урна: бумажные комки, банка и один комок мимо."""
    model = Model("trash_bin")
    model.add(lathe([(0.0, 0.0), (0.17, 0.0), (0.225, 0.50), (0.25, 0.50), (0.25, 0.56), (0.205, 0.56), (0.16, 0.06),
            (0.0, 0.06)], (0.0, 0.0, 0.0), "grey", bevel=0.01))
    model.add(cyl(0.252, 0.03, (0.0, 0.0, 0.50), "cyan", bevel=0.008))
    for x, y, z, radius in ((0.0, 0.02, 0.52, 0.10), (0.09, -0.07, 0.56, 0.075), (-0.09, 0.05, 0.57, 0.07),
            (0.02, 0.06, 0.63, 0.065)):
        model.add(ball(radius, (x, y, z), "white", scale=(1.0, 0.9, 0.85)))
    model.add(cyl(0.05, 0.14, (-0.05, -0.10, 0.61), "orange", bevel=0.01, vertices=12,
            rot=(math.radians(50.0), math.radians(20.0), 0.0)))
    model.add(ball(0.065, (0.30, 0.22, 0.055), "white", scale=(1.0, 0.9, 0.85)))
    return model, None, [((0.50, 0.50, 0.60), (0.0, 0.0, 0.30))]


BUILDERS = {
    "desk": build_desk,
    "chair": build_chair,
    "water_cooler": build_water_cooler,
    "vending_machine": build_vending_machine,
    "plant": build_plant,
    "crate_small": build_crate_small,
    "crate_large": build_crate_large,
    "barrel": build_barrel,
    "locker": build_locker,
    "server_rack": build_server_rack,
    "pipes": build_pipes,
    "vent_grate": build_vent_grate,
    "warning_sign": build_warning_sign,
    "floor_lamp": build_floor_lamp,
    "whiteboard": build_whiteboard,
    "bunk": build_bunk,
    "coffee_machine": build_coffee_machine,
    "trash_bin": build_trash_bin,
}
