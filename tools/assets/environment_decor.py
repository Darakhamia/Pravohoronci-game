"""Декор станции-офиса: мебель, техника, ящики, трубы. Модуль импортирует props.py; сам он не запускается.

Каждая функция build_* возвращает (Model, origins, коробки столкновений). Коробки — (размер, центр)
в координатах Blender; из них props.py --prefabs пишет префабы scenes/maps/props/*.tscn.
Перёд модели смотрит по +Y. У мебели перёд — сторона, с которой подходит человек.
Настенные детали (pipes, vent_grate, whiteboard): начало координат на плоскости стены на уровне пола.
"""

import math

from environment_lib import (Frame, Model, ball, bar, bolt, box, cone, cushion, cushion_rim, cyl, lathe, pill, prism,
        ring_prism, rounded_rect_points, shell, torus, tube)


def _polar(radius, angle_deg, z=0.0):
    angle = math.radians(angle_deg)
    return (radius * math.cos(angle), radius * math.sin(angle), z)


def mug_parts(origin, material):
    """Кружка с ручкой и недопитым кофе, дно в точке origin."""
    x, y, z = origin
    return [lathe([(0.0, z), (0.038, z), (0.043, z + 0.006), (0.047, z + 0.094), (0.0445, z + 0.099), (0.041, z + 0.094),
            (0.039, z + 0.012), (0.0, z + 0.012)], (x, y, 0.0), material, segments=20),
            cyl(0.040, 0.004, (x, y, z + 0.078), "wood", vertices=20),
            tube([(x + 0.045, y, z + 0.078), (x + 0.070, y, z + 0.073), (x + 0.078, y, z + 0.050),
            (x + 0.067, y, z + 0.028), (x + 0.043, y, z + 0.024)], 0.0065, material, steps=3)]


def _caster(model, x, y, yaw_deg):
    """Сдвоенный ролик кресла под точкой (x, y)."""
    yaw = math.radians(yaw_deg)
    model.add(cyl(0.009, 0.04, (x, y, 0.068), "grey", vertices=8))
    model.add(box((0.034, 0.05, 0.03), (x, y, 0.044), "panel", bevel=0.01, rot=(0.0, 0.0, yaw)))
    for sign in (-1.0, 1.0):
        center = (x + sign * 0.017 * math.cos(yaw), y + sign * 0.017 * math.sin(yaw), 0.027)
        model.add(cyl(0.027, 0.014, center, "rubber", rot=(0.0, math.pi / 2.0, yaw), bevel=0.004, vertices=14))


def _piping(model, size, puff, frame, material="panel", radius=0.005):
    """Кант по кромке подушки cushion(size, puff): frame — её положение и поворот."""
    points = [frame.at(*point) for point in cushion_rim(size, puff)]
    model.add(tube(points, radius, material, smooth=False))


def build_desk():
    """Офисный стол: столешница из пластика на стальной раме, тумба, монитор (на экране падающий график),
    клавиатура, мышь, кружка и резиновая утка."""
    model = Model("desk")
    model.add(box((1.50, 0.75, 0.036), (0.0, 0.0, 0.732), "laminate", bevel=0.005))
    model.add(bar((1.46, 0.71, 0.022), (0.0, 0.0, 0.703), "line", axis="z", bevel=0.01))
    # Рама: две стальные «П» с опорами на регулируемых ножках.
    for sign in (-1.0, 1.0):
        x = sign * 0.69
        for y in (-0.27, 0.27):
            model.add(bar((0.045, 0.045, 0.66), (x, y, 0.365), "grey", axis="z", bevel=0.006))
            model.add(cyl(0.022, 0.014, (x, y, 0.007), "rubber", vertices=10))
        model.add(bar((0.05, 0.66, 0.035), (x, 0.0, 0.035), "grey", axis="y", bevel=0.006))
        model.add(bar((0.05, 0.60, 0.035), (x, 0.0, 0.675), "grey", axis="y", bevel=0.006))
        for y in (-0.27, 0.27):
            model.add(bolt((x + sign * 0.026, y, 0.675), axis="x", radius=0.008))
    model.add(box((1.33, 0.02, 0.36), (0.0, -0.30, 0.49), "line", bevel=0.006))
    # Тумба с двумя ящиками.
    model.add(box((0.42, 0.60, 0.56), (0.42, 0.0, 0.41), "grey", bevel=0.012))
    for z in (0.55, 0.30):
        model.add(box((0.385, 0.018, 0.235), (0.42, 0.303, z), "white", bevel=0.006))
        model.add(bar((0.16, 0.012, 0.012), (0.42, 0.335, z + 0.07), "chrome", bevel=0.004))
        for dx in (-0.065, 0.065):
            model.add(cyl(0.005, 0.024, (0.42 + dx, 0.323, z + 0.07), "chrome", axis="y", vertices=8))
    model.add(bolt((0.575, 0.313, 0.64), axis="y", radius=0.009, material="chrome"))
    for x in (0.25, 0.59):
        for y in (-0.25, 0.25):
            model.add(cyl(0.02, 0.13, (x, y, 0.065), "rubber", vertices=10))
    # Монитор: подставка, шарнир, корпус с рамкой.
    screen_x, screen_z = -0.20, 1.11
    model.add(box((0.27, 0.19, 0.012), (screen_x, -0.15, 0.756), "panel", bevel=0.005))
    model.add(box((0.055, 0.022, 0.25), (screen_x, -0.185, 0.885), "panel", bevel=0.008))
    model.add(cyl(0.02, 0.10, (screen_x, -0.176, 1.01), "grey", axis="x", vertices=12))
    model.add(box((0.68, 0.028, 0.42), (screen_x, -0.142, screen_z), "panel", bevel=0.008))
    model.add(box((0.40, 0.03, 0.24), (screen_x, -0.165, screen_z - 0.02), "panel", bevel=0.012))
    outer = rounded_rect_points(0.68, 0.42, 0.012, center=(screen_x, screen_z))
    inner = rounded_rect_points(0.635, 0.36, 0.004, center=(screen_x, screen_z + 0.012))
    model.add(ring_prism(outer, inner, 0.008, "panel", plane="xz", offset=-0.13, bevel=0.002))
    model.add(bar((0.64, 0.004, 0.365), (screen_x, -0.127, screen_z + 0.012), "screen", axis="y", bevel=0.0))
    model.add(cyl(0.004, 0.003, (screen_x + 0.30, -0.1215, screen_z - 0.19), "glow_green", axis="y", vertices=8))
    model.add(cyl(0.009, 0.002, (screen_x, -0.1215, screen_z - 0.19), "chrome", axis="y", vertices=10))
    for index, (height, material) in enumerate(((0.22, "glow_green"), (0.15, "glow_yellow"), (0.09, "glow_orange"),
            (0.04, "glow_red"))):
        model.add(bar((0.075, 0.003, height), (-0.01 - 0.125 * index, -0.1245, 0.98 + height / 2.0), material, axis="y",
                bevel=0.0))
    # Клавиатура с клавишами, коврик и мышь.
    model.add(box((0.44, 0.15, 0.014), (-0.20, 0.14, 0.757), "rubber", bevel=0.005))
    for row in range(5):
        for column in range(14):
            if row == 4 and 3 < column < 10:
                continue
            model.add(bar((0.024, 0.02, 0.006), (-0.397 + 0.0303 * column, 0.196 - 0.028 * row, 0.767), "panel", axis="z",
                    bevel=0.0))
    model.add(bar((0.176, 0.02, 0.006), (-0.2, 0.084, 0.767), "panel", axis="z", bevel=0.0))
    model.add(box((0.24, 0.20, 0.004), (0.13, 0.14, 0.752), "rubber", bevel=0.0015))
    model.add(ball(0.05, (0.11, 0.15, 0.757), "panel", scale=(0.62, 1.0, 0.42)))
    model.add(cyl(0.006, 0.006, (0.11, 0.176, 0.776), "grey", axis="x", vertices=10))
    model.extend(mug_parts((0.50, 0.16, 0.75), "yellow"))
    duck = (0.50, -0.17, 0.75)
    model.add(ball(0.06, (duck[0], duck[1], duck[2] + 0.05), "yellow", scale=(1.0, 1.25, 0.85)))
    model.add(ball(0.042, (duck[0], duck[1] + 0.045, duck[2] + 0.115), "yellow"))
    model.add(cone(0.02, 0.006, 0.04, (duck[0], duck[1] + 0.095, duck[2] + 0.11), "orange", axis="y", vertices=10))
    for sign in (-1.0, 1.0):
        model.add(ball(0.008, (duck[0] + sign * 0.022, duck[1] + 0.078, duck[2] + 0.128), "void"))
    for index, turn in enumerate((6.0, -12.0)):
        model.add(box((0.21, 0.30, 0.004), (-0.56, 0.12, 0.753 + 0.004 * index), "white", bevel=0.0,
                rot=(0.0, 0.0, math.radians(turn))))
    return model, None, [((1.50, 0.75, 0.75), (0.0, 0.0, 0.375)), ((0.68, 0.10, 0.57), (-0.20, -0.14, 1.035))]


def build_chair():
    """Офисное кресло: литая крестовина на роликах, газлифт, мягкое сиденье и спинка с кантом, подлокотники.
    Перёд (+Y) — куда смотрит сидящий."""
    model = Model("chair")
    model.add(cyl(0.05, 0.075, (0.0, 0.0, 0.105), "grey", bevel=0.012, vertices=16))
    for index in range(5):
        angle = 72.0 * index + 90.0
        x, y, _z = _polar(0.16, angle)
        model.add(box((0.27, 0.048, 0.03), (x, y, 0.094), "grey", bevel=0.011,
                rot=(0.0, math.radians(7.0), math.radians(angle))))
        x, y, _z = _polar(0.292, angle)
        _caster(model, x, y, angle + 55.0)
    model.add(cyl(0.034, 0.13, (0.0, 0.0, 0.19), "panel", bevel=0.006, vertices=16))
    model.add(cyl(0.022, 0.20, (0.0, 0.0, 0.30), "chrome", vertices=14))
    model.add(box((0.20, 0.25, 0.045), (0.0, 0.0, 0.405), "panel", bevel=0.012))
    model.add(tube([(0.08, 0.03, 0.40), (0.20, 0.04, 0.395), (0.265, 0.04, 0.385)], 0.007, "panel"))
    model.add(box((0.05, 0.03, 0.008), (0.285, 0.04, 0.382), "panel", bevel=0.003))
    # Сиденье: пластиковая чаша и подушка с кантом.
    model.add(box((0.47, 0.45, 0.04), (0.0, 0.02, 0.445), "panel", bevel=0.015))
    seat_size, seat_puff = (0.50, 0.48, 0.12), 0.72
    seat_center = (0.0, 0.02, 0.497)
    model.add(cushion(seat_size, seat_center, "violet", puff=seat_puff, dent=0.12))
    _piping(model, seat_size, seat_puff, Frame(seat_center, (0.0, 0.0, 0.0)))
    # Спинка: жёсткая раковина сзади, подушка спереди, стойка от механизма.
    lean = math.radians(8.0)
    back = Frame((0.0, -0.262, 0.90), (lean, 0.0, 0.0))
    model.add(box((0.45, 0.03, 0.49), back.at(0.0, -0.022, 0.0), "panel", bevel=0.012, rot=back.rot))
    back_size, back_puff = (0.47, 0.50, 0.10), 0.72
    back_rot = (lean - math.pi / 2.0, 0.0, 0.0)
    back_center = back.at(0.0, 0.022, 0.0)
    model.add(cushion(back_size, back_center, "violet", puff=back_puff, rot=back_rot))
    _piping(model, back_size, back_puff, Frame(back_center, back_rot))
    model.add(tube([(0.0, -0.09, 0.405), (0.0, -0.21, 0.41), (0.0, -0.268, 0.47), (0.0, -0.285, 0.62),
            (0.0, -0.298, 0.80)], 0.02, "panel"))
    for sign in (-1.0, 1.0):
        model.add(box((0.07, 0.05, 0.02), (sign * 0.245, -0.04, 0.452), "panel", bevel=0.008))
        model.add(box((0.03, 0.045, 0.20), (sign * 0.268, -0.04, 0.55), "panel", bevel=0.01))
        model.add(box((0.062, 0.27, 0.03), (sign * 0.272, 0.0, 0.662), "rubber", bevel=0.013))
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
    model.add(ball(0.008, (0.068, 0.070, 1.322), "void"))
    model.add(cyl(0.048, 0.30, (0.238, 0.04, 0.78), "grey", bevel=0.012, vertices=16))
    return model, None, [((0.42, 0.42, 1.52), (0.0, 0.0, 0.76))]


def build_vending_machine():
    """Торговый автомат: утопленная витрина с полками и банками (одна застряла), панель оплаты, лоток выдачи."""
    model = Model("vending_machine")
    model.add(box((1.00, 0.10, 1.83), (0.0, -0.30, 0.985), "red", bevel=0.015))
    model.add(box((0.07, 0.70, 1.83), (0.465, 0.0, 0.985), "red", bevel=0.015))
    model.add(box((0.30, 0.70, 1.83), (-0.35, 0.0, 0.985), "red", bevel=0.015))
    model.add(box((1.00, 0.70, 0.22), (0.0, 0.0, 1.79), "red", bevel=0.015))
    model.add(box((1.00, 0.70, 0.49), (0.0, 0.0, 0.315), "red", bevel=0.015))
    # Цоколь утоплен, автомат стоит на регулируемых ножках.
    model.add(box((0.94, 0.64, 0.09), (0.0, 0.0, 0.047), "rubber", bevel=0.008))
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            model.add(cyl(0.032, 0.02, (sx * 0.43, sy * 0.29, 0.01), "grey", vertices=10))
    window_x, window_z = 0.115, 1.12
    model.add(box((0.64, 0.02, 1.14), (window_x, -0.24, window_z), "lamp_soft", bevel=0.0))
    for sign in (-1.0, 1.0):
        model.add(bar((0.012, 0.55, 1.14), (window_x + sign * 0.314, 0.05, window_z), "white", axis="z", bevel=0.0))
    cans = ("cyan", "yellow", "green", "orange", "violet", "white")
    for row in range(4):
        z = 0.58 + 0.285 * row
        model.add(box((0.616, 0.52, 0.024), (window_x, 0.02, z), "grey", bevel=0.004))
        model.add(bar((0.616, 0.008, 0.03), (window_x, 0.284, z + 0.002), "white", bevel=0.002))
        for column in range(4):
            x = window_x - 0.225 + 0.15 * column
            model.add(bar((0.05, 0.004, 0.018), (x, 0.29, z + 0.002), "yellow" if (row + column) % 2 else "cyan",
                    axis="y", bevel=0.0))
            if column:
                model.add(bar((0.004, 0.40, 0.05), (x - 0.075, 0.07, z + 0.037), "grey", axis="y", bevel=0.0))
            if row == 2 and column == 1:
                continue
            material = cans[(row * 3 + column) % len(cans)]
            for depth_index in range(2):
                y = 0.19 - 0.13 * depth_index
                model.add(cyl(0.05, 0.14, (x, y, z + 0.083), material, bevel=0.008, vertices=14))
                model.add(cyl(0.043, 0.006, (x, y, z + 0.155), "chrome", vertices=14))
    # Застрявшая банка.
    model.add(cyl(0.05, 0.14, (window_x - 0.05, 0.25, 1.02), "red", bevel=0.008, vertices=14,
            rot=(math.radians(20.0), math.radians(55.0), 0.0)))
    # Стекло утоплено в резиновый уплотнитель.
    model.add(bar((0.62, 0.006, 1.12), (window_x, 0.338, window_z), "glass", axis="y", bevel=0.0))
    outer = rounded_rect_points(0.69, 1.19, 0.035, center=(window_x, window_z))
    inner = rounded_rect_points(0.60, 1.10, 0.02, center=(window_x, window_z))
    model.add(ring_prism(outer, inner, 0.032, "rubber", plane="xz", offset=0.335, bevel=0.004))
    # Панель оплаты: экран, клавиши, монетоприёмник, купюроприёмник, картридер, возврат монет.
    panel_x, face = -0.35, 0.358
    model.add(box((0.25, 0.014, 0.84), (panel_x, 0.351, 1.21), "panel", bevel=0.004))
    model.add(box((0.19, 0.006, 0.11), (panel_x, face + 0.002, 1.52), "screen", bevel=0.002))
    for row in range(4):
        for column in range(3):
            material = "green" if (row, column) == (3, 2) else ("red" if (row, column) == (3, 0) else "white")
            model.add(box((0.046, 0.012, 0.038), (panel_x - 0.056 + 0.056 * column, face + 0.004, 1.395 - 0.048 * row),
                    material, bevel=0.004))
    model.add(box((0.075, 0.008, 0.11), (panel_x - 0.07, face + 0.003, 1.13), "chrome", bevel=0.003))
    model.add(bar((0.008, 0.004, 0.05), (panel_x - 0.07, face + 0.008, 1.135), "rubber", axis="y", bevel=0.0))
    model.add(box((0.12, 0.022, 0.075), (panel_x + 0.045, face + 0.008, 1.13), "rubber", bevel=0.006))
    model.add(bar((0.09, 0.004, 0.008), (panel_x + 0.045, face + 0.02, 1.13), "glow_green", axis="y", bevel=0.0))
    model.add(box((0.10, 0.03, 0.13), (panel_x, face + 0.012, 0.985), "line", bevel=0.008))
    model.add(bar((0.07, 0.004, 0.006), (panel_x, face + 0.028, 0.955), "rubber", axis="y", bevel=0.0))
    model.add(box((0.06, 0.004, 0.04), (panel_x, face + 0.028, 1.01), "screen", bevel=0.0015))
    model.add(box((0.11, 0.012, 0.085), (panel_x, face, 0.86), "rubber", bevel=0.004))
    model.add(bar((0.11, 0.016, 0.012), (panel_x, face + 0.004, 0.822), "chrome", bevel=0.004))
    model.add(cyl(0.016, 0.012, (0.467, 0.352, 1.0), "chrome", axis="y", bevel=0.003, vertices=12))
    for z in (0.42, 0.95, 1.5):
        model.add(cyl(0.012, 0.09, (0.494, 0.345, z), "grey", vertices=8))
    # Лоток выдачи с качающейся заслонкой.
    model.add(box((0.60, 0.02, 0.25), (window_x, 0.346, 0.32), "rubber", bevel=0.006))
    model.add(box((0.52, 0.012, 0.17), (window_x, 0.356, 0.30), "grey", bevel=0.004, rot=(math.radians(-7.0), 0.0, 0.0)))
    model.add(bar((0.30, 0.008, 0.03), (window_x, 0.372, 0.355), "yellow", bevel=0.003))
    model.add(cyl(0.04, 0.03, (panel_x, 0.352, 0.40), "glow_green", axis="y", bevel=0.008, vertices=16))
    # Светящаяся вывеска в рамке, решётки охлаждения на боках.
    model.add(box((0.90, 0.03, 0.12), (0.0, 0.35, 1.795), "glow_yellow", bevel=0.01))
    outer = rounded_rect_points(0.95, 0.17, 0.03, center=(0.0, 1.795))
    inner = rounded_rect_points(0.89, 0.11, 0.012, center=(0.0, 1.795))
    model.add(ring_prism(outer, inner, 0.022, "panel", plane="xz", offset=0.348, bevel=0.004))
    for sign in (-1.0, 1.0):
        for index in range(7):
            model.add(bar((0.008, 0.36, 0.014), (sign * 0.5, 0.0, 0.16 + 0.036 * index), "rubber", axis="y", bevel=0.0))
        for z in (0.62, 1.74):
            for y in (-0.3, 0.3):
                model.add(bolt((sign * 0.501, y, z), axis="x", radius=0.009))
    return model, None, [((1.04, 0.74, 1.90), (0.0, 0.0, 0.95))]


def _leaf(base, yaw_deg, pitch_deg, length, width, droop_deg=55.0, fold=0.22, rows=9):
    """Лист фикуса: овальная пластина вдоль дуги от точки base. yaw — куда смотрит, pitch — подъём у черенка,
    droop — на сколько градусов лист клонится к кончику, fold — насколько он сложен вдоль жилки."""
    yaw = math.radians(yaw_deg)
    forward = (math.sin(yaw), -math.cos(yaw))
    side = (math.cos(yaw), math.sin(yaw))
    thickness = 0.004
    along, height = 0.0, 0.0
    step = length / rows
    top, bottom = [], []
    for i in range(rows + 1):
        t = i / rows
        angle = math.radians(pitch_deg - droop_deg * t * t)
        if i:
            middle = math.radians(pitch_deg - droop_deg * (t - 0.5 / rows) ** 2)
            along += step * math.cos(middle)
            height += step * math.sin(middle)
        half_width = max(width * 0.5 * math.sin(math.pi * t ** 0.7) ** 0.75, 0.005)
        normal = (-math.sin(angle), math.cos(angle))
        row_top, row_bottom = [], []
        for s in (-1.0, -0.55, 0.0, 0.55, 1.0):
            # Края приподняты над жилкой и чуть волнятся.
            lift = fold * abs(s) * half_width + 0.004 * math.sin(t * 9.0 + s * 2.0 + yaw)
            for offset, row in ((lift, row_top), (lift - thickness, row_bottom)):
                row.append((base[0] + forward[0] * (along + normal[0] * offset) + side[0] * s * half_width,
                        base[1] + forward[1] * (along + normal[0] * offset) + side[1] * s * half_width,
                        base[2] + height + normal[1] * offset))
        top.append(row_top)
        bottom.append(row_bottom)
    return shell(top, bottom, "leaf")


def build_plant():
    """Фикус в керамическом горшке. Один стебель заканчивается глазом и присматривает за офисом."""
    model = Model("plant")
    model.add(lathe([(0.0, 0.0), (0.235, 0.0), (0.25, 0.012), (0.25, 0.03), (0.20, 0.035), (0.0, 0.035)], (0.0, 0.0, 0.0),
            "white", bevel=0.004))
    model.add(lathe([(0.0, 0.03), (0.17, 0.03), (0.225, 0.33), (0.255, 0.345), (0.262, 0.385), (0.245, 0.405),
            (0.225, 0.395), (0.215, 0.36), (0.0, 0.36)], (0.0, 0.0, 0.0), "white", bevel=0.006))
    model.add(cyl(0.264, 0.03, (0.0, 0.0, 0.365), "orange", bevel=0.008))
    model.add(cyl(0.222, 0.02, (0.0, 0.0, 0.372), "rubber"))
    # Ствол с лёгким изгибом и листья по спирали: нижние крупные и поникшие, верхние мельче и смотрят вверх.
    trunk = [(0.0, 0.0, 0.37), (0.015, -0.01, 0.55), (-0.01, 0.01, 0.75), (0.01, 0.0, 0.93), (0.0, -0.005, 1.02)]
    model.add(tube(trunk, 0.014, "leaf"))
    leaves = 17
    for index in range(leaves):
        t = index / (leaves - 1)
        height = 0.45 + 0.54 * t
        yaw_deg = 137.5 * index + 20.0
        yaw = math.radians(yaw_deg)
        centre = (0.012 * math.sin(height * 9.0), 0.0, height)
        reach = 0.07 - 0.03 * t
        base = (centre[0] + math.sin(yaw) * reach, centre[1] - math.cos(yaw) * reach, height + 0.03)
        model.add(tube([centre, ((centre[0] + base[0]) / 2.0, (centre[1] + base[1]) / 2.0, height + 0.022), base], 0.006,
                "leaf", steps=2))
        model.add(_leaf(base, yaw_deg, 14.0 + 52.0 * t, 0.42 - 0.17 * t, 0.21 - 0.08 * t, droop_deg=66.0 - 34.0 * t))
    model.add(cone(0.012, 0.002, 0.09, (0.0, -0.005, 1.065), "red", vertices=8))
    # Стебель с глазом.
    eye = (0.12, 0.21, 1.10)
    model.add(tube([(0.03, 0.03, 0.37), (-0.05, 0.11, 0.72), (0.05, 0.17, 0.98), eye], 0.016, "leaf"))
    model.add(ball(0.075, eye, "white"))
    model.add(ball(0.04, (eye[0] + 0.012, eye[1] + 0.045, eye[2] - 0.006), "cyan"))
    model.add(ball(0.022, (eye[0] + 0.017, eye[1] + 0.066, eye[2] - 0.009), "void"))
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
    model.add(box((0.90, 0.05, 0.50), (0.0, 0.0, center_z), "void", bevel=0.0))
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
        model.add(ball(0.014, (sign * 0.06 - 0.115, 0.042, center_z + 0.005), "void"))
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


def _blanket(material, x0, x1, half_y, top_z, lumps=(), hang=0.14, seed=1.0, columns=30, rows=24):
    """Одеяло на матрасе от x0 до x1: мелкие складки, бугры lumps = [(x, y, радиус_x, радиус_y, высота)],
    по бокам свисает на hang с волнистым краем, у изголовья (x0) подвёрнуто валиком."""
    thickness = 0.012
    flat = 0.76
    top, bottom = [], []
    for j in range(rows + 1):
        v = -1.0 + 2.0 * j / rows
        side = 1.0 if v >= 0.0 else -1.0
        drape = max((abs(v) - flat) / (1.0 - flat), 0.0)
        row_top, row_bottom = [], []
        for i in range(columns + 1):
            x = x0 + (x1 - x0) * i / columns
            if drape > 0.0:
                y = side * (half_y + 0.02 * math.sin(drape * math.pi / 2.0) + 0.012 * drape * math.sin(x * 29.0 + seed))
            else:
                y = v / flat * half_y
            z = top_z
            for cx, cy, rx, ry, lump in lumps:
                z += lump * math.exp(-(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2))
            wrinkles = (0.006 * math.sin(17.0 * x + 9.0 * y + seed) + 0.004 * math.sin(-11.0 * x + 23.0 * y + 2.0 * seed)
                    + 0.003 * math.sin(37.0 * x + 5.0 * y + 3.0 * seed))
            z += wrinkles * (1.0 - 0.6 * drape) + 0.014 * math.exp(-((x - x0 - 0.035) / 0.03) ** 2)
            # Скруглённый перегиб через край матраса и волнистый подол.
            z -= hang * drape ** 1.4 * (1.0 + 0.10 * math.sin(x * 21.0 + seed * 1.7))
            inward = min(drape * 2.5, 1.0)
            row_top.append((x, y, z))
            row_bottom.append((x, y - side * thickness * inward, z - thickness * (1.0 - inward)))
        top.append(row_top)
        bottom.append(row_bottom)
    return shell(top, bottom, material)


def build_bunk():
    """Двухъярусная койка: внизу кто-то спит под одеялом, на полу тапочки."""
    model = Model("bunk")
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            model.add(bar((0.07, 0.07, 1.73), (sx * 0.985, sy * 0.425, 0.885), "line", axis="z", bevel=0.012))
            model.add(cyl(0.045, 0.022, (sx * 0.985, sy * 0.425, 0.011), "rubber", vertices=12))
            model.add(box((0.08, 0.08, 0.012), (sx * 0.985, sy * 0.425, 1.756), "rubber", bevel=0.004))
            for z in (0.34, 1.16):
                model.add(bolt((sx * 1.022, sy * 0.425, z), axis="x", radius=0.011))
    for z in (0.34, 1.16):
        model.add(box((1.96, 0.86, 0.10), (0.0, 0.0, z), "line", bevel=0.012))
        model.add(box((1.84, 0.80, 0.14), (0.0, 0.0, z + 0.11), "fabric_white", bevel=0.045, segments=3))
        for edge_z in (z + 0.165, z + 0.055):
            model.add(tube([(sx * 0.9, sy * 0.38, edge_z) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1), (1, 1))],
                    0.006, "fabric_white", smooth=False))
    model.add(cushion((0.46, 0.64, 0.17), (-0.64, 0.0, 0.34 + 0.235), "fabric_yellow", puff=0.85, dent=0.3, steps=14,
            firm=False))
    model.add(cushion((0.46, 0.64, 0.17), (-0.66, 0.02, 1.16 + 0.235), "fabric_yellow", puff=0.85, dent=0.1, steps=14,
            rot=(0.0, 0.0, math.radians(6.0)), firm=False))
    sleeper = [(-0.24, 0.0, 0.12, 0.13, 0.17), (0.0, 0.02, 0.22, 0.2, 0.25), (0.3, 0.03, 0.22, 0.17, 0.2),
            (0.58, 0.01, 0.24, 0.13, 0.13), (0.81, 0.0, 0.06, 0.1, 0.17)]
    model.add(_blanket("fabric_cyan", -0.36, 0.905, 0.415, 0.534, lumps=sleeper, seed=1.0))
    model.add(_blanket("fabric_violet", -0.30, 0.905, 0.415, 1.354, lumps=[(0.35, -0.1, 0.3, 0.2, 0.03)], seed=4.0))
    for sy in (-1.0, 1.0):
        model.add(bar((1.92, 0.035, 0.05), (0.0, sy * 0.425, 1.53), "line", bevel=0.012))
    # Лестница справа спереди.
    for x in (0.52, 0.86):
        model.add(bar((0.04, 0.04, 1.30), (x, 0.47, 0.65), "yellow", axis="z", bevel=0.01))
        model.add(cyl(0.026, 0.016, (x, 0.47, 0.008), "rubber", vertices=10))
    for index in range(4):
        model.add(cyl(0.016, 0.34, (0.69, 0.47, 0.22 + 0.30 * index), "grey", axis="x", vertices=10))
    for index, x in enumerate((-0.30, -0.12)):
        model.add(box((0.11, 0.24, 0.07), (x, 0.62, 0.035), "red", bevel=0.03,
                rot=(0.0, 0.0, math.radians(8.0 - 20.0 * index))))
        model.add(ball(0.035, (x + 0.01 - 0.03 * index, 0.72, 0.085), "white"))
    return model, None, [((2.05, 0.93, 1.75), (0.0, 0.0, 0.875))]


def build_coffee_machine():
    """Кофейный уголок: тумба, рожковая кофемашина с чашкой и башня немытых кружек."""
    model = Model("coffee_machine")
    model.add(box((0.70, 0.50, 0.08), (0.0, 0.0, 0.04), "rubber", bevel=0.008))
    model.add(box((0.70, 0.50, 0.78), (0.0, 0.0, 0.47), "line", bevel=0.012))
    model.add(box((0.76, 0.56, 0.035), (0.0, 0.0, 0.8775), "laminate", bevel=0.005))
    for sign in (-1.0, 1.0):
        model.add(box((0.325, 0.018, 0.66), (sign * 0.168, 0.254, 0.47), "mid", bevel=0.006))
        model.add(bar((0.012, 0.012, 0.16), (sign * 0.035, 0.282, 0.56), "chrome", axis="z", bevel=0.004))
        for z in (0.50, 0.62):
            model.add(cyl(0.005, 0.02, (sign * 0.035, 0.27, z), "chrome", axis="y", vertices=8))
    top = 0.895
    machine_x = -0.13
    model.add(box((0.36, 0.30, 0.10), (machine_x, -0.06, top + 0.055), "red", bevel=0.014))
    model.add(box((0.36, 0.14, 0.44), (machine_x, -0.14, top + 0.225), "red", bevel=0.014))
    model.add(box((0.36, 0.32, 0.14), (machine_x, -0.05, top + 0.425), "red", bevel=0.02))
    for sx in (-1.0, 1.0):
        for sy in (-0.18, 0.06):
            model.add(cyl(0.018, 0.012, (machine_x + sx * 0.15, sy, top + 0.004), "rubber", vertices=10))
    # Панель: экран, кнопки, манометр.
    model.add(box((0.30, 0.012, 0.085), (machine_x, 0.108, top + 0.435), "chrome", bevel=0.004))
    model.add(box((0.12, 0.006, 0.05), (machine_x - 0.07, 0.115, top + 0.435), "screen", bevel=0.002))
    for index, material in enumerate(("white", "white", "glow_green")):
        model.add(cyl(0.013, 0.012, (machine_x + 0.03 + 0.04 * index, 0.118, top + 0.435), material, axis="y", bevel=0.003,
                vertices=12))
    # Группа с рожком, поддон с решёткой, паровой кран.
    model.add(cyl(0.034, 0.03, (machine_x - 0.02, 0.02, top + 0.34), "chrome", bevel=0.005, vertices=16))
    model.add(cyl(0.038, 0.022, (machine_x - 0.02, 0.02, top + 0.315), "chrome", bevel=0.004, vertices=16))
    model.add(tube([(machine_x - 0.02, 0.05, top + 0.315), (machine_x - 0.02, 0.12, top + 0.31),
            (machine_x - 0.02, 0.19, top + 0.30)], 0.011, "rubber", smooth=False))
    model.add(box((0.26, 0.21, 0.014), (machine_x, 0.0, top + 0.112), "chrome", bevel=0.004))
    for index in range(7):
        model.add(bar((0.24, 0.006, 0.006), (machine_x, -0.078 + 0.026 * index, top + 0.121), "grey", bevel=0.0))
    model.add(tube([(machine_x + 0.13, -0.03, top + 0.36), (machine_x + 0.15, 0.04, top + 0.33),
            (machine_x + 0.15, 0.06, top + 0.20)], 0.006, "chrome"))
    model.add(cyl(0.012, 0.03, (machine_x + 0.15, 0.06, top + 0.20), "rubber", vertices=10))
    model.extend(mug_parts((machine_x - 0.02, 0.02, top + 0.124), "white"))
    # Перильца для чашек наверху.
    rail = [(machine_x + sx * 0.16, -0.05 + sy * 0.14, top + 0.515) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1), (1, 1))]
    model.add(tube(rail, 0.005, "chrome", smooth=False))
    for point in rail[:4]:
        model.add(cyl(0.004, 0.022, (point[0], point[1], top + 0.505), "chrome", vertices=6))
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
