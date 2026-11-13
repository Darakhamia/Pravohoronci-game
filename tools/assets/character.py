"""Генератор персонажа «crewmate»: пухлая виниловая игрушка — скафандр пополам с офисным работником.

Запуск из корня репозитория:
    blender -b --python tools/assets/character.py
    blender -b --python tools/assets/character.py -- <папка для .glb>

Пишет два файла (по умолчанию в assets/models/characters/):
    crewmate.glb      тело со скелетом (17 костей профиля Godot Humanoid), жёсткий скиннинг по кускам;
    crewmate_arm.glb  предплечье с варежкой для вида от первого лица: узлы ArmRight и ArmLeft,
                      начало координат — в точке хвата, предмет в руке смотрит по +Y (в Godot -Z).

Меши тела: HeadPiece, FacePlate, FaceEyes, TorsoPiece, PelvisPiece, ArmLeft, ArmRight, LegLeft,
LegRight. Каждая конечность — один меш (прячется целиком); его же геометрию игра показывает без
скелета как отлетевшую деталь. Материалы: Suit (перекрашивается под игрока), Trim, FacePlate,
Light, Glow. Размеры ниже — метрики, на которые опираются хитбоксы; меняешь их — предупреди
геймплей.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from mathutils import Matrix, Vector

import character_shapes as shapes
import common

DEFAULT_OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models",
        "characters")
BODY_FILE = "crewmate.glb"
ARM_FILE = "crewmate_arm.glb"

# --- Палитра (sRGB) ---
SUIT_COLOR = "ff9f1c"       # цвет по умолчанию; в игре Suit перекрашивается под игрока
TRIM_COLOR = "20243f"       # перчатки, ботинки, ремень, суставы
VISOR_COLOR = "0e1020"
LIGHT_COLOR = "f2f3f7"      # воротник, манишка, манжеты, подошвы, ранец
GLOW_COLOR = "3ddbd9"       # глаза, лампа ранца, антенна

# --- Метрики (метры; Z — вверх, +Y — перёд, +X — правая рука персонажа) ---
HEAD_CENTER_Z = 1.62
HEAD_SIZE = (0.38, 0.35, 0.36)
HEAD_BEVEL = 0.11
NECK_Z = 1.445               # низ головы = верх торса
TORSO_BOTTOM_Z = 1.055
TORSO_SIZE = (0.44, 0.28)
PELVIS_BOTTOM_Z = 0.895
PELVIS_SIZE = (0.40, 0.25)
SHOULDER_X = 0.30
SHOULDER_Z = 1.42
ELBOW_Z = 1.16
WRIST_Z = 0.925
HAND_TIP_Z = 0.79
ARM_RADIUS = 0.068
HIP_X = 0.11
HIP_Z = 0.92
KNEE_Z = 0.48
ANKLE_Z = 0.09
LEG_RADIUS = 0.089
FACE_SIZE = 0.24             # лицевая пластина FacePlate: квадрат со скруглёнными углами
FACE_CENTER_Z = 1.615
CREST_WIDTH = 0.07           # гребень-полоса на шлеме
CREST_RISE = 0.007           # насколько он выступает над шлемом
CREST_FROM = 0.142           # от какой высоты над центром головы начинается
# Точка хвата в ладони (для правой руки; у левой X с минусом). От неё же считает игра.
GRIP_Z = 0.855

LIMB_SEGMENTS = 12           # граней по окружности у рукавов, штанин и суставов

# Запястье руки от первого лица согнуто: предплечье уходит вниз и наружу, к углу экрана.
VIEW_ARM_PITCH_DEG = 56.0
VIEW_ARM_YAW_DEG = 14.0
VIEW_ARM_LENGTH = 0.42


def make_materials():
    return {
        "suit": common.material("Suit", SUIT_COLOR, roughness=0.42),
        "trim": common.material("Trim", TRIM_COLOR, roughness=0.5),
        "face": common.material("FacePlate", VISOR_COLOR, roughness=0.12, metallic=0.2,
                emission=GLOW_COLOR, emission_strength=0.025),
        "light": common.material("Light", LIGHT_COLOR, roughness=0.5),
        "glow": common.material("Glow", GLOW_COLOR, roughness=0.3, emission=GLOW_COLOR, emission_strength=2.6),
    }


def x_cylinder(name, radius, depth, location, mat, bevel=0.0, vertices=20, segments=2):
    """Цилиндр, лежащий вдоль оси X."""
    obj = common.cylinder(name, radius, depth, location=location, vertices=vertices, bevel=bevel, mat=mat,
            segments=segments, rotation=(0.0, math.radians(90.0), 0.0))
    return shapes.freeze(obj)


def z_cylinder(name, radius, depth, location, mat, bevel=0.0, vertices=20, segments=2):
    obj = common.cylinder(name, radius, depth, location=location, vertices=vertices, bevel=bevel, mat=mat,
            segments=segments)
    return shapes.freeze(obj)


def joint_ball(name, radius, location, mat):
    """Шар-сустав: тело вращения с теми же сегментами, что у рукавов и штанин.
    (common.sphere здесь не годится ещё и потому, что порядок его граней меняется от запуска
    к запуску, и .glb перестаёт совпадать байт в байт.)"""
    return shapes.lathe(name, shapes.ball_profile(radius, location[2]), (location[0], location[1], 0.0),
            segments=LIMB_SEGMENTS, mat=mat)


# ---------------------------------------------------------------------------------------------
# Куски тела. Каждая функция возвращает список объектов одного жёсткого куска.
# ---------------------------------------------------------------------------------------------

def build_head(mats):
    parts = []
    parts.append(common.rounded_box("Helmet", HEAD_SIZE, (0.0, 0.0, HEAD_CENTER_Z), bevel=HEAD_BEVEL, segments=5,
            mat=mats["suit"]))
    # Рамка маски: тёмный ободок, из которого выступает лицевая пластина.
    front = HEAD_SIZE[1] * 0.5
    parts.append(shapes.extrude_profile("Bezel", shapes.rounded_rect(FACE_SIZE + 0.04, FACE_SIZE + 0.035, 0.07),
            0.07, (0.0, front - 0.022, FACE_CENTER_Z), bevel=0.008, segments=1, mat=mats["trim"]))
    # Наушники-шайбы по бокам и антенна на правой.
    for side in (-1.0, 1.0):
        ear_x = side * (HEAD_SIZE[0] * 0.5 + 0.004)
        parts.append(x_cylinder("EarCup", 0.07, 0.04, (ear_x, -0.005, HEAD_CENTER_Z - 0.005), mats["trim"],
                bevel=0.012, vertices=14, segments=1))
        parts.append(x_cylinder("EarCap", 0.038, 0.014, (ear_x + side * 0.022, -0.005, HEAD_CENTER_Z - 0.005),
                mats["light"], bevel=0.005, vertices=8, segments=1))
    antenna_x = HEAD_SIZE[0] * 0.5 + 0.012
    parts.append(z_cylinder("AntennaStalk", 0.007, 0.15, (antenna_x, -0.005, HEAD_CENTER_Z + 0.105),
            mats["trim"], vertices=6))
    parts.append(shapes.lathe("AntennaTip", shapes.ball_profile(0.018, HEAD_CENTER_Z + 0.185, 4),
            (antenna_x, -0.005, 0.0), segments=8, mat=mats["glow"]))
    # Гребень-полоса по макушке: читается сверху и сзади. Контур повторяет профиль шлема сбоку.
    outline = shapes.rounded_rect(HEAD_SIZE[1] + 2.0 * CREST_RISE, HEAD_SIZE[2] + 2.0 * CREST_RISE,
            HEAD_BEVEL + CREST_RISE, 6, (0.0, HEAD_CENTER_Z))
    crest = [point for point in outline if point[1] >= HEAD_CENTER_Z + CREST_FROM]
    parts.append(shapes.extrude_profile("Crest", crest, CREST_WIDTH, bevel=0.006, mat=mats["light"], plane="YZ"))
    return parts


def build_face(mats):
    """Лицевая пластина — отдельный меш с UV: позже на неё ляжет фото («бумажная маска»)."""
    front = HEAD_SIZE[1] * 0.5
    plate = shapes.extrude_profile("FacePlate", shapes.rounded_rect(FACE_SIZE, FACE_SIZE, 0.055, 5), 0.03,
            (0.0, front + 0.005, FACE_CENTER_Z), bevel=0.006, segments=1, mat=mats["face"])
    shapes.planar_uv(plate, (0.0, FACE_CENTER_Z), FACE_SIZE, FACE_SIZE)
    eyes = []
    for side in (-1.0, 1.0):
        eyes.append(shapes.extrude_profile("Eye", shapes.pill(0.038, 0.08, 4, (side * 0.054, FACE_CENTER_Z + 0.012)),
                0.008, (0.0, front + 0.021, 0.0), mat=mats["glow"]))
    return plate, common.join(eyes, "FaceEyes")


def build_torso(mats):
    parts = []
    height = NECK_Z - TORSO_BOTTOM_Z + 0.005
    body = common.rounded_box("Chest", (TORSO_SIZE[0], TORSO_SIZE[1], height),
            (0.0, 0.0, TORSO_BOTTOM_Z + height * 0.5), bevel=0.085, segments=3, mat=mats["suit"])
    shapes.taper(body, bottom_scale=(0.87, 0.9))
    parts.append(body)
    # Воротник-кольцо под шлемом.
    parts.append(z_cylinder("Collar", 0.146, 0.05, (0.0, 0.0, NECK_Z + 0.004), mats["light"], bevel=0.014,
            vertices=16, segments=1))
    # Гнёзда плечевых шарниров.
    for side in (-1.0, 1.0):
        parts.append(x_cylinder("ShoulderSocket", 0.052, 0.06, (side * 0.215, 0.0, SHOULDER_Z - 0.015),
                mats["trim"], bevel=0.01, vertices=10, segments=1))
    # Офисная манишка с галстуком поверх скафандра.
    front = TORSO_SIZE[1] * 0.5
    shirt = [(-0.1, 1.44), (-0.1, 1.385), (-0.016, 1.178), (0.0, 1.168), (0.016, 1.178), (0.1, 1.385), (0.1, 1.44)]
    parts.append(shapes.extrude_profile("Shirt", shirt, 0.04, (0.0, front - 0.008, 0.0), bevel=0.006,
            mat=mats["light"]))
    tie = [(-0.027, 1.432), (-0.019, 1.392), (-0.037, 1.262), (0.0, 1.208), (0.037, 1.262), (0.019, 1.392),
            (0.027, 1.432)]
    parts.append(shapes.extrude_profile("Tie", tie, 0.02, (0.0, front + 0.016, 0.0), bevel=0.005,
            mat=mats["trim"]))
    # Ранец с лампой и двумя соплами.
    back = -TORSO_SIZE[1] * 0.5
    parts.append(common.rounded_box("Backpack", (0.3, 0.12, 0.3), (0.0, back - 0.04, 1.268), bevel=0.04,
            segments=3, mat=mats["light"]))
    parts.append(shapes.extrude_profile("BackLamp", shapes.pill(0.13, 0.036, 3, (0.0, 1.33)), 0.012,
            (0.0, back - 0.101, 0.0), mat=mats["glow"]))
    parts.append(shapes.extrude_profile("BackVent", shapes.rounded_rect(0.15, 0.07, 0.015, 2, (0.0, 1.215)),
            0.012, (0.0, back - 0.101, 0.0), mat=mats["trim"]))
    for side in (-1.0, 1.0):
        parts.append(z_cylinder("Nozzle", 0.04, 0.05, (side * 0.08, back - 0.04, 1.108), mats["trim"],
                bevel=0.01, vertices=10, segments=1))
    return parts


def build_pelvis(mats):
    parts = []
    height = TORSO_BOTTOM_Z - PELVIS_BOTTOM_Z
    hips = common.rounded_box("HipBlock", (PELVIS_SIZE[0], PELVIS_SIZE[1], height),
            (0.0, 0.0, PELVIS_BOTTOM_Z + height * 0.5), bevel=0.06, segments=3, mat=mats["suit"])
    parts.append(hips)
    parts.append(common.rounded_box("Belt", (PELVIS_SIZE[0] + 0.012, PELVIS_SIZE[1] + 0.014, 0.05),
            (0.0, 0.0, TORSO_BOTTOM_Z - 0.004), bevel=0.014, segments=2, mat=mats["trim"]))
    parts.append(common.rounded_box("Buckle", (0.075, 0.03, 0.058), (0.0, PELVIS_SIZE[1] * 0.5 + 0.004,
            TORSO_BOTTOM_Z - 0.004), bevel=0.01, segments=1, mat=mats["light"]))
    return parts


def build_upper_arm(mats, x):
    """Рукав с круглым плечом: верх профиля — полусфера вокруг плечевого сустава."""
    r = ARM_RADIUS
    ball = r * 1.14
    return [
        shapes.lathe("Sleeve", [(0.0, ELBOW_Z + 0.004), (r * 0.72, ELBOW_Z + 0.008), (r * 0.95, ELBOW_Z + 0.03),
                (r * 1.02, SHOULDER_Z - 0.075), (ball, SHOULDER_Z - 0.02), (ball * 0.92, SHOULDER_Z + 0.03),
                (ball * 0.55, SHOULDER_Z + 0.064), (0.0, SHOULDER_Z + 0.076)], (x, 0.0, 0.0), segments=LIMB_SEGMENTS,
                mat=mats["suit"]),
        shapes.lathe("SleeveStripe", [(r * 0.98, SHOULDER_Z - 0.165), (r * 1.1, SHOULDER_Z - 0.16),
                (r * 1.1, SHOULDER_Z - 0.125), (r * 0.98, SHOULDER_Z - 0.12)], (x, 0.0, 0.0), segments=LIMB_SEGMENTS,
                mat=mats["light"], caps=False),
    ]


def build_lower_arm(mats, x, top_z=ELBOW_Z, with_elbow=True):
    """Предплечье с манжетой. top_z выше локтя — удлинённый рукав для вида от первого лица."""
    r = ARM_RADIUS
    parts = [
        shapes.lathe("Forearm", [(0.0, WRIST_Z - 0.01), (r * 1.12, WRIST_Z - 0.008), (r * 1.16, WRIST_Z + 0.03),
                (r * 0.94, top_z - 0.03), (r * 0.7, top_z - 0.004), (0.0, top_z)], (x, 0.0, 0.0),
                segments=LIMB_SEGMENTS, mat=mats["suit"]),
        shapes.lathe("Cuff", [(r * 1.05, WRIST_Z - 0.016), (r * 1.3, WRIST_Z - 0.01), (r * 1.32, WRIST_Z + 0.026),
                (r * 1.1, WRIST_Z + 0.034)], (x, 0.0, 0.0), segments=LIMB_SEGMENTS, mat=mats["light"], caps=False),
    ]
    if with_elbow:
        parts.append(joint_ball("ElbowBall", 0.061, (x, 0.0, ELBOW_Z), mats["trim"]))
    return parts


def build_hand(mats, x, side):
    """Варежка: кулак вокруг точки хвата и большой палец спереди с внутренней стороны."""
    height = WRIST_Z - HAND_TIP_Z + 0.014
    mitten = common.rounded_box("Mitten", (0.122, 0.138, height), (x, 0.004, HAND_TIP_Z + height * 0.5),
            bevel=0.05, segments=3, mat=mats["trim"])
    shapes.taper(mitten, bottom_scale=(0.9, 0.9), top_scale=(1.0, 1.0))
    thumb = shapes.lathe("Thumb", shapes.ball_profile(0.04, GRIP_Z + 0.02, 6), (x - side * 0.052, 0.056, 0.0),
            segments=8, mat=mats["trim"], squash=(0.68, 0.86))
    return [mitten, thumb]


def build_upper_leg(mats, x):
    """Штанина с круглым верхом: шар бедра спрятан в тазу и виден, только когда нога машет."""
    r = LEG_RADIUS
    return [
        shapes.lathe("Thigh", [(0.0, KNEE_Z + 0.006), (r * 0.74, KNEE_Z + 0.01), (r * 0.95, KNEE_Z + 0.04),
                (r * 1.02, HIP_Z - 0.05), (r * 0.98, HIP_Z + 0.02), (r * 0.7, HIP_Z + 0.065), (0.0, HIP_Z + 0.085)],
                (x, 0.0, 0.0), segments=LIMB_SEGMENTS, mat=mats["suit"]),
    ]


def build_lower_leg(mats, x):
    """Голень-клёш: расширяется к ботинку."""
    r = LEG_RADIUS
    return [
        joint_ball("KneeBall", 0.076, (x, 0.0, KNEE_Z), mats["trim"]),
        shapes.lathe("Shin", [(0.0, ANKLE_Z + 0.01), (r * 1.1, ANKLE_Z + 0.012), (r * 1.12, ANKLE_Z + 0.05),
                (r * 0.93, KNEE_Z - 0.05), (r * 0.74, KNEE_Z - 0.01), (0.0, KNEE_Z - 0.004)], (x, 0.0, 0.0),
                segments=LIMB_SEGMENTS, mat=mats["suit"]),
    ]


def build_foot(mats, x):
    """Луноход: пухлый ботинок на светлой подошве."""
    boot = common.rounded_box("Boot", (0.19, 0.29, 0.125), (x, 0.048, 0.0875), bevel=0.05, segments=3,
            mat=mats["trim"])
    shapes.taper(boot, bottom_scale=(1.0, 1.0), top_scale=(0.9, 0.84))
    sole = shapes.extrude_profile("Sole", shapes.rounded_rect(0.196, 0.296, 0.07, 4, (x, 0.048)), 0.04,
            mat=mats["light"], plane="XY")
    shapes.move(sole, (0.0, 0.0, 0.02))
    return [
        boot,
        sole,
        shapes.lathe("BootCuff", [(LEG_RADIUS * 1.05, ANKLE_Z + 0.0), (LEG_RADIUS * 1.2, ANKLE_Z + 0.008),
                (LEG_RADIUS * 1.22, ANKLE_Z + 0.042), (LEG_RADIUS * 1.08, ANKLE_Z + 0.052)], (x, 0.0, 0.0),
                segments=LIMB_SEGMENTS, mat=mats["trim"], caps=False),
    ]


# ---------------------------------------------------------------------------------------------
# Скелет
# ---------------------------------------------------------------------------------------------

def build_armature():
    data = bpy.data.armatures.new("Armature")
    armature = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(name, head, tail, parent=None):
        edit_bone = data.edit_bones.new(name)
        edit_bone.head = Vector(head)
        edit_bone.tail = Vector(tail)
        if parent is not None:
            edit_bone.parent = data.edit_bones[parent]

    bone("Hips", (0.0, 0.0, HIP_Z), (0.0, 0.0, TORSO_BOTTOM_Z))
    bone("Spine", (0.0, 0.0, TORSO_BOTTOM_Z), (0.0, 0.0, 1.2), "Hips")
    bone("Chest", (0.0, 0.0, 1.2), (0.0, 0.0, SHOULDER_Z), "Spine")
    bone("Neck", (0.0, 0.0, SHOULDER_Z), (0.0, 0.0, NECK_Z + 0.02), "Chest")
    bone("Head", (0.0, 0.0, NECK_Z + 0.02), (0.0, 0.0, HEAD_CENTER_Z + HEAD_SIZE[2] * 0.5), "Neck")
    # Левая сторона персонажа — минус X.
    for prefix, side in (("Left", -1.0), ("Right", 1.0)):
        arm_x = SHOULDER_X * side
        bone(prefix + "UpperArm", (arm_x, 0.0, SHOULDER_Z), (arm_x, 0.0, ELBOW_Z), "Chest")
        bone(prefix + "LowerArm", (arm_x, 0.0, ELBOW_Z), (arm_x, 0.0, WRIST_Z), prefix + "UpperArm")
        bone(prefix + "Hand", (arm_x, 0.0, WRIST_Z), (arm_x, 0.0, HAND_TIP_Z), prefix + "LowerArm")
        leg_x = HIP_X * side
        bone(prefix + "UpperLeg", (leg_x, 0.0, HIP_Z), (leg_x, 0.0, KNEE_Z), "Hips")
        bone(prefix + "LowerLeg", (leg_x, 0.0, KNEE_Z), (leg_x, 0.0, ANKLE_Z), prefix + "UpperLeg")
        bone(prefix + "Foot", (leg_x, 0.0, ANKLE_Z), (leg_x, 0.13, 0.02), prefix + "LowerLeg")
    bpy.ops.object.mode_set(mode="OBJECT")
    return armature


def rigid_piece(name, groups, armature):
    """groups = [(имя кости, [объекты]), ...] -> один меш с жёсткой привязкой к этим костям."""
    objects = []
    for bone_name, parts in groups:
        for part in parts:
            shapes.freeze(part)
            shapes.skin_to(part, bone_name)
            objects.append(part)
    piece = common.join(objects, name)
    shapes.bind_to_armature(piece, armature)
    return piece


# ---------------------------------------------------------------------------------------------
# Сборка файлов
# ---------------------------------------------------------------------------------------------

def build_body(path):
    common.reset_scene()
    mats = make_materials()
    armature = build_armature()

    rigid_piece("HeadPiece", [("Head", build_head(mats))], armature)

    plate, eyes = build_face(mats)
    rigid_piece("FacePlate", [("Head", [plate])], armature)
    rigid_piece("FaceEyes", [("Head", [eyes])], armature)
    rigid_piece("TorsoPiece", [("Chest", build_torso(mats))], armature)
    rigid_piece("PelvisPiece", [("Hips", build_pelvis(mats))], armature)
    for prefix, side in (("Left", -1.0), ("Right", 1.0)):
        arm_x = SHOULDER_X * side
        rigid_piece("Arm" + prefix, [
            (prefix + "UpperArm", build_upper_arm(mats, arm_x)),
            (prefix + "LowerArm", build_lower_arm(mats, arm_x)),
            (prefix + "Hand", build_hand(mats, arm_x, side)),
        ], armature)
        leg_x = HIP_X * side
        rigid_piece("Leg" + prefix, [
            (prefix + "UpperLeg", build_upper_leg(mats, leg_x)),
            (prefix + "LowerLeg", build_lower_leg(mats, leg_x)),
            (prefix + "Foot", build_foot(mats, leg_x)),
        ], armature)

    report()
    common.export_glb(path)


def build_view_arms(path):
    """Руки для вида от первого лица: кисть вокруг точки хвата, предплечье согнуто в запястье."""
    common.reset_scene()
    mats = make_materials()
    for name, side in (("ArmRight", 1.0), ("ArmLeft", -1.0)):
        x = SHOULDER_X * side
        wrist = (x, 0.0, WRIST_Z)
        forearm = build_lower_arm(mats, x, top_z=WRIST_Z + VIEW_ARM_LENGTH, with_elbow=False)
        for part in forearm:
            shapes.rotate_about(part, wrist, "X", VIEW_ARM_PITCH_DEG)
            shapes.rotate_about(part, wrist, "Y", VIEW_ARM_YAW_DEG * side)
        arm = common.join(forearm + build_hand(mats, x, side), name)
        shapes.freeze(arm)
        # Точка хвата -> начало координат; «вдоль руки вниз» -> +Y (вперёд), «перёд тела» -> +Z (вверх).
        shapes.move(arm, (-x, 0.0, -GRIP_Z))
        shapes.transform(arm, Matrix.Rotation(math.radians(90.0), 4, "X"))
    report()
    common.export_glb(path)


def report():
    """Печатает габариты и число треугольников — сверка с метриками и бюджетом."""
    low = Vector((1.0e9, 1.0e9, 1.0e9))
    high = Vector((-1.0e9, -1.0e9, -1.0e9))
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        xs = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
        piece_low = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
        piece_high = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
        triangles = sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)
        print("PIECE %-12s tris=%5d  min=(%.3f, %.3f, %.3f)  max=(%.3f, %.3f, %.3f)" % (obj.name, triangles,
                *piece_low, *piece_high))
        low = Vector((min(low.x, piece_low.x), min(low.y, piece_low.y), min(low.z, piece_low.z)))
        high = Vector((max(high.x, piece_high.x), max(high.y, piece_high.y), max(high.z, piece_high.z)))
    print("TOTAL tris=%d  min=(%.3f, %.3f, %.3f)  max=(%.3f, %.3f, %.3f)" % (shapes.triangle_count(), *low, *high))


def main():
    args = common.script_args()
    out_dir = os.path.abspath(args[0] if args else DEFAULT_OUT_DIR)
    os.makedirs(out_dir, exist_ok=True)
    build_body(os.path.join(out_dir, BODY_FILE))
    build_view_arms(os.path.join(out_dir, ARM_FILE))


main()
