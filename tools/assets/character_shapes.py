"""Конструктор геометрии для генераторов персонажа и оружия (character.py, weapons.py).

Всё строится «на бумаге», обычными списками Python, и только в конце превращается в меш Blender:
так результат не зависит от операторов bpy и получается одинаковым при каждом запуске.

- Geo               кусок геометрии: вершины, грани, UV по углам граней, материал, пометки
                    «кромка с износом»;
- lathe, sphere, loft, box, cuboid, extrude, tube, rod, dome, quad, arc_quad   генераторы кусков;
- wear_shell        оболочка-наклейка поверх помеченных кромок: сколы краски до металла;
- Piece             один меш модели: набор Geo с привязкой к костям и формами (shape keys);
- build_object      Piece -> объект Blender (UV, веса, формы, затенение в цвете вершин);
- make_material     простой Principled BSDF (в Godot его заменяет внешний материал по имени).

Оси Blender: X — вправо, Y — вперёд (перёд модели), Z — вверх. Грани смотрят наружу, если
контуры заданы против часовой стрелки при взгляде навстречу направлению построения.

UV: у тел вращения и труб развёртка цилиндрическая (U — вокруг, V — вдоль), у остального —
проекция по главной оси нормали («коробкой»). Плотность — UV_SCALE[материал] тайлов на метр.
"""

import math
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# Сколько раз тайловая текстура материала повторяется на метре поверхности.
UV_SCALE = {}
DEFAULT_UV_SCALE = 4.0
# Рёбра острее этого угла остаются жёсткими, остальное сглаживается.
SMOOTH_ANGLE_DEG = 40.0

# Затенение в цвете вершин: лучи из каждой вершины в полусферу, только по своему куску.
AO_RAYS = 20
AO_DISTANCE = 0.09
AO_STRENGTH = 0.85
AO_FLOOR = 0.3
AO_BIAS = 0.003
AO_LEVELS = 255.0

# Сколы краски: помеченные кромки дублируются оболочкой с этим материалом (отсечение по альфе),
# приподнятой над поверхностью на WEAR_LIFT.
# Коробки со скруглением меньше этого строятся простым параллелепипедом.
MIN_BOX_BEVEL = 0.0026
WEAR_MATERIAL = "SuitChips"
WEAR_LIFT = 0.0006


def script_args():
    """Аргументы после "--" в командной строке Blender."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def uv_scale(mat):
    return UV_SCALE.get(mat, DEFAULT_UV_SCALE)


def hex_color(value):
    """"ffd23f" -> (r, g, b) в линейном пространстве, как ждёт Blender."""
    value = value.lstrip("#")
    srgb = [int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


def make_material(name, color, roughness=0.5, metallic=0.0, emission=None, emission_strength=1.0):
    """Материал-заглушка с нужным именем: в Godot его подменяет ресурс из resources/materials."""
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*hex_color(color), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*hex_color(emission), 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


# ---------------------------------------------------------------------------------------------
# Geo
# ---------------------------------------------------------------------------------------------

class Geo:
    """Кусок геометрии. uvs[i] — список (u, v) по углам грани i или None (проекция «коробкой»)."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.uvs = []
        self.mats = []
        self.wear = []          # по граням: True — кромка, на которой облезает краска

    def add_vert(self, co):
        self.verts.append(Vector(co))
        return len(self.verts) - 1

    def add_face(self, indices, mat, uv=None, wear=False):
        self.faces.append(tuple(indices))
        self.mats.append(mat)
        self.uvs.append(uv)
        self.wear.append(wear)

    def merge(self, other):
        base = len(self.verts)
        self.verts.extend(v.copy() for v in other.verts)
        self.faces.extend(tuple(i + base for i in face) for face in other.faces)
        self.uvs.extend(other.uvs)
        self.mats.extend(other.mats)
        self.wear.extend(other.wear)
        return self

    def scale(self, factors, pivot=(0.0, 0.0, 0.0)):
        pivot = Vector(pivot)
        return self.transform(Matrix.Translation(pivot) @ Matrix.Diagonal((*factors, 1.0)) @ Matrix.Translation(-pivot))

    def paint(self, mat):
        """Перекрашивает весь кусок в другой материал."""
        self.mats = [mat] * len(self.mats)
        return self

    def transform(self, matrix):
        self.verts = [matrix @ v for v in self.verts]
        if matrix.determinant() < 0.0:
            self.faces = [tuple(reversed(face)) for face in self.faces]
            self.uvs = [None if uv is None else list(reversed(uv)) for uv in self.uvs]
        return self

    def move(self, offset):
        return self.transform(Matrix.Translation(Vector(offset)))

    def rotate(self, axis, degrees, pivot=(0.0, 0.0, 0.0)):
        pivot = Vector(pivot)
        return self.transform(Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(degrees), 4, axis)
                @ Matrix.Translation(-pivot))

    def mirror_x(self):
        return self.transform(Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)))

    def flip(self):
        self.faces = [tuple(reversed(face)) for face in self.faces]
        self.uvs = [None if uv is None else list(reversed(uv)) for uv in self.uvs]
        return self

    def orient_outward(self):
        """Для замкнутой оболочки: разворачивает грани наружу (по знаку объёма)."""
        volume = 0.0
        for face in self.faces:
            first = self.verts[face[0]]
            for index in range(1, len(face) - 1):
                volume += first.dot(self.verts[face[index]].cross(self.verts[face[index + 1]]))
        return self.flip() if volume < 0.0 else self


def combine(geos):
    result = Geo()
    for geo in geos:
        result.merge(geo)
    return result


# ---------------------------------------------------------------------------------------------
# Контуры
# ---------------------------------------------------------------------------------------------

def superellipse(a, b, count=24, power=2.0, center=(0.0, 0.0)):
    """Контур суперэллипса (power = 2 — эллипс, больше — ближе к прямоугольнику), против часовой."""
    points = []
    for index in range(count):
        angle = math.tau * index / count
        c, s = math.cos(angle), math.sin(angle)
        points.append((center[0] + a * math.copysign(abs(c) ** (2.0 / power), c),
                center[1] + b * math.copysign(abs(s) ** (2.0 / power), s)))
    return points


def rounded_rect(width, height, radius, corner_segments=3, center=(0.0, 0.0)):
    """Контур прямоугольника со скруглёнными углами, против часовой стрелки."""
    radius = max(min(radius, width * 0.5 - 1.0e-5, height * 0.5 - 1.0e-5), 1.0e-5)
    points = []
    corners = (
        (width * 0.5 - radius, height * 0.5 - radius, 0.0),
        (-width * 0.5 + radius, height * 0.5 - radius, 90.0),
        (-width * 0.5 + radius, -height * 0.5 + radius, 180.0),
        (width * 0.5 - radius, -height * 0.5 + radius, 270.0),
    )
    for corner_a, corner_b, start in corners:
        for step in range(corner_segments + 1):
            angle = math.radians(start + 90.0 * step / corner_segments)
            points.append((center[0] + corner_a + radius * math.cos(angle),
                    center[1] + corner_b + radius * math.sin(angle)))
    return points


def inset_outline(points, distance):
    """Сдвигает контур (против часовой) внутрь на distance — для фасок выдавленных пластин."""
    count = len(points)
    result = []
    for index in range(count):
        previous = Vector(points[index - 1])
        current = Vector(points[index])
        following = Vector(points[(index + 1) % count])
        edge_in = (current - previous).normalized()
        edge_out = (following - current).normalized()
        normal_in = Vector((-edge_in.y, edge_in.x))
        normal_out = Vector((-edge_out.y, edge_out.x))
        miter = normal_in + normal_out
        miter /= max(1.0 + normal_in.dot(normal_out), 0.35)
        result.append((current.x + miter.x * distance, current.y + miter.y * distance))
    return result


def ball_profile(radius, center_z, rings=6, squash_z=1.0):
    """Профиль шара для lathe (снизу вверх)."""
    points = []
    for index in range(rings + 1):
        angle = math.pi * index / rings - math.pi * 0.5
        points.append((0.0 if index in (0, rings) else radius * math.cos(angle),
                center_z + radius * squash_z * math.sin(angle)))
    return points


def smooth_path(points, subdivisions=3):
    """Сглаживает ломаную сплайном Катмулла — Рома."""
    points = [Vector(p) for p in points]
    result = []
    for index in range(len(points) - 1):
        p0 = points[max(index - 1, 0)]
        p1 = points[index]
        p2 = points[index + 1]
        p3 = points[min(index + 2, len(points) - 1)]
        for step in range(subdivisions):
            t = step / subdivisions
            result.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
                    + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
    result.append(points[-1])
    return result


# ---------------------------------------------------------------------------------------------
# Генераторы
# ---------------------------------------------------------------------------------------------

def lathe(profile, mat, segments=16, squash=(1.0, 1.0), caps=True, closed=False, center=(0.0, 0.0, 0.0),
        radius_scale=None, wear=(), box_uv=False):
    """Тело вращения вокруг Z. profile = [(радиус, z), ...] снизу вверх (радиус 0 на конце —
    полюс). closed = True замыкает профиль в кольцо (тор): тогда он идёт против часовой
    стрелки в плоскости (радиус, z). squash = (x, y) сплющивает сечение.
    radius_scale(угол) -> множитель радиуса: некруглые сечения (икра, бедро).
    wear — номера отрезков профиля (по нижней точке), на которых облезает краска.
    box_uv = True — развёртка «коробкой» вместо цилиндрической: у шаров и куполов нет полюса,
    к которому сходился бы рисунок текстуры."""
    geo = Geo()
    scale = uv_scale(mat)
    reference = max(radius for radius, _ in profile) * max(squash)
    tiles = max(1, round(math.tau * reference * scale))
    rings = []
    lengths = [0.0]
    for index in range(1, len(profile)):
        step = Vector(profile[index]) - Vector(profile[index - 1])
        lengths.append(lengths[-1] + step.length)
    if closed:
        lengths.append(lengths[-1] + (Vector(profile[0]) - Vector(profile[-1])).length)
    for radius, z in profile:
        if radius <= 1.0e-6:
            rings.append([geo.add_vert((0.0, 0.0, z))])
            continue
        ring = []
        for index in range(segments):
            angle = math.tau * index / segments
            factor = radius if radius_scale is None else radius * radius_scale(angle)
            ring.append(geo.add_vert((factor * math.cos(angle) * squash[0], factor * math.sin(angle) * squash[1], z)))
        rings.append(ring)
    pairs = list(zip(range(len(rings) - 1), range(1, len(rings))))
    if closed:
        pairs.append((len(rings) - 1, 0))
    for lower_index, upper_index in pairs:
        lower, upper = rings[lower_index], rings[upper_index]
        v0 = lengths[lower_index] * scale
        v1 = lengths[lower_index + 1] * scale
        worn = lower_index in wear
        if len(lower) == 1 and len(upper) == 1:
            continue
        for index in range(segments):
            following = (index + 1) % segments
            u0 = index / segments * tiles
            u1 = (index + 1) / segments * tiles
            if len(lower) == 1:
                geo.add_face((lower[0], upper[following], upper[index]), mat,
                        None if box_uv else [((u0 + u1) * 0.5, v0), (u1, v1), (u0, v1)], worn)
            elif len(upper) == 1:
                geo.add_face((lower[index], lower[following], upper[0]), mat,
                        None if box_uv else [(u0, v0), (u1, v0), ((u0 + u1) * 0.5, v1)], worn)
            else:
                geo.add_face((lower[index], lower[following], upper[following], upper[index]), mat,
                        None if box_uv else [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], worn)
    if caps and not closed:
        if len(rings[0]) > 1:
            geo.add_face(tuple(reversed(rings[0])), mat)
        if len(rings[-1]) > 1:
            geo.add_face(tuple(rings[-1]), mat)
    if closed or ((caps or len(rings[0]) == 1) and (caps or len(rings[-1]) == 1)):
        geo.orient_outward()
    return geo.move(center)


def sphere(radius, center, mat, segments=16, rings=8, squash=(1.0, 1.0, 1.0)):
    geo = lathe(ball_profile(radius, 0.0, rings, squash[2]), mat, segments, (squash[0], squash[1]), box_uv=True)
    return geo.move(center)


def loft(sections, mat, cap_start=True, cap_end=True):
    """Оболочка по сечениям: sections — списки точек одинаковой длины; контуры идут против
    часовой стрелки, если смотреть навстречу направлению от первого сечения к последнему."""
    geo = Geo()
    count = len(sections[0])
    rings = [[geo.add_vert(point) for point in section] for section in sections]
    for lower, upper in zip(rings, rings[1:]):
        for index in range(count):
            following = (index + 1) % count
            geo.add_face((lower[index], lower[following], upper[following], upper[index]), mat)
    if cap_start:
        geo.add_face(tuple(reversed(rings[0])), mat)
    if cap_end:
        geo.add_face(tuple(rings[-1]), mat)
    if cap_start and cap_end:
        geo.orient_outward()
    return geo


def section(outline, z):
    """Плоский контур [(x, y), ...] -> сечение на высоте z."""
    return [(x, y, z) for x, y in outline]


def box(size, center, mat, bevel=0.01, segments=2, corner_segments=3, wear=False):
    """Параллелепипед со скруглёнными рёбрами. wear = True — на скруглениях облезает краска."""
    width, depth, height = size
    bevel = min(bevel, width * 0.49, depth * 0.49, height * 0.49)
    if bevel < MIN_BOX_BEVEL:
        # Скругление меньше пары миллиметров в игре не видно: хватит шести граней.
        return cuboid(size, center, mat)
    sections = []
    levels = []
    for step in range(segments + 1):
        angle = math.pi * 0.5 * step / segments
        levels.append((-height * 0.5 + bevel * (1.0 - math.cos(angle)), bevel * (1.0 - math.sin(angle))))
    levels += [(-z, inset) for z, inset in reversed(levels)]
    for z, inset in levels:
        outline = rounded_rect(width - 2.0 * inset, depth - 2.0 * inset, max(bevel - inset, 1.0e-4), corner_segments)
        sections.append(section(outline, z))
    geo = loft(sections, mat)
    if wear:
        # Грани loft идут поясами между сечениями; плоские — только в среднем поясе между углами.
        count = len(sections[0])
        for band in range(len(sections) - 1):
            for index in range(count):
                flat = band == segments and index % (corner_segments + 1) == corner_segments
                geo.wear[band * count + index] = not flat
    return geo.move(center)


def cuboid(size, center, mat):
    """Простой параллелепипед из шести граней: мелкие детали, которым скругления не нужны."""
    geo = Geo()
    half = Vector(size) * 0.5
    for sz in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            for sx in (-1.0, 1.0):
                geo.add_vert((center[0] + sx * half.x, center[1] + sy * half.y, center[2] + sz * half.z))
    for face in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
        geo.add_face(face, mat)
    return geo


def extrude(outline, depth, mat, plane="XZ", bevel=0.0, center=0.0, wear=False):
    """Плоский контур [(a, b), ...] (против часовой), выдавленный на depth с фаской bevel.
    plane "XZ": a -> X, b -> Z, толщина по Y; "YZ": a -> Y, b -> Z, толщина по X;
    "XY": a -> X, b -> Y, толщина по Z. center — положение середины толщины на этой оси."""
    half = depth * 0.5
    area = sum(a0 * b1 - a1 * b0 for (a0, b0), (a1, b1) in zip(outline, outline[1:] + outline[:1]))
    if area < 0.0:
        outline = list(reversed(outline))
    if bevel > 0.0:
        inner = inset_outline(outline, bevel)
        layers = [(inner, -half), (outline, -half + bevel), (outline, half - bevel), (inner, half)]
    else:
        layers = [(outline, -half), (outline, half)]
    if plane == "XZ":
        # X x Z = -Y: контур смотрит назад, поэтому строим от +Y к -Y.
        sections = [[(a, center - t, b) for a, b in points] for points, t in layers]
    elif plane == "YZ":
        sections = [[(center + t, a, b) for a, b in points] for points, t in layers]
    else:
        sections = [[(a, b, center + t) for a, b in points] for points, t in layers]
    geo = loft(sections, mat)
    if wear and bevel > 0.0:
        count = len(outline)
        for band in (0, 2):
            for index in range(count):
                geo.wear[band * count + index] = True
    return geo


def tube(path, radius, mat, sides=8, caps=True, radius_fn=None, squash=1.0, up=(0.0, 0.0, 1.0), radii=None):
    """Труба вдоль ломаной path. radius_fn(доля длины 0..1) -> множитель радиуса (гофра, сужение);
    radii — множитель радиуса для каждой точки пути (вместо radius_fn);
    squash < 1 сплющивает сечение вдоль второй оси (ремни)."""
    geo = Geo()
    path = [Vector(p) for p in path]
    scale = uv_scale(mat)
    tiles = max(1, round(math.tau * radius * scale))
    lengths = [0.0]
    for index in range(1, len(path)):
        lengths.append(lengths[-1] + (path[index] - path[index - 1]).length)
    total = max(lengths[-1], 1.0e-9)
    tangents = []
    for index in range(len(path)):
        before = path[max(index - 1, 0)]
        after = path[min(index + 1, len(path) - 1)]
        tangents.append((after - before).normalized())
    normal = Vector(up) - tangents[0] * Vector(up).dot(tangents[0])
    if normal.length < 1.0e-4:
        normal = Vector((1.0, 0.0, 0.0)) - tangents[0] * tangents[0].x
    normal.normalize()
    rings = []
    for index, point in enumerate(path):
        tangent = tangents[index]
        normal = (normal - tangent * normal.dot(tangent)).normalized()
        binormal = tangent.cross(normal)
        factor = radius if radius_fn is None else radius * radius_fn(lengths[index] / total)
        if radii is not None:
            factor = radius * radii[index]
        ring = []
        for side in range(sides):
            angle = math.tau * side / sides
            ring.append(geo.add_vert(point + normal * (factor * math.cos(angle))
                    + binormal * (factor * squash * math.sin(angle))))
        rings.append(ring)
    for index in range(len(rings) - 1):
        lower, upper = rings[index], rings[index + 1]
        v0, v1 = lengths[index] * scale, lengths[index + 1] * scale
        for side in range(sides):
            following = (side + 1) % sides
            u0, u1 = side / sides * tiles, (side + 1) / sides * tiles
            geo.add_face((lower[side], lower[following], upper[following], upper[side]), mat,
                    [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
    if caps:
        geo.add_face(tuple(reversed(rings[0])), mat)
        geo.add_face(tuple(rings[-1]), mat)
        geo.orient_outward()
    return geo


def rod(start, end, radius, mat, sides=8, caps=True):
    """Прямой цилиндр между двумя точками."""
    return tube([start, end], radius, mat, sides, caps)


def dome(surface, outline, rings, mat, wear=(), center=(0.0, 0.0)):
    """Накладная пластина на криволинейной поверхности. surface(u, v) -> (точка, нормаль);
    outline — контур пластины [(u, v), ...]; rings — [(масштаб контура, высота над поверхностью),
    ...] от края к середине, в середине ставится вершина на высоте последнего кольца.
    wear — номера поясов между кольцами (0 — у края), на которых облезает краска."""
    geo = Geo()
    loops = []
    for scale, height in rings:
        loop = []
        for u, v in outline:
            point, normal = surface(center[0] + (u - center[0]) * scale, center[1] + (v - center[1]) * scale)
            loop.append(geo.add_vert(Vector(point) + Vector(normal).normalized() * height))
        loops.append(loop)
    point, normal = surface(*center)
    normal = Vector(normal).normalized()
    top = geo.add_vert(Vector(point) + normal * rings[-1][1])
    count = len(outline)
    for band, (outer, inner) in enumerate(zip(loops, loops[1:])):
        for index in range(count):
            following = (index + 1) % count
            geo.add_face((outer[index], outer[following], inner[following], inner[index]), mat, None, band in wear)
    for index in range(count):
        geo.add_face((loops[-1][index], loops[-1][(index + 1) % count], top), mat)
    # Грани должны смотреть наружу, как бы ни был обойдён контур.
    last = [geo.verts[index] for index in geo.faces[-1]]
    if _face_normal(last).dot(normal) < 0.0:
        geo.flip()
    return geo


def wear_shell(geo, mat=None, lift=None):
    """Оболочка поверх граней, помеченных как изношенные кромки: её материал рисует сколы краски
    до металла (отсечение по альфе). None, если помеченных граней нет."""
    if not any(geo.wear):
        return None
    mat = WEAR_MATERIAL if mat is None else mat
    lift = WEAR_LIFT if lift is None else lift
    normals = _vertex_normals(geo)
    shell = Geo()
    remap = {}
    for face, worn in zip(geo.faces, geo.wear):
        if not worn:
            continue
        indices = []
        for index in face:
            if index not in remap:
                remap[index] = shell.add_vert(geo.verts[index] + normals[index] * lift)
            indices.append(remap[index])
        shell.add_face(indices, mat)
    return shell


def atlas_uv(cell, atlas_size):
    """Ячейка атласа (x, y, ширина, высота в пикселях) -> (u0, v0, u1, v1) в UV Blender."""
    x, y, width, height = cell
    return (x / atlas_size, 1.0 - (y + height) / atlas_size, (x + width) / atlas_size, 1.0 - y / atlas_size)


def quad(center, normal, up, width, height, mat, uv_rect=(0.0, 0.0, 1.0, 1.0), offset=0.0):
    """Плоская табличка: смотрит по normal, верх картинки — по up."""
    normal = Vector(normal).normalized()
    up = (Vector(up) - normal * Vector(up).dot(normal)).normalized()
    right = up.cross(normal)
    origin = Vector(center) + normal * offset
    u0, v0, u1, v1 = uv_rect
    geo = Geo()
    corners = [origin - right * width * 0.5 - up * height * 0.5, origin + right * width * 0.5 - up * height * 0.5,
            origin + right * width * 0.5 + up * height * 0.5, origin - right * width * 0.5 + up * height * 0.5]
    indices = [geo.add_vert(corner) for corner in corners]
    geo.add_face(indices, mat, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
    return geo


def arc_quad(axis_point, radius, angle_deg, z, width, height, mat, uv_rect, segments=5, squash=(1.0, 1.0)):
    """Наклейка на цилиндре вокруг вертикальной оси через axis_point: центр — под углом angle_deg
    (0 — в сторону +X, 90 — вперёд, +Y) на высоте z. Верх картинки — вверх."""
    u0, v0, u1, v1 = uv_rect
    geo = Geo()
    span = width / radius
    centre = math.radians(angle_deg)
    lower, upper = [], []
    for step in range(segments + 1):
        t = step / segments
        # Картинка читается слева направо для смотрящего снаружи: угол растёт.
        angle = centre + span * (t - 0.5)
        x = axis_point[0] + radius * squash[0] * math.cos(angle)
        y = axis_point[1] + radius * squash[1] * math.sin(angle)
        lower.append(geo.add_vert((x, y, z - height * 0.5)))
        upper.append(geo.add_vert((x, y, z + height * 0.5)))
    for step in range(segments):
        ua = u0 + (u1 - u0) * step / segments
        ub = u0 + (u1 - u0) * (step + 1) / segments
        geo.add_face((lower[step], lower[step + 1], upper[step + 1], upper[step]), mat,
                [(ua, v0), (ub, v0), (ub, v1), (ua, v1)])
    return geo


# ---------------------------------------------------------------------------------------------
# Сборка мешей
# ---------------------------------------------------------------------------------------------

def rigid(bone):
    """Жёсткая привязка всего куска к одной кости."""
    return lambda co: {bone: 1.0}


def blend_z(upper_bone, lower_bone, z_top, z_bottom):
    """Плавный переход весов по высоте: выше z_top — upper_bone, ниже z_bottom — lower_bone."""
    def weights(co):
        t = min(max((co.z - z_bottom) / (z_top - z_bottom), 0.0), 1.0)
        t = t * t * (3.0 - 2.0 * t)
        if t >= 0.999:
            return {upper_bone: 1.0}
        if t <= 0.001:
            return {lower_bone: 1.0}
        return {upper_bone: t, lower_bone: 1.0 - t}
    return weights


class Piece:
    """Один меш модели: куски Geo и то, к каким костям они привязаны."""

    def __init__(self, name):
        self.name = name
        self.geo = Geo()
        self.weights = []       # по вершинам: словарь {кость: вес} или None
        self.morphs = {}        # имя формы -> положения по вершинам (None — как в основе)

    def add(self, geo, weights=None, morphs=None):
        """weights — имя кости, функция co -> {кость: вес} или None (меш без скелета).
        morphs — {имя формы: Geo с той же топологией в другой позе} (shape keys: кисть в хвате).
        Кромки, помеченные износом, сразу получают оболочку со сколами."""
        if isinstance(weights, str):
            weights = rigid(weights)
        morphs = morphs or {}
        base = len(self.geo.verts)
        for name in list(self.morphs) + [name for name in morphs if name not in self.morphs]:
            column = self.morphs.setdefault(name, [None] * base)
            other = morphs.get(name)
            if other is None:
                column.extend([None] * len(geo.verts))
            else:
                assert len(other.verts) == len(geo.verts), "форма %s: другая топология" % name
                column.extend(v.copy() for v in other.verts)
        self.weights.extend(None if weights is None else weights(v) for v in geo.verts)
        self.geo.merge(geo)
        shell = wear_shell(geo)
        if shell is not None:
            self.add(shell, weights)
        return self

    def transform(self, matrix):
        """Преобразует весь меш вместе с формами."""
        self.geo.transform(matrix)
        for column in self.morphs.values():
            for index, co in enumerate(column):
                if co is not None:
                    column[index] = matrix @ co
        return self


def _box_uv(corner_points, normal, scale):
    """Проекция по главной оси нормали. U по возможности идёт вдоль Y (длинная ось оружия)."""
    ax, ay, az = abs(normal.x), abs(normal.y), abs(normal.z)
    if ax >= ay and ax >= az:
        return [(p.y * scale, p.z * scale) for p in corner_points]
    if ay >= az:
        return [(p.x * scale, p.z * scale) for p in corner_points]
    return [(p.y * scale, p.x * scale) for p in corner_points]


def _face_normal(points):
    normal = Vector((0.0, 0.0, 0.0))
    for index in range(len(points)):
        current, following = points[index], points[(index + 1) % len(points)]
        normal.x += (current.y - following.y) * (current.z + following.z)
        normal.y += (current.z - following.z) * (current.x + following.x)
        normal.z += (current.x - following.x) * (current.y + following.y)
    return normal.normalized() if normal.length > 1.0e-12 else Vector((0.0, 0.0, 1.0))


def _fibonacci_hemisphere(count):
    directions = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for index in range(count):
        z = (index + 0.5) / count
        radius = math.sqrt(max(1.0 - z * z, 0.0))
        directions.append(Vector((math.cos(golden * index) * radius, math.sin(golden * index) * radius, z)))
    return directions


def _vertex_normals(geo):
    """Нормали вершин (среднее по граням с весом площади). Считаются здесь, а не берутся у
    Blender: тот складывает их в несколько потоков, и последние биты гуляют от запуска к запуску."""
    normals = [Vector((0.0, 0.0, 0.0)) for _ in geo.verts]
    for face in geo.faces:
        points = [geo.verts[index] for index in face]
        weighted = Vector((0.0, 0.0, 0.0))
        for index in range(1, len(points) - 1):
            weighted += (points[index] - points[0]).cross(points[index + 1] - points[0])
        for index in face:
            normals[index] += weighted
    return [normal.normalized() if normal.length > 1.0e-12 else Vector((0.0, 0.0, 0.0)) for normal in normals]


def _occlusion(geo):
    """Затенение в щелях: доля лучей из вершины, упёршихся в свой же кусок поблизости."""
    tree = BVHTree.FromPolygons([tuple(v) for v in geo.verts], geo.faces, all_triangles=False)
    directions = _fibonacci_hemisphere(AO_RAYS)
    total_weight = sum(direction.z for direction in directions)
    values = []
    for position, normal in zip(geo.verts, _vertex_normals(geo)):
        if normal.length < 0.5:
            values.append(1.0)
            continue
        helper = Vector((0.0, 0.0, 1.0)) if abs(normal.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        tangent = normal.cross(helper).normalized()
        bitangent = normal.cross(tangent)
        origin = position + normal * AO_BIAS
        blocked = 0.0
        for direction in directions:
            world = tangent * direction.x + bitangent * direction.y + normal * direction.z
            hit = tree.ray_cast(origin, world, AO_DISTANCE)
            if hit[0] is not None:
                blocked += direction.z * (1.0 - hit[3] / AO_DISTANCE) ** 0.5
        # Округление до 1/255: точнее цвет вершины всё равно не нужен.
        values.append(round(max(1.0 - AO_STRENGTH * blocked / total_weight, AO_FLOOR) * AO_LEVELS) / AO_LEVELS)
    return values


def build_object(piece, armature=None, occlusion=True, smooth_angle=SMOOTH_ANGLE_DEG):
    """Piece -> объект Blender с материалами, UV, весами, формами и затенением в цвете вершин.
    smooth_angle — рёбра острее него остаются жёсткими (у рук он больше: пальцы — шестигранные
    трубки, которые должны выглядеть круглыми)."""
    geo = piece.geo
    mesh = bpy.data.meshes.new(piece.name)
    mesh.from_pydata([tuple(v) for v in geo.verts], [], geo.faces)
    mesh.update()
    names = []
    for name in geo.mats:
        if name not in names:
            names.append(name)
    for name in names:
        mesh.materials.append(bpy.data.materials[name])
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        polygon.material_index = names.index(geo.mats[polygon.index])
        uv = geo.uvs[polygon.index]
        if uv is None:
            points = [geo.verts[index] for index in geo.faces[polygon.index]]
            uv = _box_uv(points, _face_normal(points), uv_scale(geo.mats[polygon.index]))
        for corner, loop_index in enumerate(polygon.loop_indices):
            layer.data[loop_index].uv = uv[corner]
    mesh.use_auto_smooth = True
    mesh.auto_smooth_angle = math.radians(smooth_angle)
    if occlusion:
        values = _occlusion(geo)
        colors = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        for index, value in enumerate(values):
            colors.data[index].color = (value, value, value, 1.0)
        mesh.color_attributes.active_color = colors
        mesh.color_attributes.render_color_index = 0
    obj = bpy.data.objects.new(piece.name, mesh)
    bpy.context.collection.objects.link(obj)
    if piece.morphs:
        obj.shape_key_add(name="Basis", from_mix=False)
        for name, column in piece.morphs.items():
            key = obj.shape_key_add(name=name, from_mix=False)
            for index, co in enumerate(column):
                if co is not None:
                    key.data[index].co = co
    if armature is not None:
        groups = {}
        for index, weights in enumerate(piece.weights):
            for bone, weight in weights.items():
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([index], weight, "REPLACE")
        modifier = obj.modifiers.new("Armature", "ARMATURE")
        modifier.object = armature
        obj.parent = armature
    return obj


def export_glb(path, extras=False):
    """Экспортирует всю сцену в один .glb. Сообщение про Draco в выводе Blender безвредно."""
    bpy.ops.object.select_all(action="DESELECT")
    # export_apply выключен: с ним Blender не пишет формы (shape keys), а модификаторов, кроме
    # скелета, у мешей нет.
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=False, export_yup=True,
            export_animations=False, export_extras=extras, export_colors=True, export_tangents=False,
            export_morph=True, export_morph_normal=True, export_morph_tangent=False)
    print("EXPORTED", path)


def report():
    """Печатает габариты и число треугольников — сверка с метриками и бюджетом."""
    low = Vector((1.0e9, 1.0e9, 1.0e9))
    high = Vector((-1.0e9, -1.0e9, -1.0e9))
    total = 0
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        xs = [vertex.co for vertex in obj.data.vertices]
        piece_low = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
        piece_high = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
        triangles = sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)
        total += triangles
        print("PIECE %-12s tris=%5d  min=(%.3f, %.3f, %.3f)  max=(%.3f, %.3f, %.3f)" % (obj.name, triangles,
                *piece_low, *piece_high))
        low = Vector((min(low.x, piece_low.x), min(low.y, piece_low.y), min(low.z, piece_low.z)))
        high = Vector((max(high.x, piece_high.x), max(high.y, piece_high.y), max(high.z, piece_high.z)))
    print("TOTAL tris=%d  min=(%.3f, %.3f, %.3f)  max=(%.3f, %.3f, %.3f)" % (total, *low, *high))
