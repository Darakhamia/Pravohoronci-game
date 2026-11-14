"""Генератор персонажа «crewmate»: член экипажа в жёстком скафандре, пропорции взрослого человека.

Запуск из корня репозитория:
    blender -b --python tools/assets/character.py
    blender -b --python tools/assets/character.py -- <папка для .glb>

Пишет два файла (по умолчанию в assets/models/characters/):
    crewmate.glb      тело со скелетом (17 костей профиля Godot Humanoid);
    crewmate_arm.glb  руки для вида от первого лица, по три жёстких звена на руку:
                      ArmRight/ArmLeft         кисть, начало координат — точка хвата, пальцы по -Z Godot;
                      ForearmRight/ForearmLeft предплечье, начало — центр запястья, локоть по +Z;
                      UpperRight/UpperLeft     плечо, начало — центр локтя, уходит по +Z за кадр.
                      Звенья ставит и поворачивает scripts/gameplay/viewmodel.gd.

Скафандр собран из жёстких сегментов на кольцах-подшипниках, между ними — тканевые гофры.
Поэтому конечность отлетает целым сегментом по плечевому или тазовому кольцу: на теле остаётся
заглушка с разъёмом и обрывками кабелей (пока конечность на месте, они спрятаны внутри неё).
Тазовые кольца наклонены на 45 градусов, наплечники закреплены на торсе.

Меши тела: HeadPiece, VisorGlass, FacePlate, TorsoPiece, PelvisPiece, ArmLeft, ArmRight, LegLeft,
LegRight. Каждая конечность — один меш (прячется целиком); его же геометрию игра показывает
без скелета как отлетевшую деталь.

У мешей рук (и тела, и вида от первого лица) две формы (shape keys) кисти: в основе кисть
расслаблена, HAND_GRIP — кулак вокруг рукояти (нож, удар), HAND_TRIGGER — хват пистолета
с указательным пальцем на спуске. Вес форм выставляет игра.

Материалы здесь — заглушки с именами: при импорте Godot подменяет их ресурсами из
resources/materials/characters/ (см. .glb.import). Suit перекрашивается под игрока. Развёртка
под тайловые текстуры, в цвете вершин — затенение в щелях. На кромках сегментов поверх краски
лежит оболочка SuitChips со сколами до металла (character_shapes.wear_shell).

Размеры ниже — метрики, на которые опираются хитбоксы; меняешь их — предупреди геймплей.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "textures"))

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import character_shapes as shapes
from character_atlas import DECAL_ATLAS_SIZE, DECAL_CELLS
from character_shapes import Piece

DEFAULT_OUT_DIR = os.path.join(HERE, "..", "..", "assets", "models", "characters")
BODY_FILE = "crewmate.glb"
ARM_FILE = "crewmate_arm.glb"

# --- Материалы: имя -> (цвет sRGB, шероховатость, металл, свечение) для заглушки в Blender ---
SUIT = "Suit"                # крашеный композит, цвет игрока
WHITE = "SuitWhite"          # ранец, блок на груди, наколенники
FABRIC = "SuitFabric"        # гофры суставов
METAL = "SuitMetal"          # кольца-подшипники
DARK = "SuitMetalDark"       # замки, корпуса приборов
RUBBER = "SuitRubber"        # шланги, уплотнители, подошвы
GLOVE = "SuitGlove"          # перчатки: тёмная ткань
BOOT = "SuitBoot"            # ботинки, подсумки, ремни наколенников
CHIPS = shapes.WEAR_MATERIAL # сколы краски на кромках (оболочка поверх Suit и SuitWhite)
DECAL = "SuitDecal"          # наклейки из атласа
SCREEN = "SuitScreen"        # светящийся экранчик (тот же атлас)
GLOW = "SuitGlow"            # индикаторы
LAMP = "SuitLamp"            # фонари шлема
ALERT = "SuitAlert"          # красные огни
RED = "SuitRed"              # красный пластик: клапан, степлер
VISOR = "Visor"              # стекло шлема
FACE = "FacePlate"           # пластина внутри шлема: позже на неё ляжет фото
MATERIALS = {
    SUIT: ("ff9f1c", 0.4, 0.0, None),
    WHITE: ("dfe2e6", 0.4, 0.0, None),
    FABRIC: ("44474f", 0.9, 0.0, None),
    METAL: ("c8cbd0", 0.3, 1.0, None),
    DARK: ("2a2d34", 0.4, 1.0, None),
    RUBBER: ("101114", 0.8, 0.0, None),
    GLOVE: ("2c2e33", 0.85, 0.0, None),
    BOOT: ("5a5d66", 0.75, 0.0, None),
    CHIPS: ("9a9da3", 0.45, 1.0, None),
    DECAL: ("ffffff", 0.6, 0.0, None),
    SCREEN: ("0a1a1e", 0.3, 0.0, "3ddbd9"),
    GLOW: ("3ddbd9", 0.3, 0.0, "3ddbd9"),
    LAMP: ("fff1d6", 0.3, 0.0, "fff1d6"),
    ALERT: ("ff3b30", 0.3, 0.0, "ff3b30"),
    RED: ("c8322c", 0.4, 0.0, None),
    VISOR: ("1a1410", 0.06, 0.6, None),
    FACE: ("05080a", 0.5, 0.0, "3ddbd9"),
}
shapes.UV_SCALE.update({SUIT: 2.0, WHITE: 2.0, RED: 2.0, FABRIC: 6.25, METAL: 4.0, DARK: 4.0, RUBBER: 8.0, GLOVE: 9.0,
        BOOT: 8.0, CHIPS: 7.0})

# --- Метрики (метры; Z — вверх, +Y — перёд, +X — правая рука персонажа) ---
HEAD_CENTER = Vector((0.0, 0.0, 1.62))
HEAD_RADII = Vector((0.18, 0.185, 0.18))     # шлем: ширина 0.36, верх на 1.80
NECK_Z = 1.465               # ось наклона головы: стык колец шлема и торса
TORSO_BOTTOM_Z = 1.095
PELVIS_TOP_Z = 1.04
SHOULDER_X = 0.30
SHOULDER_Z = 1.42
ELBOW_Z = 1.14
WRIST_Z = 0.905
HAND_TIP_Z = 0.76            # кончики расслабленных пальцев
HIP_X = 0.11
HIP_Z = 0.92
KNEE_Z = 0.50
ANKLE_Z = 0.10
FACE_SIZE = 0.24             # лицевая пластина FacePlate: квадрат со скруглёнными углами
FACE_CENTER_Z = 1.615
FACE_Y = 0.088               # пластина стоит в глубине шлема, за стеклом
# Точка хвата в кулаке (для правой руки; у левой X с минусом). От неё же считает игра.
GRIP_Z = 0.85

SHOULDER_BALL = 0.086        # гофрированный шар плеча: внутри него прячутся заглушка и кабели
# Наплечник закреплён на торсе: купол над шаром плеча, ось чуть наклонена наружу.
PAULDRON_RADIUS = 0.094
PAULDRON_TILT_DEG = 14.0
PAULDRON_SPAN_DEG = 60.0
# Тазобедренное кольцо: ось смотрит наружу-вниз под этим углом к вертикали.
HIP_RING_TILT_DEG = 45.0
HIP_RING_INNER = 0.095
HIP_RING_OUTER = 0.112
# Вдоль оси кольца (от центра сустава наружу): кольцо таза, гофра ноги, кольцо ноги, бедро.
HIP_RING_BACK = -0.03
HIP_RING_FRONT = 0.012
HIP_COLLAR_END = 0.034
HIP_RACE_END = 0.047
THIGH_TOP_Z = 0.775          # ниже бедро — обычное тело вращения вокруг оси ноги
THIGH_SQUASH = 1.07          # бедро чуть шире спереди назад
# Формы кисти (shape keys): имена общие с игрой (PlayerVisuals, Viewmodel).
HAND_GRIP = "Grip"
HAND_TRIGGER = "Trigger"
HAND_POSES = ("relaxed", HAND_GRIP, HAND_TRIGGER)

# Стекло шлема: ось взгляда чуть опущена, проём — «скруглённый прямоугольник» в углах.
VISOR_TILT_DEG = 8.0
VISOR_HALF_WIDTH_DEG = 66.0
VISOR_UP_DEG = 41.0
VISOR_DOWN_DEG = 31.0
VISOR_POWER = 3.2
VISOR_FRAME_DEG = 4.5
HELMET_SEGMENTS = 28

# Сечения жёсткого торса снизу вверх: (z, полуширина, полуглубина, сдвиг вперёд).
TORSO_POWER = 2.7
TORSO_SECTIONS = (
    (1.095, 0.168, 0.114, 0.0),
    (1.12, 0.186, 0.127, 0.0),
    (1.20, 0.208, 0.140, 0.003),
    (1.30, 0.220, 0.146, 0.006),
    (1.38, 0.218, 0.142, 0.004),
    (1.425, 0.198, 0.132, 0.0),
    (1.452, 0.160, 0.122, 0.0),
    (1.462, 0.130, 0.110, 0.0),
)
PACK_SIZE = (0.35, 0.15, 0.40)
PACK_CENTER = (0.0, -0.212, 1.275)
COWL_SIZE = (0.358, 0.158, 0.125)        # крышка ранца в цвет игрока: по ней узнают со спины
COWL_CENTER = (0.0, -0.214, 1.42)

LIMB_SEGMENTS = 12           # граней по окружности у сегментов рук и ног
FINGER_SIDES = 6
# У мешей рук сглаживаются и рёбра шестигранных трубок пальцев (60 градусов между гранями).
ARM_SMOOTH_ANGLE_DEG = 62.0

# Руки от первого лица: подробнее, рукав чуть тоньше (у самой камеры он иначе закрывает кадр),
# плечо длиннее настоящего — его срез всегда за кадром.
VIEW_DETAIL = 1.5
VIEW_SLEEVE_SCALE = 0.84
VIEW_UPPER_LENGTH = 0.44
VIEW_WRIST_Z = WRIST_Z + 0.012


def make_materials():
    for name, (color, roughness, metallic, emission) in MATERIALS.items():
        shapes.make_material(name, color, roughness, metallic, emission, 2.0)


def decal_uv(name):
    return shapes.atlas_uv(DECAL_CELLS[name], DECAL_ATLAS_SIZE)


def lathe_x(profile, mat, segments, center, **kwargs):
    """Тело вращения вокруг оси X: profile = [(радиус, x), ...]."""
    geo = shapes.lathe(profile, mat, segments, **kwargs)
    geo.transform(Matrix.Rotation(math.radians(90.0), 4, "Y"))
    return geo.move(center)


def lathe_y(profile, mat, segments, center, **kwargs):
    """Тело вращения вокруг оси Y: profile = [(радиус, y), ...]."""
    geo = shapes.lathe(profile, mat, segments, **kwargs)
    geo.transform(Matrix.Rotation(math.radians(-90.0), 4, "X"))
    return geo.move(center)


def bellows(z_low, z_high, radius, depth, ribs, rounded=True):
    """Профиль гофры: ribs складок между z_low и z_high. rounded = False — складки «домиком»
    (вдвое меньше граней: для коротких гофр, которые не видно вблизи)."""
    pitch = (z_high - z_low) / ribs
    profile = []
    for index in range(ribs):
        z = z_low + index * pitch
        profile.append((radius - depth, z))
        profile += [(radius, z + 0.3 * pitch), (radius, z + 0.7 * pitch)] if rounded else [(radius, z + 0.5 * pitch)]
    profile.append((radius - depth, z_high))
    return profile


def plate(z_low, z_high, radius_low, radius_high, lip=0.004, bulge=0.003):
    """Профиль жёсткого сегмента: утолщённые кромки на концах, лёгкая бочка посередине.
    Кромки облезают: передай lathe(wear=PLATE_WEAR)."""
    middle = (z_low + z_high) * 0.5
    return [
        (radius_low - 0.012, z_low), (radius_low + lip, z_low + 0.003), (radius_low + lip, z_low + 0.016),
        (radius_low, z_low + 0.02), ((radius_low + radius_high) * 0.5 + bulge, middle),
        (radius_high, z_high - 0.02), (radius_high + lip, z_high - 0.016), (radius_high + lip, z_high - 0.003),
        (radius_high - 0.012, z_high),
    ]


def band(z_low, z_high, radius, thickness=0.006, chamfer=0.004):
    """Профиль кольца-подшипника: замкнутый контур для lathe(closed=True)."""
    inner = radius - thickness
    return [(inner, z_low), (radius - chamfer, z_low), (radius, z_low + chamfer), (radius, z_high - chamfer),
            (radius - chamfer, z_high), (inner, z_high)]


def strap(z_low, z_high, radius, thickness=0.008):
    """Профиль ремня или хомута: простое кольцо без фасок и без внутренней стенки
    (для lathe(caps=False))."""
    inner = radius - thickness
    return [(inner, z_low), (radius, z_low), (radius, z_high), (inner, z_high)]


# Отрезки профиля plate(), на которых облезает краска: наружные грани кромок.
PLATE_WEAR = (1, 6)


def ribbed_ball(radius, center_z, ribs=5, depth=0.006):
    """Профиль гофрированного шара сустава для lathe (снизу вверх)."""
    count = ribs * 2
    points = [(0.0, center_z - radius)]
    for index in range(1, count):
        angle = math.pi * index / count - math.pi * 0.5
        rib = radius - (depth if index % 2 == 0 else 0.0)
        points.append((rib * math.cos(angle), center_z + rib * math.sin(angle)))
    points.append((0.0, center_z + radius))
    return points


def cylinder_surface(axis_x, radius_fn, angle_deg, half_angle_deg, z_center, half_height, squash_y=1.0, axis_y=0.0):
    """Поверхность для shapes.dome: участок цилиндра вокруг вертикальной оси (axis_x, axis_y).
    u = -1..1 — вокруг оси (в сторону роста угла), v = -1..1 — по высоте. Угол 0 — в сторону +X,
    90 — вперёд (+Y). radius_fn(z) -> радиус."""
    def surface(u, v):
        angle = math.radians(angle_deg + u * half_angle_deg)
        z = z_center + v * half_height
        radius = radius_fn(z)
        normal = Vector((math.cos(angle), math.sin(angle) / squash_y, 0.0)).normalized()
        return Vector((axis_x + radius * math.cos(angle), axis_y + radius * squash_y * math.sin(angle), z)), normal
    return surface


def plate_outline(count=16, power=3.5):
    """Контур накладной пластины в координатах (u, v): скруглённый прямоугольник."""
    return shapes.superellipse(1.0, 1.0, count, power)


def armor_plate(surface, mat, thickness, count=16, power=3.5, bolts=(), crown=0.0):
    """Накладная бронепластина с фаской и болтами: bolts — [(u, v), ...]. crown приподнимает середину."""
    rings = [(1.0, -0.003), (1.0, thickness * 0.55), (0.93, thickness), (0.55, thickness + crown * 0.7),
            (0.2, thickness + crown)]
    geos = [shapes.dome(surface, plate_outline(count, power), rings, mat, wear=(1,))]
    for u, v in bolts:
        point, normal = surface(u, v)
        base = point + normal * (thickness - 0.001)
        geos.append(shapes.rod(base, base + normal * 0.004, 0.0052, METAL, 5))
    return geos


def interpolate(table, z):
    """Линейная интерполяция по таблице [(z, значение), ...], отсортированной по z."""
    if z <= table[0][0]:
        return table[0][1]
    for (z0, value0), (z1, value1) in zip(table, table[1:]):
        if z <= z1:
            return value0 + (value1 - value0) * (z - z0) / (z1 - z0)
    return table[-1][1]


def hip_frame():
    """Оси правого тазобедренного кольца: axis — наружу-вниз, across — наружу-вверх, forward — вперёд."""
    tilt = math.radians(HIP_RING_TILT_DEG)
    axis = Vector((math.sin(tilt), 0.0, -math.cos(tilt)))
    across = Vector((math.cos(tilt), 0.0, math.sin(tilt)))
    return axis, across, Vector((0.0, 1.0, 0.0))


def hip_circle(offset, radius, count):
    """Окружность в плоскости тазобедренного кольца (правая нога): offset — вдоль оси от центра сустава."""
    axis, across, forward = hip_frame()
    center = Vector((HIP_X, 0.0, HIP_Z)) + axis * offset
    return [center + (across * math.cos(math.tau * index / count) + forward * math.sin(math.tau * index / count)) * radius
            for index in range(count)]


def hip_lathe(profile, mat, segments, **kwargs):
    """Тело вращения вокруг оси правого тазобедренного кольца: profile = [(радиус, вдоль оси), ...]."""
    geo = shapes.lathe(profile, mat, segments, **kwargs)
    geo.transform(Matrix.Rotation(math.radians(180.0 - HIP_RING_TILT_DEG), 4, "Y"))
    return geo.move((HIP_X, 0.0, HIP_Z))


def face_outward(geo, center):
    """Разворачивает незамкнутую оболочку наружу от точки center."""
    points = [geo.verts[index] for index in geo.faces[0]]
    middle = sum(points, Vector((0.0, 0.0, 0.0))) / len(points)
    if shapes._face_normal(points).dot(middle - Vector(center)) < 0.0:
        geo.flip()
    return geo


def mark_wear(geo, count, bands):
    """Помечает износом пояса оболочки loft (count граней в поясе)."""
    for band in bands:
        for index in range(count):
            geo.wear[band * count + index] = True
    return geo


# ---------------------------------------------------------------------------------------------
# Шлем
# ---------------------------------------------------------------------------------------------

def _visor_frame():
    tilt = math.radians(VISOR_TILT_DEG)
    axis = Vector((0.0, math.cos(tilt), -math.sin(tilt)))
    right = Vector((1.0, 0.0, 0.0))
    up = right.cross(axis)
    return axis, right, up


def helmet_point(theta, phi, factor=1.0):
    """Точка шлема: theta — угол от оси взгляда, phi — вокруг неё; factor раздувает оболочку."""
    axis, right, up = _visor_frame()
    direction = axis * math.cos(theta) + (right * math.cos(phi) + up * math.sin(phi)) * math.sin(theta)
    return Vector((HEAD_CENTER.x + direction.x * HEAD_RADII.x * factor,
            HEAD_CENTER.y + direction.y * HEAD_RADII.y * factor,
            HEAD_CENTER.z + direction.z * HEAD_RADII.z * factor))


def visor_edge(phi):
    """Угол от оси взгляда до края стекла в направлении phi."""
    c, s = math.cos(phi), math.sin(phi)
    half_height = math.radians(VISOR_UP_DEG if s >= 0.0 else VISOR_DOWN_DEG)
    half_width = math.radians(VISOR_HALF_WIDTH_DEG)
    return (abs(c / half_width) ** VISOR_POWER + abs(s / half_height) ** VISOR_POWER) ** (-1.0 / VISOR_POWER)


def helmet_ring(share, factor, extra_deg=0.0, toward_back=0.0):
    """Кольцо точек шлема: share — доля от края стекла, toward_back — доля пути от края к затылку."""
    points = []
    for index in range(HELMET_SEGMENTS):
        phi = math.tau * index / HELMET_SEGMENTS
        theta = visor_edge(phi) * share + math.radians(extra_deg)
        theta += (math.pi - theta) * toward_back
        points.append(helmet_point(theta, phi, factor))
    return points


def ellipsoid_point(x, angle_deg, factor=1.0):
    """Точка шлема в продольной плоскости: x — вбок, angle_deg — от «вперёд» (0) через верх (90)
    к затылку (180)."""
    k = math.sqrt(max(1.0 - (x / HEAD_RADII.x) ** 2, 0.0))
    angle = math.radians(angle_deg)
    return Vector((x, HEAD_CENTER.y + HEAD_RADII.y * math.cos(angle) * k * factor,
            HEAD_CENTER.z + HEAD_RADII.z * math.sin(angle) * k * factor))


CREST_HALF_WIDTH = 0.047
CREST_START_DEG = 47.0
CREST_END_DEG = 184.0
CREST_HEIGHT = 0.03          # доля радиуса шлема
CREST_SUNK = 0.985           # края полосы утоплены под оболочку шлема


def _helmet_crest():
    """Гребень: сетка «угол вдоль шлема x поперёк», у торцов полоса сужается по дуге."""
    cap_deg = 9.0
    angles = [CREST_START_DEG, CREST_START_DEG + 1.5, CREST_START_DEG + 4.5, CREST_START_DEG + cap_deg]
    angle = CREST_START_DEG + cap_deg
    while angle + 13.0 < CREST_END_DEG - cap_deg:
        angle += 13.0
        angles.append(angle)
    angles += [CREST_END_DEG - cap_deg, CREST_END_DEG - 4.5, CREST_END_DEG - 1.5, CREST_END_DEG]
    across = (-1.0, -0.86, -0.45, 0.0, 0.45, 0.86, 1.0)
    geo = shapes.Geo()
    rows = []
    for angle in angles:
        from_end = min(angle - CREST_START_DEG, CREST_END_DEG - angle)
        t = min(from_end / cap_deg, 1.0)
        width = CREST_HALF_WIDTH * max(math.sqrt(1.0 - (1.0 - t) ** 2), 0.12)
        lift = min(from_end / 1.5, 1.0)
        row = []
        for share in across:
            edge = abs(share) == 1.0
            factor = CREST_SUNK if edge or lift <= 0.0 else 1.0 + CREST_HEIGHT * lift
            row.append(geo.add_vert(ellipsoid_point(share * width, angle, factor)))
        rows.append(row)
    for near, far in zip(rows, rows[1:]):
        for index in range(len(across) - 1):
            worn = index in (0, len(across) - 2)
            geo.add_face((near[index], near[index + 1], far[index + 1], far[index]), WHITE, None, worn)
    return face_outward(geo, HEAD_CENTER)


def build_head(piece):
    bone = "Head"
    # Оболочка: от рамки стекла к затылку. Контуры идут по часовой стрелке, если смотреть
    # спереди, — то есть против часовой навстречу направлению построения (назад).
    shell = [helmet_ring(1.0, 1.0, VISOR_FRAME_DEG + 0.5)]
    for toward_back in (0.07, 0.17, 0.3, 0.45, 0.6, 0.75, 0.88, 0.96):
        shell.append(helmet_ring(1.0, 1.0, VISOR_FRAME_DEG + 0.5, toward_back))
    piece.add(mark_wear(shapes.loft(shell, SUIT, cap_start=False, cap_end=True), HELMET_SEGMENTS, (0,)), bone)
    # Рамка-уплотнитель стекла.
    frame = [helmet_ring(1.0, 0.975), helmet_ring(1.0, 1.03), helmet_ring(1.0, 1.035, VISOR_FRAME_DEG),
            helmet_ring(1.0, 0.99, VISOR_FRAME_DEG + 0.6)]
    piece.add(shapes.loft(frame, RUBBER, cap_start=False, cap_end=False), bone)
    # Подкладка: тёмная чаша внутри, видна сквозь стекло вокруг лицевой пластины.
    liner = [helmet_ring(1.0, 0.972), helmet_ring(1.0, 0.95, 4.0)]
    for toward_back in (0.25, 0.5, 0.75, 0.95):
        liner.append(helmet_ring(1.0, 0.94, 4.0, toward_back))
    piece.add(shapes.loft(liner, RUBBER, cap_start=False, cap_end=True).flip(), bone)

    # Гребень со светлой накладкой: от лба через макушку к затылку. Полоса лежит на оболочке
    # шлема; края утоплены под неё, торцы скруглены — спереди она кончается над рамкой стекла.
    piece.add(_helmet_crest(), bone)
    # Кольцо шлема: входит в кольцо торса.
    piece.add(shapes.lathe(band(1.478, 1.506, 0.152, 0.03), METAL, 28), bone)
    piece.add(shapes.lathe([(0.118, 1.5), (0.146, 1.503), (0.132, 1.522), (0.118, 1.528)], DARK, 28, caps=False), bone)
    for side in (-1.0, 1.0):
        # Боковые модули связи.
        x = side * (HEAD_RADII.x - 0.012)
        module = lathe_x([(0.0, 0.0), (0.05, 0.0), (0.056, 0.006), (0.056, 0.02), (0.046, 0.03), (0.0, 0.03)], DARK, 12,
                (0.0, -0.012, 1.6))
        cap = lathe_x([(0.0, 0.028), (0.03, 0.028), (0.03, 0.036), (0.024, 0.04), (0.0, 0.04)], METAL, 10,
                (0.0, -0.012, 1.6))
        # Фонарь на виске.
        lamp = lathe_y([(0.0, -0.03), (0.016, -0.03), (0.02, -0.022), (0.02, 0.018), (0.017, 0.024), (0.0, 0.024)],
                DARK, 10, (0.138, 0.085, 1.722))
        lens = lathe_y([(0.0, 0.022), (0.015, 0.022), (0.012, 0.027), (0.0, 0.028)], LAMP, 10, (0.138, 0.085, 1.722))
        bracket = shapes.box((0.02, 0.03, 0.03), (0.128, 0.078, 1.706), DARK, 0.004, 1, 1)
        for geo in (module, cap):
            geo.move((abs(x), 0.0, 0.0))
        for geo in (module, cap, lamp, lens, bracket):
            if side < 0.0:
                geo.mirror_x()
            piece.add(geo, bone)
    # Блок на затылке с красным огоньком и антенна.
    piece.add(shapes.box((0.12, 0.04, 0.07), (0.0, -0.172, 1.565), DARK, 0.008, 1, 2), bone)
    piece.add(shapes.box((0.05, 0.008, 0.012), (0.0, -0.194, 1.578), ALERT, 0.003, 1, 1), bone)
    piece.add(shapes.rod((0.172, -0.03, 1.63), (0.186, -0.075, 1.745), 0.0045, DARK, 6), bone)
    piece.add(shapes.sphere(0.008, (0.186, -0.075, 1.747), ALERT, 6, 4), bone)


def build_visor(piece):
    """Стекло — отдельный меш: прозрачный материал, свой проход отрисовки."""
    geo = shapes.Geo()
    centre = geo.add_vert(helmet_point(0.0, 0.0, 0.985))
    rings = []
    for share in (0.36, 0.7, 1.0):
        rings.append([geo.add_vert(point) for point in helmet_ring(share, 0.985 if share < 1.0 else 0.978)])
    count = HELMET_SEGMENTS
    for index in range(count):
        following = (index + 1) % count
        geo.add_face((centre, rings[0][following], rings[0][index]), VISOR)
        for lower, upper in zip(rings, rings[1:]):
            geo.add_face((lower[index], lower[following], upper[following], upper[index]), VISOR)
    piece.add(geo, "Head")


def build_face(piece):
    """Лицевая пластина — отдельный меш с UV 0..1: позже на неё ляжет фото («бумажная маска»)."""
    outline = shapes.rounded_rect(FACE_SIZE, FACE_SIZE, 0.055, 4)
    geo = shapes.Geo()
    indices = []
    uv = []
    for x, z in outline:
        # Контур в плоскости XZ смотрит назад, поэтому обходим его в обратную сторону.
        indices.append(geo.add_vert((x, FACE_Y, FACE_CENTER_Z + z)))
        # Картинка читается правильно для смотрящего на модель спереди.
        uv.append((0.5 - x / FACE_SIZE, 0.5 + z / FACE_SIZE))
    geo.add_face(tuple(reversed(indices)), FACE, list(reversed(uv)))
    piece.add(geo, "Head")


# ---------------------------------------------------------------------------------------------
# Торс и таз
# ---------------------------------------------------------------------------------------------

def torso_size(z):
    """(полуширина, полуглубина, сдвиг вперёд) торса на высоте z."""
    for lower, upper in zip(TORSO_SECTIONS, TORSO_SECTIONS[1:]):
        if lower[0] <= z <= upper[0]:
            t = (z - lower[0]) / (upper[0] - lower[0])
            return tuple(lower[i] + (upper[i] - lower[i]) * t for i in (1, 2, 3))
    edge = TORSO_SECTIONS[0] if z < TORSO_SECTIONS[0][0] else TORSO_SECTIONS[-1]
    return edge[1], edge[2], edge[3]


def torso_surface(x, z, back=False):
    """Y поверхности торса спереди (или сзади) в точке (x, z)."""
    half_width, half_depth, shift = torso_size(z)
    reach = half_depth * max(1.0 - abs(x / half_width) ** TORSO_POWER, 0.0) ** (1.0 / TORSO_POWER)
    return shift - reach if back else shift + reach


def torso_decal(shell, x, z, width, height, cell, columns=10, rows=4, lift=0.0025):
    """Наклейка на груди: сетка точек, спроецированных на саму оболочку торса и приподнятых по
    нормали, — корпус нигде не пробивается сквозь картинку."""
    tree = BVHTree.FromPolygons([tuple(v) for v in shell.verts], shell.faces, all_triangles=False)
    u0, v0, u1, v1 = decal_uv(cell)
    geo = shapes.Geo()
    grid = []
    for row in range(rows + 1):
        pz = z + height * (row / rows - 0.5)
        line = []
        for column in range(columns + 1):
            # Слева направо для смотрящего спереди — от +X к -X модели.
            px = x + width * (0.5 - column / columns)
            location, normal, _, _ = tree.ray_cast(Vector((px, 1.0, pz)), Vector((0.0, -1.0, 0.0)))
            line.append(geo.add_vert(location + normal * lift))
        grid.append(line)
    for row in range(rows):
        for column in range(columns):
            ua = u0 + (u1 - u0) * column / columns
            ub = u0 + (u1 - u0) * (column + 1) / columns
            va = v0 + (v1 - v0) * row / rows
            vb = v0 + (v1 - v0) * (row + 1) / rows
            geo.add_face((grid[row][column], grid[row][column + 1], grid[row + 1][column + 1], grid[row + 1][column]),
                    DECAL, [(ua, va), (ub, va), (ub, vb), (ua, vb)])
    return geo


def pauldron_surface(radius):
    """Поверхность для shapes.dome: купол вокруг правого плеча. (u, v) — точка в круге радиуса 1:
    u — поперёк (наружу), v — вперёд."""
    tilt = math.radians(PAULDRON_TILT_DEG)
    axis = Vector((math.sin(tilt), 0.0, math.cos(tilt)))
    across = Vector((math.cos(tilt), 0.0, -math.sin(tilt)))
    forward = Vector((0.0, 1.0, 0.0))
    center = Vector((SHOULDER_X, 0.0, SHOULDER_Z))

    def surface(u, v):
        distance = math.hypot(u, v)
        theta = math.radians(PAULDRON_SPAN_DEG) * distance
        side = (across * u + forward * v) / distance if distance > 1.0e-9 else across
        direction = axis * math.cos(theta) + side * math.sin(theta)
        return center + direction * radius, direction
    return surface


def build_torso(piece):
    bone = "Chest"
    count = 32
    sections = [shapes.section(shapes.superellipse(a, b, count, TORSO_POWER, (0.0, shift)), z)
            for z, a, b, shift in TORSO_SECTIONS]
    shell = shapes.loft(sections, SUIT)
    piece.add(mark_wear(shell, count, (0, len(sections) - 3)), bone)
    # Пояс-разъём по линии стыка двух половин торса.
    seam = []
    for z, grow in ((1.168, 0.004), (1.172, 0.011), (1.19, 0.011), (1.194, 0.004)):
        a, b, shift = torso_size(z)
        seam.append(shapes.section(shapes.superellipse(a + grow, b + grow, count, TORSO_POWER, (0.0, shift)), z))
    piece.add(shapes.loft(seam, DARK, False, False), bone)
    # Нижнее кольцо торса (поясной подшипник) и кольцо горловины с замками.
    a, b, _ = torso_size(TORSO_BOTTOM_Z)
    piece.add(shapes.lathe(band(1.078, 1.108, a + 0.012, 0.03), METAL, 24, (1.0, (b + 0.012) / (a + 0.012))), bone)
    piece.add(shapes.lathe(band(1.446, 1.48, 0.16, 0.03), DARK, 20), bone)
    for angle in (35.0, 145.0, 215.0, 325.0):
        latch = shapes.cuboid((0.034, 0.014, 0.026), (0.0, 0.163, 1.462), METAL)
        piece.add(latch.rotate("Z", angle - 90.0), bone)

    for side in (-1.0, 1.0):
        geos = []
        # Плечевой узел: раструб корпуса и кольцо-подшипник, в которое входит шар руки.
        geos.append(lathe_x([(0.122, -0.15), (0.116, -0.1), (0.104, -0.078)], SUIT, 16, (SHOULDER_X, 0.0, SHOULDER_Z - 0.004),
                caps=False))
        geos.append(lathe_x([(0.085, -0.09), (0.101, -0.09), (0.106, -0.082), (0.106, -0.06), (0.098, -0.05), (0.085, -0.05)],
                METAL, 16, (SHOULDER_X, 0.0, SHOULDER_Z), closed=True))
        # Наплечник: жёсткий купол над шаром плеча, держится на кронштейне у горловины.
        rings = [(1.0, -0.008), (1.0, 0.003), (0.95, 0.0095), (0.7, 0.0115), (0.38, 0.0125)]
        geos.append(shapes.dome(pauldron_surface(PAULDRON_RADIUS), shapes.superellipse(1.0, 1.0, 16, 2.3), rings, SUIT,
                wear=(1,)))
        # Подбой наплечника: тёмная изнанка, чтобы купол не просвечивал снизу.
        lining = shapes.dome(pauldron_surface(PAULDRON_RADIUS - 0.003), shapes.superellipse(1.0, 1.0, 16, 2.3),
                [(1.0, 0.0)], RUBBER)
        geos.append(lining.flip())
        for y in (-0.05, 0.05):
            point, normal = pauldron_surface(PAULDRON_RADIUS + 0.008)(-0.55, y / 0.09 * 0.55)
            geos.append(shapes.rod(point, point + normal * 0.005, 0.0065, METAL, 6))
        # Заглушка с разъёмом и обрывки кабелей: видны, только когда рука отлетела.
        geos.append(lathe_x([(0.0, -0.062), (0.086, -0.062)], DARK, 16, (SHOULDER_X, 0.0, SHOULDER_Z)))
        geos.append(lathe_x([(0.0, -0.062), (0.036, -0.062), (0.036, -0.046), (0.03, -0.04), (0.0, -0.04)], METAL, 10,
                (SHOULDER_X, 0.0, SHOULDER_Z)))
        for index, (y, droop, tip) in enumerate(((-0.018, 0.058, GLOW), (0.004, 0.044, None), (0.022, 0.05, ALERT))):
            path = shapes.smooth_path([(SHOULDER_X - 0.045, y, SHOULDER_Z + 0.006), (SHOULDER_X - 0.016, y * 1.2, SHOULDER_Z + 0.004),
                    (SHOULDER_X + 0.004, y * 1.5, SHOULDER_Z - 0.02), (SHOULDER_X + 0.008, y * 1.7, SHOULDER_Z - droop)], 1)
            geos.append(shapes.tube(path, 0.0045, RUBBER, 4))
            end = path[-1]
            geos.append(shapes.sphere(0.0065, end + Vector((0.0, 0.0, -0.004)), METAL if tip is None else tip, 5, 3))
        # Шланг от блока на груди к ранцу, с муфтами на концах.
        hose = shapes.smooth_path([(0.108, 0.168, 1.236), (0.16, 0.162, 1.214), (0.2, 0.112, 1.184), (0.213, 0.03, 1.166),
                (0.2, -0.07, 1.166), (0.158, -0.142, 1.186)], 2)
        geos.append(shapes.tube(hose, 0.0145, RUBBER, 6))
        geos.append(shapes.tube(hose[:2], 0.019, METAL, 6))
        geos.append(shapes.tube(hose[-2:], 0.019, METAL, 6))
        for geo in geos:
            if side < 0.0:
                geo.mirror_x()
            piece.add(geo, bone)

    _build_chest_unit(piece, bone)
    _build_backpack(piece, bone)
    piece.add(torso_decal(shell, 0.0, 1.372, 0.16, 0.04, "warning"), bone)


def _build_chest_unit(piece, bone):
    """Блок управления на груди: экран, шкалы, тумблеры, пропуск на прищепке."""
    front = torso_surface(0.0, 1.27) + 0.05
    centre_y = front - 0.0375
    piece.add(shapes.box((0.21, 0.075, 0.135), (0.0, centre_y, 1.27), WHITE, 0.016, 2, 3, wear=True), bone)
    piece.add(shapes.box((0.19, 0.012, 0.118), (0.0, front - 0.003, 1.27), DARK, 0.008, 1, 2), bone)
    face = front + 0.004
    piece.add(shapes.quad((0.05, face, 1.272), (0, 1, 0), (0, 0, 1), 0.078, 0.078, DECAL, decal_uv("panel")), bone)
    piece.add(shapes.quad((-0.046, face, 1.287), (0, 1, 0), (0, 0, 1), 0.08, 0.06, SCREEN, decal_uv("screen")), bone)
    for index in range(3):
        x = -0.074 + index * 0.028
        piece.add(shapes.box((0.016, 0.006, 0.016), (x, face, 1.238), METAL, 0.002, 1, 1), bone)
        piece.add(shapes.rod((x, face, 1.238), (x, face + 0.014, 1.238 + (0.006 if index != 1 else -0.006)), 0.0032,
                METAL, 6), bone)
    piece.add(shapes.sphere(0.0065, (0.0, face + 0.002, 1.238), GLOW, 8, 4), bone)
    # Ручки сверху и аварийный клапан сбоку.
    for x in (-0.062, 0.062):
        piece.add(shapes.lathe([(0.0, 1.335), (0.017, 1.335), (0.017, 1.35), (0.013, 1.354), (0.0, 1.354)], DARK, 10,
                center=(x, centre_y + 0.008, 0.0)), bone)
    piece.add(lathe_x([(0.0, 0.0), (0.02, 0.0), (0.024, 0.006), (0.024, 0.016), (0.016, 0.022), (0.0, 0.022)], RED, 10,
            (0.105, centre_y, 1.292)), bone)
    # Пропуск: карточка с эмблемой и штрихкодом висит на прищепке под блоком.
    card = shapes.combine([
        shapes.box((0.056, 0.003, 0.084), (0.0, 0.0, -0.05), WHITE, 0.001, 1, 2),
        shapes.quad((0.0, 0.0017, -0.036), (0, 1, 0), (0, 0, 1), 0.036, 0.036, DECAL, decal_uv("patch")),
        shapes.quad((0.0, 0.0017, -0.074), (0, 1, 0), (0, 0, 1), 0.046, 0.0153, DECAL, decal_uv("barcode")),
        shapes.box((0.014, 0.008, 0.02), (0.0, 0.0, -0.004), METAL, 0.002, 1, 1),
    ])
    card.rotate("X", -7.0).rotate("Z", 6.0).move((0.064, centre_y + 0.02, 1.206))
    piece.add(card, bone)


def _louvre(x, z, back, size=0.112):
    """Жалюзи ранца геометрией: рамка, тёмная ниша и наклонные ламели."""
    geos = []
    half = size * 0.5
    inner = half - 0.011
    # Рамка: контуры от корпуса наружу и обратно в нишу.
    frame = []
    for reach, depth in ((half, 0.0), (half, 0.012), (inner, 0.012), (inner, 0.002)):
        frame.append([(x - reach, back - depth, z - reach), (x + reach, back - depth, z - reach),
                (x + reach, back - depth, z + reach), (x - reach, back - depth, z + reach)])
    geos.append(face_outward(shapes.loft(frame, WHITE, False, False), (x, back + 0.05, z)))
    geos.append(shapes.quad((x, back - 0.002, z), (0, -1, 0), (0, 0, 1), inner * 2.0, inner * 2.0, RUBBER))
    slats = 5
    for index in range(slats):
        slat_z = z + (index - (slats - 1) * 0.5) * (inner * 2.0 / slats)
        slat = shapes.cuboid((inner * 2.0, 0.003, 0.021), (x, back - 0.0075, slat_z), METAL)
        geos.append(slat.rotate("X", 42.0, (x, back - 0.0075, slat_z)))
    return geos


def _build_backpack(piece, bone):
    """Ранец жизнеобеспечения: крышка в цвет игрока, жалюзи, баллоны с вентилями на раме,
    огни состояния и блок маневровых сопел."""
    width, depth, height = PACK_SIZE
    cx, cy, cz = PACK_CENTER
    back = cy - depth * 0.5
    piece.add(shapes.box(PACK_SIZE, PACK_CENTER, WHITE, 0.022, 2, 3, wear=True), bone)
    # Крепление к спине.
    piece.add(shapes.box((0.24, 0.06, 0.3), (0.0, cy + depth * 0.5 + 0.005, cz - 0.01), DARK, 0.01, 1, 2), bone)
    # Крышка в цвет игрока с табличкой номера: по ней игрока узнают со спины.
    cowl_back = COWL_CENTER[1] - COWL_SIZE[1] * 0.5
    cowl_top = COWL_CENTER[2] + COWL_SIZE[2] * 0.5
    piece.add(shapes.box(COWL_SIZE, COWL_CENTER, SUIT, 0.03, 2, 3, wear=True), bone)
    piece.add(shapes.box((0.25, 0.01, 0.078), (0.0, cowl_back - 0.002, COWL_CENTER[2] + 0.004), WHITE, 0.004, 1, 1), bone)
    piece.add(shapes.quad((0.0, cowl_back - 0.0078, COWL_CENTER[2] + 0.004), (0, -1, 0), (0, 0, 1), 0.2, 0.062, DECAL,
            decal_uv("number")), bone)
    # Шов между крышкой и корпусом: тёмный уплотнитель с замками по бокам.
    piece.add(shapes.box((0.352, 0.152, 0.012), (0.0, cy, COWL_CENTER[2] - COWL_SIZE[2] * 0.5 - 0.003), RUBBER, 0.004, 1, 2), bone)
    for x in (-0.12, 0.12):
        piece.add(shapes.box((0.03, 0.01, 0.034), (x, cowl_back - 0.001, COWL_CENTER[2] - COWL_SIZE[2] * 0.5 + 0.004), METAL,
                0.003, 1, 1), bone)
    # Жалюзи теплообменника.
    for x in (-0.076, 0.076):
        for geo in _louvre(x, cz + 0.012, back):
            piece.add(geo, bone)
    piece.add(shapes.quad((0.078, back - 0.0015, cz - 0.118), (0, -1, 0), (0, 0, 1), 0.108, 0.072, DECAL,
            decal_uv("caution")), bone)
    piece.add(shapes.quad((-0.066, back - 0.0015, cz - 0.105), (0, -1, 0), (0, 0, 1), 0.14, 0.0525, DECAL,
            decal_uv("label")), bone)
    piece.add(shapes.quad((-0.07, back - 0.0015, cz - 0.15), (0, -1, 0), (0, 0, 1), 0.1, 0.0333, DECAL,
            decal_uv("barcode")), bone)
    # Огни состояния под крышкой.
    for index, mat in enumerate((GLOW, GLOW, ALERT)):
        piece.add(lathe_y([(0.0, -0.006), (0.008, -0.006), (0.008, 0.0), (0.0, 0.0)], mat, 8,
                (0.1 + index * 0.024, back - 0.004, cz + 0.084 - 0.004), caps=True), bone)
    # Болты по углам панели жалюзи.
    for x in (-0.148, 0.148):
        for z in (cz - 0.05, cz + 0.07):
            piece.add(shapes.rod((x, back + 0.001, z), (x, back - 0.005, z), 0.007, METAL, 6), bone)
    for side in (-1.0, 1.0):
        geos = []
        tank_x = 0.188
        tank_y = cy - 0.005
        # Баллоны по бокам: на раме из двух хомутов и стойки, сверху вентиль с маховичком.
        geos.append(shapes.lathe([(0.0, 1.1), (0.03, 1.104), (0.044, 1.122), (0.046, 1.14), (0.046, 1.3), (0.044, 1.318),
                (0.03, 1.336), (0.014, 1.342), (0.014, 1.352), (0.0, 1.352)], METAL, 10, center=(tank_x, tank_y, 0.0)))
        for z in (1.16, 1.286):
            geos.append(shapes.lathe(strap(z - 0.011, z + 0.011, 0.05), DARK, 10, center=(tank_x, tank_y, 0.0), caps=False))
            geos.append(shapes.cuboid((0.03, 0.03, 0.03), (tank_x - 0.012, tank_y - 0.05, z), DARK))
        geos.append(shapes.cuboid((0.014, 0.014, 0.16), (tank_x - 0.012, tank_y - 0.058, 1.223), DARK))
        geos.append(shapes.arc_quad((tank_x, tank_y), 0.0475, 330.0, 1.223, 0.06, 0.0225, DECAL, decal_uv("oxygen"), 4))
        geos.append(shapes.box((0.032, 0.032, 0.026), (tank_x, tank_y, 1.362), DARK, 0.005, 1, 2))
        geos.append(lathe_x([(0.0, 0.016), (0.006, 0.016), (0.006, 0.03), (0.021, 0.03), (0.023, 0.033), (0.023, 0.037),
                (0.021, 0.04), (0.0, 0.04)], RED, 10, (tank_x, tank_y, 1.362)))
        pipe = shapes.smooth_path([(tank_x - 0.012, tank_y, 1.366), (tank_x - 0.03, tank_y - 0.012, 1.376),
                (tank_x - 0.04, tank_y - 0.02, 1.37)], 2)
        geos.append(shapes.tube(pipe, 0.0065, METAL, 6))
        # Сопла маневрового блока.
        nozzle = shapes.lathe([(0.012, 0.0), (0.03, -0.04), (0.027, -0.04), (0.01, -0.004)], DARK, 10, closed=True)
        geos.append(nozzle.rotate("X", -38.0).move((0.105, back + 0.012, cz - height * 0.5 - 0.03)))
        for geo in geos:
            if side < 0.0:
                geo.mirror_x()
            piece.add(geo, bone)
    piece.add(shapes.box((0.3, 0.12, 0.08), (0.0, cy - 0.005, cz - height * 0.5 - 0.012), DARK, 0.014, 1, 2), bone)
    piece.add(shapes.quad((0.0, back + 0.0085, cz - height * 0.5 - 0.012), (0, -1, 0), (0, 0, 1), 0.26, 0.049, DECAL,
            decal_uv("hazard")), bone)
    # Ручка для переноски и антенна на крышке.
    handle = shapes.smooth_path([(-0.07, cy, cowl_top - 0.006), (-0.066, cy, cowl_top + 0.02),
            (0.066, cy, cowl_top + 0.02), (0.07, cy, cowl_top - 0.006)], 3)
    piece.add(shapes.tube(handle, 0.007, DARK, 6), bone)
    piece.add(shapes.lathe([(0.0, 0.0), (0.014, 0.0), (0.014, 0.012), (0.006, 0.018), (0.0, 0.018)], DARK, 8,
            center=(0.125, cy - 0.03, cowl_top - 0.004)), bone)
    piece.add(shapes.rod((0.125, cy - 0.03, cowl_top + 0.01), (0.132, cy - 0.045, cowl_top + 0.1),
            0.003, DARK, 5), bone)


# Жёсткие «трусы» скафандра: сечения сверху вниз (z, полуширина, полуглубина). Боковые грани идут
# под 45 градусов — на них лежат кольца тазобедренных шарниров.
PELVIS_POWER = 3.4
PELVIS_SECTIONS = (
    (0.826, 0.024, 0.078),
    (0.842, 0.034, 0.096),
    (0.88, 0.066, 0.111),
    (0.923, 0.107, 0.12),
    (0.96, 0.144, 0.124),
    (0.998, 0.182, 0.125),
    (1.02, 0.181, 0.121),
    (PELVIS_TOP_Z, 0.165, 0.111),
)


def build_pelvis(piece):
    bone = "Hips"
    count = 28
    sections = [shapes.section(shapes.superellipse(a, b, count, PELVIS_POWER), z) for z, a, b in PELVIS_SECTIONS]
    piece.add(mark_wear(shapes.loft(sections, SUIT), count, (len(sections) - 2,)), bone)
    # Поясная гофра: тянется между тазом и жёстким торсом.
    waist = shapes.lathe(bellows(PELVIS_TOP_Z - 0.012, TORSO_BOTTOM_Z - 0.008, 0.162, 0.012, 2, False), FABRIC, count,
            (1.0, 0.68), caps=False)
    piece.add(waist, shapes.blend_z("Chest", "Hips", TORSO_BOTTOM_Z - 0.01, PELVIS_TOP_Z))
    # Поясное кольцо таза под гофрой.
    piece.add(shapes.lathe(band(1.026, 1.05, 0.172, 0.03), METAL, 20, (1.0, 0.685)), bone)
    # Ремень с пряжкой, подсумками и степлером в кобуре: офис есть офис.
    piece.add(shapes.lathe(strap(0.992, 1.022, 0.191, 0.02), FABRIC, count, (1.0, 0.685), caps=False), bone)
    piece.add(shapes.box((0.06, 0.016, 0.044), (0.0, 0.132, 1.007), METAL, 0.005, 1, 2), bone)
    piece.add(shapes.box((0.034, 0.006, 0.024), (0.0, 0.141, 1.007), DARK, 0.003, 1, 1), bone)
    # Паховый ремень: от пряжки вниз между ног и вверх по спине.
    crotch = shapes.smooth_path([(0.0, 0.128, 0.99), (0.0, 0.126, 0.93), (0.0, 0.117, 0.87), (0.0, 0.094, 0.826),
            (0.0, 0.04, 0.812), (0.0, -0.04, 0.812), (0.0, -0.094, 0.826), (0.0, -0.117, 0.87), (0.0, -0.126, 0.93),
            (0.0, -0.128, 0.99)], 1)
    piece.add(shapes.tube(crotch, 0.021, FABRIC, 4, caps=False, squash=0.2, up=(1.0, 0.0, 0.0)), bone)
    piece.add(shapes.box((0.05, 0.012, 0.03), (0.0, 0.123, 0.9), METAL, 0.004, 1, 1), bone)
    for x in (-0.118, 0.118):
        pouch = shapes.box((0.075, 0.04, 0.085), (0.0, 0.0, 0.0), BOOT, 0.012, 2, 2)
        flap = shapes.box((0.079, 0.044, 0.03), (0.0, 0.0, 0.03), FABRIC, 0.008, 1, 2)
        stud = lathe_y([(0.0, -0.004), (0.006, -0.004), (0.006, 0.0), (0.0, 0.0)], METAL, 6, (0.0, -0.022, 0.024))
        for geo in (pouch, flap, stud):
            geo.rotate("Z", -20.0 if x > 0 else 20.0).move((x, -0.122, 0.995))
            piece.add(geo, bone)
    stapler = shapes.combine([
        shapes.box((0.03, 0.05, 0.11), (0.0, 0.0, 0.0), DARK, 0.008, 1, 2),
        shapes.box((0.026, 0.046, 0.05), (0.0, 0.004, 0.07), RED, 0.008, 1, 2),
        shapes.box((0.02, 0.04, 0.024), (0.0, -0.002, 0.092), METAL, 0.005, 1, 1),
    ])
    piece.add(stapler.rotate("X", 10.0).rotate("Z", -62.0).move((0.122, 0.112, 0.962)), bone)
    axis, across, forward = hip_frame()
    hip = Vector((HIP_X, 0.0, HIP_Z))
    for side in (-1.0, 1.0):
        geos = []
        # Кольцо тазобедренного шарнира под 45 градусов: подшипник с фасками и болтами.
        geos.append(hip_lathe([(HIP_RING_INNER, HIP_RING_BACK), (HIP_RING_OUTER, HIP_RING_BACK),
                (HIP_RING_OUTER, HIP_RING_FRONT - 0.004), (HIP_RING_OUTER - 0.004, HIP_RING_FRONT),
                (HIP_RING_INNER + 0.003, HIP_RING_FRONT), (HIP_RING_INNER, HIP_RING_FRONT - 0.003)], METAL, 16, closed=True))
        geos.append(hip_lathe(strap(-0.012, -0.002, HIP_RING_OUTER + 0.002, 0.004), DARK, 16, caps=False))
        for index in range(4):
            angle = math.tau * (index + 0.5) / 4
            base = hip + axis * (HIP_RING_FRONT - 0.001) + (across * math.cos(angle) + forward * math.sin(angle)) * 0.1035
            geos.append(shapes.rod(base, base + axis * 0.004, 0.0048, DARK, 5))
        # Гнездо с заглушкой и кабелями: видны, только когда нога отлетела.
        geos.append(hip_lathe([(0.0, -0.006), (HIP_RING_INNER, -0.006)], DARK, 14))
        geos.append(hip_lathe([(0.0, -0.006), (0.03, -0.006), (0.034, 0.0), (0.034, 0.012), (0.0, 0.012)], METAL, 10))
        for a, b, droop, tip in ((-0.045, 0.03, 0.06, GLOW), (0.03, -0.04, 0.045, None), (0.05, 0.03, 0.055, ALERT)):
            start = hip + axis * -0.004 + across * a + forward * b
            path = shapes.smooth_path([start, start + axis * 0.018, start + axis * 0.03 + Vector((0.0, 0.0, -droop * 0.4)),
                    start + axis * 0.034 + Vector((0.0, 0.0, -droop))], 1)
            geos.append(shapes.tube(path, 0.0045, RUBBER, 4))
            end = path[-1]
            geos.append(shapes.sphere(0.0065, end + Vector((0.0, 0.0, -0.004)), METAL if tip is None else tip, 5, 3))
        for geo in geos:
            if side < 0.0:
                geo.mirror_x()
            piece.add(geo, bone)


# ---------------------------------------------------------------------------------------------
# Рука
# ---------------------------------------------------------------------------------------------

# Кисть в перчатке. Рука висит вдоль тела: ладонь смотрит к бедру (-X у правой руки), тыльная
# сторона — наружу, большой палец — вперёд (+Y). Рукоять предмета проходит сквозь кулак вдоль Y.
# Координаты ниже — (смещение по X от оси руки, z) в плоскости сгиба пальцев.
KNUCKLE = (0.032, 0.819)                 # пястный сустав: нижний край ладони
FINGER_LENGTHS = (0.05, 0.031, 0.025)    # фаланги перчатки
# Пальцы от указательного к мизинцу: (y, масштаб длины, радиус, подъём костяшки).
FINGERS = (
    (0.0345, 0.97, 0.0112, 0.0),
    (0.0115, 1.05, 0.0116, -0.003),
    (-0.0115, 0.98, 0.0112, 0.0),
    (-0.0335, 0.82, 0.0102, 0.005),
)
# Расслабленная кисть: сгиб в каждом суставе, градусы (у мизинца пальцы подогнуты сильнее).
RELAXED_CURL = ((10.0, 22.0, 14.0), (14.0, 26.0, 16.0), (18.0, 30.0, 18.0), (24.0, 34.0, 20.0))
# Хват: палец проходит под рукоятью и поднимается с внутренней стороны (точки: сустав 2, сустав 3, кончик).
GRIP_CURL = ((-0.021, 0.8055), (-0.0315, 0.835), (-0.0235, 0.857))
# Указательный на спуске пистолета: вдоль рамки вниз и внутрь скобы.
TRIGGER_CURL = ((0.031, 0.782), (0.012, 0.764), (-0.008, 0.768))
THUMB_RADIUS = 0.0125
THUMB_PATHS = {
    "relaxed": ((0.02, 0.036, 0.886), (0.013, 0.058, 0.858), (0.006, 0.068, 0.828), (0.0, 0.069, 0.802)),
    # Поверх указательного пальца, вокруг рукояти.
    HAND_GRIP: ((0.012, 0.03, 0.894), (-0.021, 0.038, 0.887), (-0.037, 0.042, 0.866), (-0.04, 0.045, 0.84)),
    # Вдоль рамки пистолета, к стволу.
    HAND_TRIGGER: ((0.012, 0.03, 0.894), (-0.021, 0.037, 0.886), (-0.032, 0.039, 0.86), (-0.031, 0.04, 0.832)),
}
# Точки трубки пальца на каждой фаланге (доля длины) и толщина в них; суставы толще.
PHALANX_STOPS = (0.0, 0.3, 0.72)
PHALANX_RADII = ((1.1, 0.98, 0.97), (1.04, 0.93, 0.92), (0.97, 0.87, 0.85))
FINGERTIP_RADIUS = 0.8


def _finger_joints(index, pose):
    """Суставы пальца (костяшка, второй, третий, кончик) в координатах модели для правой руки."""
    y, scale, _, lift = FINGERS[index]
    knuckle = Vector((KNUCKLE[0], KNUCKLE[1] + lift))
    points = [knuckle]
    curl = TRIGGER_CURL if pose == HAND_TRIGGER and index == 0 else GRIP_CURL
    if pose == "relaxed":
        angle = 0.0
        for length, bend in zip(FINGER_LENGTHS, RELAXED_CURL[index]):
            angle += math.radians(bend)
            points.append(points[-1] + Vector((-math.sin(angle), -math.cos(angle))) * length * scale)
    else:
        # Первая фаланга огибает рукоять у всех пальцев одинаково, дальше палец короче или длиннее.
        second = Vector(curl[0]) + Vector((0.0, lift))
        points.append(second)
        for target in curl[1:]:
            points.append(second + (Vector(target) + Vector((0.0, lift)) - second) * scale)
    return [Vector((SHOULDER_X + px, y, pz)) for px, pz in points]


def _finger_path(joints):
    """Точки и толщины трубки пальца: по три кольца на фалангу и кончик."""
    # Трубка начинается внутри ладони, чтобы её открытый торец не было видно.
    path = [joints[0] + Vector((0.0, 0.0, 0.014))]
    radii = [1.0]
    for phalanx in range(3):
        start, end = joints[phalanx], joints[phalanx + 1]
        for stop, radius in zip(PHALANX_STOPS, PHALANX_RADII[phalanx]):
            path.append(start.lerp(end, stop))
            radii.append(radius)
    path.append(joints[3])
    radii.append(FINGERTIP_RADIUS)
    return path, radii


def hand_geos(detail=1.0, pose="relaxed"):
    """Правая кисть в перчатке в одной из поз HAND_POSES. Топология во всех позах одинаковая:
    позы хвата становятся формами (shape keys) поверх расслабленной кисти."""
    x = SHOULDER_X
    close_up = detail > 1.0
    sides = max(FINGER_SIDES, int(FINGER_SIDES * detail + 0.5))
    box_detail = (2, 3) if close_up else (1, 2)
    geos = []
    # Манжета перчатки и шар запястья под ней.
    geos.append(shapes.lathe([(0.0, WRIST_Z - 0.018), (0.04, WRIST_Z - 0.016), (0.05, WRIST_Z - 0.004), (0.052, WRIST_Z + 0.022),
            (0.047, WRIST_Z + 0.03), (0.0, WRIST_Z + 0.03)], GLOVE, int(LIMB_SEGMENTS * detail), center=(x, 0.0, 0.0)))
    # Ладонь, резиновая накладка на ней и жёсткая пластина на тыльной стороне (в цвет костюма).
    geos.append(shapes.box((0.03, 0.096, 0.094), (x + 0.035, 0.0, 0.866), GLOVE, 0.013, *box_detail))
    geos.append(shapes.box((0.006, 0.076, 0.064), (x + 0.0195, 0.0, 0.862), RUBBER, 0.0025, 1, 2))
    geos.append(shapes.box((0.012, 0.074, 0.056), (x + 0.053, -0.002, 0.874), SUIT, 0.005, *box_detail, wear=close_up))
    # Щиток костяшек.
    geos.append(shapes.box((0.012, 0.09, 0.02), (x + KNUCKLE[0] + 0.012, 0.0, KNUCKLE[1] + 0.007), RUBBER, 0.005, 1, 2))
    # Четыре пальца: три фаланги с утолщениями суставов, на кончиках — резиновые напальчники.
    for index, (y, _, radius, _) in enumerate(FINGERS):
        joints = _finger_joints(index, pose)
        path, radii = _finger_path(joints)
        geos.append(shapes.tube(path, radius, GLOVE, sides, caps=False, up=(0.0, 1.0, 0.0), radii=radii))
        tip = [joints[2].lerp(joints[3], share) for share in (0.42, 0.7, 1.0)]
        tip_radius = radius * PHALANX_RADII[2][2]
        geos.append(shapes.tube(tip, tip_radius * 1.07, RUBBER, sides, caps=False, up=(0.0, 1.0, 0.0), radii=(1.0, 1.0, 0.96)))
        geos.append(shapes.sphere(tip_radius * 1.03, joints[3], RUBBER, sides, 4))
    # Большой палец: две фаланги от подушечки у запястья.
    thumb = [Vector((x + px, py, pz)) for px, py, pz in THUMB_PATHS[pose]]
    path = [thumb[0], thumb[0].lerp(thumb[1], 0.5), thumb[1], thumb[1].lerp(thumb[2], 0.35), thumb[1].lerp(thumb[2], 0.75),
            thumb[2], thumb[2].lerp(thumb[3], 0.4), thumb[3]]
    thumb_up = (1.0, 0.0, 1.0)
    geos.append(shapes.tube(path, THUMB_RADIUS, GLOVE, sides, caps=False, up=thumb_up,
            radii=(1.3, 1.16, 1.08, 0.98, 0.97, 1.03, 0.9, 0.84)))
    tip = [thumb[2].lerp(thumb[3], share) for share in (0.35, 0.7, 1.0)]
    geos.append(shapes.tube(tip, THUMB_RADIUS * 0.94, RUBBER, sides, caps=False, up=thumb_up, radii=(1.0, 1.0, 0.95)))
    geos.append(shapes.sphere(THUMB_RADIUS * 0.9, thumb[3], RUBBER, sides, 4))
    geos.append(shapes.sphere(0.0185, thumb[0], GLOVE, sides + 2, 5))
    return geos


def _forearm_radius(z):
    return interpolate(((0.962, 0.054), (1.102, 0.064)), z)


def _upper_arm_radius(z):
    return interpolate(((1.186, 0.066), (1.306, 0.071)), z)


def arm_geos(detail=1.0, view=False):
    """Правая рука без кисти: список (кусок, роль), роль — "upper", "elbow" или "lower".
    view = True — вид от первого лица: плечо без шара, длиннее, локоть — шар-гофра."""
    x = SHOULDER_X
    segments = int(LIMB_SEGMENTS * detail)
    center = (x, 0.0, 0.0)
    parts = []
    if not view:
        # Шар плеча: гофрированный сустав под наплечником торса.
        parts.append((shapes.lathe(ribbed_ball(SHOULDER_BALL, SHOULDER_Z, 4), FABRIC, segments, center=center), "upper"))
        # Штекер шара: сидит в плечевом кольце торса, виден на отлетевшей руке.
        parts.append((lathe_x([(0.0, -0.112), (0.044, -0.112), (0.05, -0.106), (0.05, -0.088), (0.064, -0.086),
                (0.064, -0.07)], METAL, 12, (x, 0.0, SHOULDER_Z)), "upper"))
        parts.append((shapes.lathe(bellows(1.322, 1.372, 0.07, 0.009, 2, False), FABRIC, segments, center=center, caps=False), "upper"))
        top = 1.306
    else:
        # Срез плеча всегда за кадром.
        top = ELBOW_Z + VIEW_UPPER_LENGTH
        parts.append((shapes.lathe(ribbed_ball(0.066, ELBOW_Z, 4, 0.005), FABRIC, segments, center=center), "upper"))
    parts.append((shapes.lathe(band(1.302, 1.326, 0.076, 0.02), METAL, segments, center=center, closed=True), "upper"))
    parts.append((shapes.lathe(plate(1.186, top, 0.066, 0.071), SUIT, segments, center=center, wear=PLATE_WEAR), "upper"))
    # Накладка на плече снаружи (на ней нашивка) и щиток локтя сзади.
    surface = cylinder_surface(x, _upper_arm_radius, 0.0, 46.0, 1.248, 0.05)
    for geo in armor_plate(surface, SUIT, 0.006, 14):
        parts.append((geo, "upper"))
    elbow_pad = cylinder_surface(x, lambda z: 0.065, 270.0, 50.0, ELBOW_Z + 0.004, 0.042)
    for geo in armor_plate(elbow_pad, WHITE, 0.008, 12, 3.2, crown=0.003):
        parts.append((geo, "upper"))
    if not view:
        parts.append((shapes.lathe(bellows(1.096, 1.19, 0.062, 0.009, 4), FABRIC, segments, center=center, caps=False),
                "elbow"))
    parts.append((shapes.lathe(plate(0.962, 1.102, 0.054, 0.064), SUIT, segments, center=center, wear=PLATE_WEAR), "lower"))
    # Запястное кольцо с замком.
    parts.append((shapes.lathe(band(0.93, 0.966, 0.058, 0.024), METAL, segments, center=center, closed=True), "lower"))
    parts.append((shapes.lathe(strap(0.941, 0.955, 0.0595, 0.004), DARK, segments, center=center, caps=False), "lower"))
    parts.append((shapes.box((0.016, 0.026, 0.03), (x + 0.058, 0.0, 0.948), DARK, 0.004, 1, 1), "lower"))
    # Бронепластина предплечья снаружи, на ней пульт.
    surface = cylinder_surface(x, _forearm_radius, 0.0, 62.0, 1.034, 0.058)
    for geo in armor_plate(surface, SUIT, 0.006, 14, bolts=((-0.74, -0.74), (0.74, -0.74)) if detail > 1.0 else ()):
        parts.append((geo, "lower"))
    parts.append((shapes.box((0.014, 0.05, 0.076), (x + 0.064, 0.004, 1.036), DARK, 0.005, 1, 2), "lower"))
    for row in range(3):
        parts.append((shapes.box((0.004, 0.009, 0.007), (x + 0.0715, -0.01 + row * 0.014, 1.012), GLOW if row == 0 else METAL,
                0.0015, 1, 1), "lower"))
    return parts


def arm_screen(side):
    """Экранчик пульта на предплечье (строится для своей стороны, чтобы надпись не зеркалилась)."""
    return shapes.quad((side * (SHOULDER_X + 0.0715), 0.004, 1.044), (side, 0, 0), (0, 0, 1), 0.038, 0.0285, SCREEN,
            decal_uv("screen"))


def add_hand(piece, weights, side, detail=1.0, matrix=None):
    """Добавляет в меш кисть со всеми формами хвата. matrix — общее преобразование (вид от первого лица)."""
    poses = {pose: hand_geos(detail, pose) for pose in HAND_POSES}
    for index, geo in enumerate(poses["relaxed"]):
        morphs = {}
        for pose in HAND_POSES[1:]:
            other = poses[pose][index]
            if any((a - b).length > 1.0e-7 for a, b in zip(geo.verts, other.verts)):
                morphs[pose] = other
        for item in [geo] + list(morphs.values()):
            if side < 0.0:
                item.mirror_x()
            if matrix is not None:
                item.transform(matrix)
        piece.add(geo, weights, morphs)


def build_arm(piece, prefix, side):
    weights = {
        "upper": shapes.rigid(prefix + "UpperArm"),
        "elbow": shapes.blend_z(prefix + "UpperArm", prefix + "LowerArm", ELBOW_Z + 0.04, ELBOW_Z - 0.04),
        "lower": shapes.rigid(prefix + "LowerArm"),
    }
    for geo, role in arm_geos():
        if side < 0.0:
            geo.mirror_x()
        piece.add(geo, weights[role])
    piece.add(arm_screen(side), weights["lower"])
    add_hand(piece, shapes.rigid(prefix + "Hand"), side)
    # Нашивки на накладке плеча: эмблема отдела слева, шеврон справа.
    axis = (SHOULDER_X * side, 0.0)
    radius = _upper_arm_radius(1.248) + 0.0075
    if side < 0.0:
        piece.add(shapes.arc_quad(axis, radius, 180.0, 1.248, 0.066, 0.066, DECAL, decal_uv("patch"), 5), weights["upper"])
    else:
        piece.add(shapes.arc_quad(axis, radius, 0.0, 1.248, 0.072, 0.045, DECAL, decal_uv("chevron"), 5), weights["upper"])


# ---------------------------------------------------------------------------------------------
# Нога
# ---------------------------------------------------------------------------------------------

def _boot_outline(count, grow=1.0):
    """Контур подошвы вокруг оси голени: шире у пальцев, пятка сзади."""
    points = []
    for px, py in shapes.superellipse(0.058, 0.15, count, 2.5, (0.0, 0.06)):
        t = min(max((py + 0.05) / 0.17, 0.0), 1.0)
        widen = 1.0 + 0.16 * t * t * (3.0 - 2.0 * t)
        points.append((px * widen * grow, 0.06 + (py - 0.06) * grow))
    return points


def boot_geos(detail=1.0):
    x = HIP_X
    count = 20
    geos = []
    sole = [shapes.section(_boot_outline(count, 0.97), 0.004), shapes.section(_boot_outline(count, 1.03), 0.01),
            shapes.section(_boot_outline(count, 1.045), 0.034), shapes.section(_boot_outline(count, 1.0), 0.042)]
    geos.append(shapes.loft(sole, RUBBER).move((x, 0.0, 0.0)))
    # Протектор: поперечные грунтозацепы.
    for index in range(3):
        y = -0.05 + index * 0.105
        width = 0.084 if index < 1 else 0.1
        geos.append(shapes.box((width, 0.024, 0.01), (x, y, 0.005), RUBBER, 0.003, 1, 1))
    # Верх ботинка: контур подошвы плавно стягивается к голенищу.
    ankle = shapes.superellipse(0.068, 0.072, count, 2.0)
    foot = _boot_outline(count, 0.97)
    upper = []
    for z, share in ((0.036, 0.0), (0.066, 0.03), (0.088, 0.3), (0.106, 0.62), (0.124, 0.88), (0.14, 1.0), (0.152, 1.0)):
        upper.append([(fx + (ax - fx) * share, fy + (ay - fy) * share, z) for (fx, fy), (ax, ay) in zip(foot, ankle)])
    geos.append(shapes.loft(upper, BOOT).move((x, 0.0, 0.0)))
    # Накладка на носке и ремни через подъём.
    front = [index for index, (_, fy) in enumerate(foot) if fy >= 0.118]
    toe = []
    for z, share in ((0.036, 0.0), (0.064, 0.03), (0.084, 0.26)):
        ring = []
        for index in front:
            (fx, fy), (ax, ay) = foot[index], ankle[index]
            ring.append(((fx + (ax - fx) * share) * 1.035, (fy + (ay - fy) * share) * 1.014, z))
        toe.append(ring)
    geos.append(shapes.loft(toe, RUBBER).move((x, 0.0, 0.0)))
    instep = shapes.smooth_path([(-0.072, 0.14, 0.038), (-0.06, 0.14, 0.084), (0.0, 0.138, 0.107), (0.06, 0.14, 0.084),
            (0.072, 0.14, 0.038)], 2)
    geos.append(shapes.tube(instep, 0.013, FABRIC, 6, squash=0.3, up=(0.0, 1.0, 0.0)).move((x, 0.0, 0.0)))
    geos.append(shapes.box((0.026, 0.022, 0.009), (x + 0.034, 0.139, 0.1), METAL, 0.003, 1, 1))
    # Ремень вокруг голенища с пряжкой спереди.
    geos.append(shapes.lathe(strap(0.126, 0.146, 0.076), FABRIC, 16, (1.0, 1.05), center=(x, 0.0, 0.0), caps=False))
    geos.append(shapes.box((0.028, 0.01, 0.022), (x, 0.08, 0.136), METAL, 0.003, 1, 1))
    return geos


# Радиус жёстких сегментов ноги по высоте: бедро сужается к колену, голень — к щиколотке.
THIGH_RADII = ((0.598, 0.081), (0.64, 0.086), (0.7, 0.093), (THIGH_TOP_Z, 0.098))
SHIN_RADII = ((0.2, 0.064), (0.26, 0.07), (0.34, 0.08), (0.4, 0.083), (0.436, 0.081))


def _thigh_radius(z):
    return interpolate(THIGH_RADII, z)


def _shin_radius(z):
    return interpolate(SHIN_RADII, z)


def _thigh_ring(z, radius, count, shift=0.0):
    """Горизонтальное сечение бедра: начало обхода там же, где у hip_circle (наружу)."""
    return [Vector((HIP_X + radius * math.cos(math.tau * index / count), shift + radius * THIGH_SQUASH * math.sin(math.tau * index / count), z))
            for index in range(count)]


def leg_geos(detail=1.0):
    """Правая нога: список (кусок, роль), роль — "upper", "knee", "lower", "ankle" или "foot"."""
    x = HIP_X
    segments = int(LIMB_SEGMENTS * detail)
    center = (x, 0.0, 0.0)
    hip = (HIP_X, 0.0, HIP_Z)
    parts = []
    # Верх ноги входит в кольцо таза под 45 градусов: штекер (виден на отлетевшей ноге), гофра,
    # кольцо ноги и жёсткое бедро, которое от наклонного среза переходит к обычной трубе.
    parts.append((hip_lathe([(0.0, -0.016), (0.044, -0.016), (0.05, -0.01), (0.05, 0.004), (0.088, 0.006), (0.088, 0.01)],
            METAL, segments, caps=False), "upper"))
    collar = [hip_circle(offset, radius, segments) for offset, radius in ((0.008, 0.088), (0.016, 0.0935), (0.025, 0.088),
            (HIP_COLLAR_END, 0.0935))]
    parts.append((face_outward(shapes.loft(collar, FABRIC, False, False), hip), "upper"))
    parts.append((hip_lathe(band(HIP_COLLAR_END, HIP_RACE_END, 0.099, 0.02), METAL, segments, closed=True), "upper"))
    shell = [hip_circle(HIP_RACE_END - 0.002, 0.09, segments), hip_circle(HIP_RACE_END + 0.002, 0.096, segments),
            hip_circle(HIP_RACE_END + 0.012, 0.0965, segments)]
    for z in (THIGH_TOP_Z, 0.7, 0.64, 0.602):
        shell.append(_thigh_ring(z, _thigh_radius(z), segments))
    shell += [_thigh_ring(0.598, 0.085, segments), _thigh_ring(0.582, 0.085, segments), _thigh_ring(0.578, 0.07, segments)]
    thigh = face_outward(shapes.loft(shell, SUIT, False, False), (x + 0.03, 0.0, 0.75))
    parts.append((mark_wear(thigh, segments, (1, 7)), "upper"))
    # Бронепластина бедра спереди с болтами и карман снаружи.
    surface = cylinder_surface(x, _thigh_radius, 90.0, 50.0, 0.69, 0.078, THIGH_SQUASH)
    for geo in armor_plate(surface, SUIT, 0.0075, 16, bolts=((-0.72, 0.74), (0.72, 0.74), (-0.72, -0.74), (0.72, -0.74))):
        parts.append((geo, "upper"))
    parts.append((shapes.box((0.014, 0.075, 0.1), (x + 0.094, -0.004, 0.69), FABRIC, 0.006, 1, 2), "upper"))
    parts.append((shapes.box((0.016, 0.079, 0.03), (x + 0.095, -0.004, 0.732), BOOT, 0.005, 1, 2), "upper"))
    parts.append((shapes.lathe(bellows(0.43, 0.582, 0.08, 0.011, 4), FABRIC, segments, center=center, caps=False), "knee"))
    # Наколенник: жёсткий щиток спереди на двух ремнях, держится на бедре.
    guard = cylinder_surface(x, lambda z: 0.084, 90.0, 56.0, KNEE_Z + 0.012, 0.06)
    for geo in armor_plate(guard, WHITE, 0.011, 16, 3.4, crown=0.003):
        parts.append((geo, "upper"))
    for z in (0.553, 0.462):
        parts.append((shapes.lathe(strap(z, z + 0.018, 0.0855), BOOT, segments, (1.0, 1.04), center=center, caps=False), "upper"))
    calf = lambda angle: 1.0 + 0.12 * max(-math.sin(angle), 0.0)
    shin = [(0.052, 0.2), (0.068, 0.203), (0.068, 0.216), (0.064, 0.22)]
    shin += [(_shin_radius(z), z) for z in (0.26, 0.34, 0.4)]
    shin += [(0.081, 0.416), (0.085, 0.42), (0.085, 0.433), (0.07, 0.436)]
    parts.append((shapes.lathe(shin, SUIT, segments, center=center, radius_scale=calf, wear=(1, 8)), "lower"))
    # Щиток голени спереди.
    surface = cylinder_surface(x, _shin_radius, 90.0, 40.0, 0.32, 0.085)
    for geo in armor_plate(surface, SUIT, 0.007, 14):
        parts.append((geo, "lower"))
    parts.append((shapes.lathe(band(0.176, 0.204, 0.072, 0.02), METAL, segments, center=center, closed=True), "lower"))
    parts.append((shapes.box((0.026, 0.014, 0.022), (x, 0.074, 0.19), DARK, 0.004, 1, 1), "lower"))
    parts.append((shapes.lathe(bellows(0.128, 0.18, 0.066, 0.008, 2, False), FABRIC, segments, center=center, caps=False), "ankle"))
    for geo in boot_geos(detail):
        parts.append((geo, "foot"))
    return parts


def build_leg(piece, prefix, side):
    weights = {
        "upper": shapes.rigid(prefix + "UpperLeg"),
        "knee": shapes.blend_z(prefix + "UpperLeg", prefix + "LowerLeg", KNEE_Z + 0.05, KNEE_Z - 0.05),
        "lower": shapes.rigid(prefix + "LowerLeg"),
        "ankle": shapes.blend_z(prefix + "LowerLeg", prefix + "Foot", 0.17, 0.135),
        "foot": shapes.rigid(prefix + "Foot"),
    }
    for geo, role in leg_geos():
        if side < 0.0:
            geo.mirror_x()
        piece.add(geo, weights[role])
    # Надпись на бедре сзади-сбоку — на обеих ногах читается слева направо.
    piece.add(shapes.arc_quad((HIP_X * side, 0.0), _thigh_radius(0.75) + 0.0015, -90.0 - side * 50.0, 0.75, 0.13, 0.0244, DECAL,
            decal_uv("serial"), 6, (1.0, THIGH_SQUASH)), weights["upper"])


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

    bone("Hips", (0.0, 0.0, HIP_Z), (0.0, 0.0, PELVIS_TOP_Z))
    bone("Spine", (0.0, 0.0, PELVIS_TOP_Z), (0.0, 0.0, 1.2), "Hips")
    bone("Chest", (0.0, 0.0, 1.2), (0.0, 0.0, SHOULDER_Z), "Spine")
    bone("Neck", (0.0, 0.0, SHOULDER_Z), (0.0, 0.0, NECK_Z), "Chest")
    bone("Head", (0.0, 0.0, NECK_Z), (0.0, 0.0, HEAD_CENTER.z + HEAD_RADII.z), "Neck")
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


# ---------------------------------------------------------------------------------------------
# Сборка файлов
# ---------------------------------------------------------------------------------------------

def build_body(path):
    shapes.reset_scene()
    make_materials()
    armature = build_armature()
    pieces = []
    for name, builder in (("HeadPiece", build_head), ("VisorGlass", build_visor), ("FacePlate", build_face),
            ("TorsoPiece", build_torso), ("PelvisPiece", build_pelvis)):
        piece = Piece(name)
        builder(piece)
        pieces.append(piece)
    for prefix, side in (("Left", -1.0), ("Right", 1.0)):
        arm = Piece("Arm" + prefix)
        build_arm(arm, prefix, side)
        leg = Piece("Leg" + prefix)
        build_leg(leg, prefix, side)
        pieces += [arm, leg]
    for piece in pieces:
        shapes.build_object(piece, armature, occlusion=piece.name not in ("VisorGlass", "FacePlate"),
                smooth_angle=ARM_SMOOTH_ANGLE_DEG if piece.name.startswith("Arm") else shapes.SMOOTH_ANGLE_DEG)
    shapes.report()
    shapes.export_glb(path)


def build_view_arms(path):
    """Руки для вида от первого лица: кисть, предплечье и плечо — отдельные жёсткие меши.
    Оси звена: «вдоль руки вниз» -> +Y Blender (в Godot -Z, от камеры), «перёд тела» -> +Z (вверх)."""
    shapes.reset_scene()
    make_materials()
    turn = Matrix.Rotation(math.radians(90.0), 4, "X")
    for suffix, side in (("Right", 1.0), ("Left", -1.0)):
        # Кисть: начало координат — точка хвата.
        hand = Piece("Arm" + suffix)
        add_hand(hand, None, side, VIEW_DETAIL, turn @ Matrix.Translation((-SHOULDER_X * side, 0.0, -GRIP_Z)))
        # Предплечье (начало — центр запястья) и плечо (начало — центр локтя).
        forearm = Piece("Forearm" + suffix)
        upper = Piece("Upper" + suffix)
        to_wrist = turn @ Matrix.Translation((-SHOULDER_X * side, 0.0, -VIEW_WRIST_Z))
        to_elbow = turn @ Matrix.Translation((-SHOULDER_X * side, 0.0, -ELBOW_Z))
        slim = (VIEW_SLEEVE_SCALE, VIEW_SLEEVE_SCALE, 1.0)
        geos = [(geo, role) for geo, role in arm_geos(VIEW_DETAIL, True)]
        # Шар запястья закрывает стык предплечья с перчаткой при любом сгибе.
        geos.append((shapes.sphere(0.058, (SHOULDER_X, 0.0, VIEW_WRIST_Z), GLOVE, int(LIMB_SEGMENTS * VIEW_DETAIL), 8), "lower"))
        for geo, role in geos:
            geo.scale(slim, (SHOULDER_X, 0.0, 0.0))
            if side < 0.0:
                geo.mirror_x()
            if role == "upper":
                upper.add(geo.transform(to_elbow))
            else:
                forearm.add(geo.transform(to_wrist))
        screen = arm_screen(1.0).scale(slim, (SHOULDER_X, 0.0, 0.0))
        if side < 0.0:
            # Зеркальная копия экранчика с незеркальной надписью.
            screen.mirror_x()
            screen.uvs = [[uv[1], uv[0], uv[3], uv[2]] for uv in screen.uvs]
        forearm.add(screen.transform(to_wrist))
        shapes.build_object(hand, smooth_angle=ARM_SMOOTH_ANGLE_DEG)
        shapes.build_object(forearm)
        shapes.build_object(upper)
    shapes.report()
    shapes.export_glb(path)


def main():
    args = shapes.script_args()
    out_dir = os.path.abspath(args[0] if args else DEFAULT_OUT_DIR)
    os.makedirs(out_dir, exist_ok=True)
    build_body(os.path.join(out_dir, BODY_FILE))
    build_view_arms(os.path.join(out_dir, ARM_FILE))


main()
