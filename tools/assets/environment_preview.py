"""Собирает демонстрационную сцену tests/visual/kit_preview.tscn из префабов набора и реквизита.

Обычный Python без Blender, запуск из корня репозитория:
    python3 tools/assets/environment_preview.py

План (вид сверху, клетки 4 x 4 м, север — это -Z):
    комната А (офис, 8 x 8 м) — дверь — коридор (4 x 8 м) — дверь — комната Б (реактор, 8 x 8 м).
Рецепт света описан в tests/visual/kit_preview.gd; здесь он просто записан узлами.
"""

import math
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTPUT = os.path.join(REPO_ROOT, "tests", "visual", "kit_preview.tscn")

GRID = 4.0
HALF = GRID / 2.0
# На сколько лицевая поверхность стены (светлые панели) отстоит от линии сетки.
WALL_SURFACE = 0.13

# Повороты вокруг Y (градусы): куда смотрит перёд модели (-Z без поворота).
NORTH = 0.0
WEST = 90.0
SOUTH = 180.0
EAST = -90.0

ROOM_A = [(0, 0), (1, 0), (0, 1), (1, 1)]
CORRIDOR = [(2, 0), (3, 0)]
ROOM_B = [(4, 0), (5, 0), (4, 1), (5, 1)]

# Плитки пола с полосатой кромкой: клетка -> поворот (кромка смотрит на дверь).
HAZARD_FLOORS = {(2, 0): WEST, (3, 0): EAST}
# Клетки без потолочного светильника (обычная плитка потолка).
PLAIN_CEILINGS = [(4, 1), (5, 0)]

# Стены: (деталь, x, z, поворот). Стены вдоль X — без поворота, вдоль Z — 90°.
WALLS = [
    # комната А
    ("wall_window", 0, -2, 0), ("wall_window", 4, -2, 0),
    ("wall", 0, 6, 0), ("wall", 4, 6, 0),
    ("wall", -2, 0, 90), ("wall", -2, 4, 90),
    ("wall_doorway", 6, 0, 90), ("wall", 6, 4, 90),
    # коридор
    ("wall_window", 8, -2, 0), ("wall", 12, -2, 0),
    ("wall", 8, 2, 0), ("wall", 12, 2, 0),
    # комната Б
    ("wall_doorway", 14, 0, 90), ("wall", 14, 4, 90),
    ("wall", 16, -2, 0), ("wall_window", 20, -2, 0),
    ("wall", 22, 0, 90), ("wall", 22, 4, 90),
    ("wall", 16, 6, 0), ("wall", 20, 6, 0),
]
PILLARS = [
    (-2, -2), (2, -2), (6, -2), (-2, 2), (6, 2), (-2, 6), (2, 6), (6, 6),
    (10, -2), (10, 2), (14, -2), (14, 2),
    (18, -2), (22, -2), (22, 2), (14, 6), (18, 6), (22, 6),
]
EXTRA_KIT = [
    ("corridor_arch", 10, 0, 90),
    ("railing", 18, 3.7, 0),
]

# Реквизит с префабами (scenes/maps/props): (имя, x, y, z, поворот).
DECOR = [
    # комната А: офис и переговорная
    ("chair", 2.0, 0, 0.05, SOUTH), ("chair", 3.9, 0, 1.5, WEST), ("chair", 0.1, 0, 1.5, EAST),
    ("chair", 3.4, 0, 3.75, 35.0), ("chair", 0.6, 0, 3.75, -35.0),
    ("desk", -0.9, 0, -1.2, SOUTH), ("chair", -0.9, 0, -0.45, 20.0),
    ("whiteboard", -2 + WALL_SURFACE, 0, 3.4, EAST),
    ("plant", -1.35, 0, 5.35, NORTH), ("locker", 0.2, 0, 5.5, NORTH),
    ("water_cooler", 1.45, 0, 5.45, NORTH),
    ("vending_machine", 5.45, 0, 4.4, WEST), ("coffee_machine", 5.45, 0, 3.0, WEST),
    ("trash_bin", 5.45, 0, 5.45, WEST), ("floor_lamp", 5.35, 0, -1.35, NORTH),
    ("plant", 3.1, 0, -1.4, NORTH),
    # коридор
    ("warning_sign", 7.3, 0, 0.9, 25.0), ("pipes", 12, 0, -2 + WALL_SURFACE, SOUTH),
    ("vent_grate", 8, 0, 2 - WALL_SURFACE, NORTH), ("trash_bin", 13.3, 0, 1.4, NORTH),
    ("plant", 6.75, 0, -1.3, NORTH),
    # комната Б: реактор
    ("server_rack", 14.75, 0, 5.4, NORTH), ("server_rack", 15.6, 0, 5.4, NORTH),
    ("crate_large", 21.2, 0, 5.2, 8.0), ("crate_small", 20.2, 0, 5.4, -15.0),
    ("crate_small", 21.25, 1.0, 5.15, 30.0),
    ("barrel", 21.4, 0, 3.9, NORTH), ("barrel", 20.75, 0, 4.25, 40.0),
    ("pipes", 22 - WALL_SURFACE, 0, 0, WEST), ("vent_grate", 14 + WALL_SURFACE, 0, 4, EAST),
    ("bunk", 16.6, 0, -1.3, SOUTH), ("locker", 14.6, 0, -1.5, SOUTH),
    ("floor_lamp", 21.4, 0, -1.4, NORTH),
]

# Игровой реквизит: модели .glb напрямую (префабы для них делает игровой код).
GAMEPLAY = [
    ("meeting_table", 2, 0, 2, NORTH), ("emergency_button", 2, 0, 2, SOUTH),
    ("task_keypad", -1.45, 0, 1.6, EAST),
    ("weapon_pedestal", 4.6, 0, -1.3, SOUTH),
    ("reactor_core", 18, 0, 1.6, NORTH), ("reactor_panel", 18, 0, 4.6, SOUTH),
    ("canister_rack", 19.9, 0, -1.45, SOUTH),
    ("canister_dock", 21.35, 0, 2.2, WEST), ("canister", 20.6, 0, 1.3, 30.0),
    ("task_calibrator", 14.75, 0, 2.6, EAST),
    ("task_panel", 17.2, 1.3, 6 - WALL_SURFACE, NORTH),
]

# Свет: (имя, тип, позиция, параметры). Рецепт — в tests/visual/kit_preview.gd.
LIGHTS = [
    ("RoomAKey", "OmniLight3D", (2, 2.7, 2), dict(light_color="Color(1, 0.95, 0.86, 1)", light_energy=1.5,
            omni_range=9.5, omni_attenuation=1.0, shadow_enabled="true", shadow_bias=0.06)),
    ("CorridorKey", "OmniLight3D", (10, 2.6, 0), dict(light_color="Color(0.86, 0.93, 1, 1)", light_energy=1.2,
            omni_range=7.5, omni_attenuation=1.0, shadow_enabled="true", shadow_bias=0.06)),
    ("RoomBKey", "OmniLight3D", (18, 2.95, 3.6), dict(light_color="Color(0.86, 0.93, 1, 1)", light_energy=1.2,
            omni_range=9.0, omni_attenuation=1.0, shadow_enabled="true", shadow_bias=0.06)),
    ("ReactorGlow", "OmniLight3D", (18, 1.35, 1.6), dict(light_color="Color(1, 0.62, 0.2, 1)", light_energy=3.0,
            omni_range=3.5, omni_attenuation=0.8)),
]


def number(value):
    text = ("%.4f" % value).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def transform(x, y, z, yaw_deg=0.0):
    angle = math.radians(yaw_deg)
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    values = (cos_a, 0.0, sin_a, 0.0, 1.0, 0.0, -sin_a, 0.0, cos_a, x, y, z)
    return "Transform3D(%s)" % ", ".join(number(value) for value in values)


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

    def node(self, name, kind, parent, properties=None):
        line = "[node name=\"%s\" type=\"%s\"%s]" % (name, kind, "" if parent is None else " parent=\"%s\"" % parent)
        self.body.append(line)
        for key, value in (properties or {}).items():
            self.body.append("%s = %s" % (key, value if isinstance(value, str) else number(value)))
        self.body.append("")

    def instance(self, parent, base_name, path, x, y, z, yaw_deg):
        if not os.path.exists(os.path.join(REPO_ROOT, path.replace("res://", ""))):
            print("ПРОПУЩЕНО: нет файла", path)
            return
        name = self.unique_name(base_name)
        self.body.append("[node name=\"%s\" parent=\"%s\" instance=%s]" % (name, parent,
                self.resource("PackedScene", path)))
        self.body.append("transform = %s" % transform(x, y, z, yaw_deg))
        self.body.append("")

    def text(self):
        return "\n".join(["[gd_scene format=3]", ""] + self.header + [""] + self.body)


def pascal(name):
    return "".join(part.capitalize() for part in name.split("_"))


def kit(name):
    return "res://scenes/maps/kit/%s.tscn" % name


def main():
    scene = SceneWriter()
    script = scene.resource("Script", "res://tests/visual/kit_preview.gd")
    environment = scene.resource("Environment", "res://resources/maps/station_environment.tres")
    scene.node("KitPreview", "Node3D", None, {"script": script})
    scene.node("WorldEnvironment", "WorldEnvironment", ".", {"environment": environment})

    scene.node("Structure", "Node3D", ".")
    for cell in ROOM_A + CORRIDOR + ROOM_B:
        x, z = cell[0] * GRID, cell[1] * GRID
        if cell in HAZARD_FLOORS:
            scene.instance("Structure", "FloorHazard", kit("floor_hazard"), x, 0, z, HAZARD_FLOORS[cell])
        else:
            scene.instance("Structure", "Floor", kit("floor"), x, 0, z, 0)
    for name, x, z, yaw in WALLS + EXTRA_KIT:
        scene.instance("Structure", pascal(name), kit(name), x, 0, z, yaw)
    for x, z in PILLARS:
        scene.instance("Structure", "Pillar", kit("pillar"), x, 0, z, 0)

    scene.node("Ceilings", "Node3D", ".")
    for cell in ROOM_A + CORRIDOR + ROOM_B:
        name = "ceiling" if cell in PLAIN_CEILINGS else "ceiling_light"
        scene.instance("Ceilings", pascal(name), kit(name), cell[0] * GRID, 0, cell[1] * GRID, 0)

    scene.node("Decor", "Node3D", ".")
    for name, x, y, z, yaw in DECOR:
        scene.instance("Decor", pascal(name), "res://scenes/maps/props/%s.tscn" % name, x, y, z, yaw)

    scene.node("Gameplay", "Node3D", ".")
    for name, x, y, z, yaw in GAMEPLAY:
        scene.instance("Gameplay", pascal(name), "res://assets/models/props/%s.glb" % name, x, y, z, yaw)

    scene.node("Lights", "Node3D", ".")
    for name, kind, position, properties in LIGHTS:
        values = {"transform": transform(*position)}
        values.update(properties)
        scene.node(name, kind, "Lights", values)

    scene.node("Camera", "Camera3D", ".", {"transform": transform(2, 1.6, 4.6), "fov": 75.0})

    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(scene.text())
    print("WROTE", OUTPUT)


if __name__ == "__main__":
    main()
