"""Помощники для генераторов окружения (kit.py, props.py): палитра, материалы, фигуры, сборка и экспорт.

Договорённости те же, что в common.py: 1 единица = 1 метр, низ на Z = 0, перёд модели смотрит по +Y Blender
(в Godot это -Z), +X — право. Здесь ничего не запускается само: модуль только импортируют.

Повторный запуск генератора без правок даёт те же .glb байт в байт (git не видит изменений). Ради этого
детали склеиваются в порядке их добавления (_merge), нормали считаются на Python (_set_weighted_normals),
а буфер геометрии в готовом файле пересобирается в каноническом порядке (_canonicalize_glb).
Развёртки (UV) у моделей нет. В самих .glb материалы одноцветные (палитра ниже) и служат только именами:
при импорте в Godot каждый env_<имя> заменяется PBR-материалом из библиотеки resources/materials
(текстуры накладываются проекцией с трёх сторон, без UV). Библиотеку и замены пишет
tools/textures/apply_materials.py; новому ключу в MATERIALS нужна запись и там.

Кроме брусков и тел вращения здесь есть мягкие формы: shell() — тело между двумя сетками точек (одеяло,
лист), cushion() — подушка или сиденье, cushion_rim() — её кромка для канта, и bolt() — головка винта.
Мелкие детали (швы, винты, ножки, оправы) — то, что отличает вещь от цветного бруска: добавляй их щедро,
но внутри прежних габаритов модели.
"""

import json
import math
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Угол, после которого ребро считается жёстким. Фаски в 2 сегмента (по 30°) остаются гладкими.
SMOOTH_ANGLE_DEG = 40.0
# Сколько сторон у круглых деталей по умолчанию.
ROUND_SEGMENTS = 24

# Палитра проекта (sRGB hex) и производные от неё оттенки. Так модели выглядят в Blender; в игре вид
# каждого материала задаёт библиотека resources/materials (см. tools/textures/apply_materials.py).
MATERIALS = {
    # конструкция станции
    "white": dict(color="f2f3f7", roughness=0.5),
    "wall_core": dict(color="b4b9d0", roughness=0.6),
    "grey": dict(color="9aa0b8", roughness=0.5),
    "line": dict(color="2c3152", roughness=0.6),
    "mid": dict(color="20243f", roughness=0.6),
    "panel": dict(color="171a30", roughness=0.6),
    "deep": dict(color="0e1020", roughness=0.7),
    "floor_a": dict(color="4b5384", roughness=0.55),
    "floor_b": dict(color="414875", roughness=0.55),
    # яркие цвета реквизита
    "yellow": dict(color="ffd23f", roughness=0.45),
    "cyan": dict(color="3ddbd9", roughness=0.45),
    "red": dict(color="ff5d73", roughness=0.45),
    "green": dict(color="57e39a", roughness=0.45),
    "orange": dict(color="ff9f1c", roughness=0.45),
    "violet": dict(color="a855f7", roughness=0.45),
    "metal": dict(color="9aa0b8", roughness=0.35, metallic=0.35),
    "wood": dict(color="c98a55", roughness=0.6),
    "laminate": dict(color="ecebe6", roughness=0.3),
    "enamel_violet": dict(color="8a5fd0", roughness=0.4),
    "chrome": dict(color="d5d8de", roughness=0.15, metallic=1.0),
    "rubber": dict(color="1b1c22", roughness=0.9),
    # «пустота»: дно щелей и отверстий, зрачки — почти чёрная матовая поверхность
    "void": dict(color="08090c", roughness=0.9),
    "leaf": dict(color="2fbf71", roughness=0.55),
    "water": dict(color="3ddbd9", roughness=0.1, alpha=0.45),
    "glass": dict(color="bfeff5", roughness=0.05, alpha=0.08),
    "cover": dict(color="9fe8f0", roughness=0.05, alpha=0.3),
    # ткани: матрасы, одеяла, подушки (в игре — тканое полотно из библиотеки материалов)
    "fabric_white": dict(color="e6e6ea", roughness=0.9),
    "fabric_yellow": dict(color="e8c24a", roughness=0.9),
    "fabric_cyan": dict(color="45b9c2", roughness=0.9),
    "fabric_violet": dict(color="8a5fd0", roughness=0.9),
    # светящиеся детали (свечение подхватывает glow в Environment)
    "lamp": dict(color="fff3d6", emission="fff0cf", strength=2.4),
    "glow_cyan": dict(color="3ddbd9", emission="3ddbd9", strength=2.6),
    "glow_yellow": dict(color="ffd23f", emission="ffd23f", strength=2.4),
    "glow_red": dict(color="ff5d73", emission="ff3d57", strength=2.6),
    "glow_green": dict(color="57e39a", emission="57e39a", strength=2.4),
    "glow_orange": dict(color="ff9f1c", emission="ff8a1c", strength=3.0),
    "glow_violet": dict(color="a855f7", emission="a855f7", strength=2.6),
    "core": dict(color="ffd23f", emission="ffb21c", strength=4.5),
    "button_red": dict(color="ff5d73", emission="ff3d57", strength=1.0, roughness=0.3),
    "lamp_soft": dict(color="dfe9ff", emission="cfe0ff", strength=1.6),
    "shade": dict(color="ffd23f", emission="ffc531", strength=1.3),
    "screen": dict(color="103a4a", emission="3ddbd9", strength=0.9, roughness=0.2),
    "screen_dark": dict(color="0e1020", roughness=0.15),
}


def mat(key):
    """Материал из MATERIALS по ключу. Имя в .glb — env_<ключ>."""
    name = "env_" + key
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    spec = MATERIALS[key]
    material = common.material(name, spec["color"], roughness=spec.get("roughness", 0.5),
            metallic=spec.get("metallic", 0.0), emission=spec.get("emission"),
            emission_strength=spec.get("strength", 1.0))
    alpha = spec.get("alpha")
    if alpha is not None:
        material.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = alpha
        material.blend_method = "BLEND"
        material.shadow_method = "NONE"
    return material


def _axis_rotation(axis):
    """Поворот, который кладёт локальную ось Z вдоль оси axis."""
    if axis == "x":
        return (0.0, math.pi / 2.0, 0.0)
    if axis == "y":
        return (-math.pi / 2.0, 0.0, 0.0)
    return (0.0, 0.0, 0.0)


def _object_from_bmesh(name, bm, material):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if material is not None:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.use_auto_smooth = True
    mesh.auto_smooth_angle = math.radians(SMOOTH_ANGLE_DEG)
    return obj


def _place(obj, rot, pivot):
    """Поворачивает деталь вокруг точки pivot (у фигур из common.py начало координат лежит в нуле мира)."""
    if rot is not None:
        shift = Matrix.Translation(Vector(pivot))
        obj.matrix_world = shift @ Euler(rot).to_matrix().to_4x4() @ shift.inverted() @ obj.matrix_world
    return obj


def box(size, loc, material, bevel=0.03, segments=2, rot=None):
    """Скруглённый со всех сторон брусок size = (x, y, z) с центром в loc; rot — углы Эйлера в радианах."""
    obj = common.rounded_box("part", size, location=loc, bevel=bevel, segments=segments, mat=mat(material))
    return _place(obj, rot, loc)


def bar(size, loc, material, axis="x", bevel=0.03, segments=2):
    """Брусок, у которого скруглены только рёбра вдоль оси axis: торцы плоские и стыкуются без щелей."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for vertex in bm.verts:
        vertex.co = Vector((vertex.co.x * size[0] + loc[0], vertex.co.y * size[1] + loc[1],
                vertex.co.z * size[2] + loc[2]))
    if bevel > 0.0:
        index = "xyz".index(axis)
        edges = [edge for edge in bm.edges
                if abs((edge.verts[0].co - edge.verts[1].co).normalized()[index]) > 0.99]
        cross = [size[i] for i in range(3) if i != index]
        bmesh.ops.bevel(bm, geom=edges, offset=min(bevel, min(cross) * 0.49), segments=segments,
                affect="EDGES", profile=0.5)
    return _object_from_bmesh("part", bm, mat(material))


def cyl(radius, depth, loc, material, axis="z", bevel=0.0, vertices=ROUND_SEGMENTS, rot=None):
    """Цилиндр вдоль оси axis с центром в loc; bevel скругляет кромки торцов."""
    rotation = rot if rot is not None else _axis_rotation(axis)
    return common.cylinder("part", radius, depth, location=loc, vertices=vertices, bevel=bevel,
            mat=mat(material), rotation=rotation)


def cone(radius_bottom, radius_top, depth, loc, material, axis="z", vertices=ROUND_SEGMENTS, rot=None):
    """Усечённый конус вдоль оси axis с центром в loc."""
    rotation = rot if rot is not None else _axis_rotation(axis)
    bpy.ops.mesh.primitive_cone_add(radius1=radius_bottom, radius2=radius_top, depth=depth, vertices=vertices,
            location=loc, rotation=rotation)
    obj = bpy.context.active_object
    obj.data.materials.append(mat(material))
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.use_auto_smooth = True
    obj.data.auto_smooth_angle = math.radians(SMOOTH_ANGLE_DEG)
    return obj


def ball(radius, loc, material, scale=(1.0, 1.0, 1.0), rot=None):
    """Шар (или эллипсоид со scale) с центром в loc. Мелкие шары получают меньше граней."""
    size = radius * max(scale)
    segments, rings = (10, 6) if size < 0.03 else ((16, 10) if size < 0.12 else (24, 14))
    # Свой шар вместо common.sphere: там масштаб применяет Blender, и координаты вершин чуть «шумят»
    # от запуска к запуску.
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    for vertex in bm.verts:
        vertex.co = Vector((vertex.co.x * scale[0], vertex.co.y * scale[1], vertex.co.z * scale[2]))
    obj = _object_from_bmesh("part", bm, mat(material))
    obj.location = loc
    if rot is not None:
        obj.rotation_euler = rot
    return obj


def pill(radius, length, loc, material, axis="z", rot=None):
    """Капсула полной длины length вдоль оси axis."""
    rotation = rot if rot is not None else _axis_rotation(axis)
    return common.capsule("part", radius, length, location=loc, mat=mat(material), rotation=rotation)


def torus(major, minor, loc, material, axis="z", rot=None, major_segments=ROUND_SEGMENTS, minor_segments=8):
    """Тор: major — радиус кольца, minor — радиус трубки; ось кольца вдоль axis."""
    rotation = rot if rot is not None else _axis_rotation(axis)
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=major_segments,
            minor_segments=minor_segments, location=loc, rotation=rotation)
    obj = bpy.context.active_object
    obj.data.materials.append(mat(material))
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.use_auto_smooth = True
    obj.data.auto_smooth_angle = math.radians(180.0)
    return obj


def lathe(profile, loc, material, axis="z", segments=ROUND_SEGMENTS, closed=False, bevel=0.0, rot=None):
    """Тело вращения. profile — точки (радиус, высота) снизу вверх; радиус 0 закрывает торец.

    closed=True соединяет последнюю точку с первой (кольца, бублики). bevel скругляет изломы профиля.
    """
    bm = bmesh.new()
    rings = []
    for radius, height in profile:
        if radius <= 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, height))])
        else:
            rings.append([bm.verts.new((radius * math.cos(2.0 * math.pi * i / segments),
                    radius * math.sin(2.0 * math.pi * i / segments), height)) for i in range(segments)])
    pairs = list(zip(rings, rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for lower, upper in pairs:
        if len(lower) == 1 and len(upper) == 1:
            continue
        for i in range(segments):
            j = (i + 1) % segments
            if len(lower) == 1:
                bm.faces.new((lower[0], upper[i], upper[j]))
            elif len(upper) == 1:
                bm.faces.new((lower[i], lower[j], upper[0]))
            else:
                bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    obj = _bevel_sharp(_object_from_bmesh("part", bm, mat(material)), bevel)
    obj.location = loc
    obj.rotation_euler = rot if rot is not None else _axis_rotation(axis)
    return obj


def _bevel_sharp(obj, bevel):
    """Фаска только на жёстких рёбрах (угол больше 30°): гладкие изгибы контура не трогает."""
    if bevel > 0.0:
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
        common.apply_modifiers(obj)
    return obj


def prism(points, depth, material, plane="xy", offset=0.0, bevel=0.0):
    """Многоугольник points [(u, v), ...], выдавленный на depth; bevel скругляет жёсткие рёбра.

    plane="xy": лежит на полу, выдавлен по Z от offset; "xz": стоит лицом к ±Y, (u, v) = (x, z), выдавлен
    по Y от offset; "yz": стоит лицом к ±X, (u, v) = (y, z), выдавлен по X от offset.
    """
    def to_space(u, v, w):
        if plane == "xy":
            return (u, v, w)
        if plane == "xz":
            return (u, w, v)
        return (w, u, v)

    bm = bmesh.new()
    near = [bm.verts.new(to_space(u, v, offset)) for u, v in points]
    far = [bm.verts.new(to_space(u, v, offset + depth)) for u, v in points]
    bm.faces.new(near)
    bm.faces.new(list(reversed(far)))
    count = len(points)
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new((near[i], far[i], far[j], near[j]))
    return _bevel_sharp(_object_from_bmesh("part", bm, mat(material)), bevel)


def ring_prism(outer, inner, depth, material, plane="xz", offset=0.0, bevel=0.0):
    """Рамка: пространство между контурами outer и inner (одинаковое число точек, один порядок обхода),
    выдавленное на depth. Плоскости и offset — как у prism()."""
    def to_space(u, v, w):
        if plane == "xy":
            return (u, v, w)
        if plane == "xz":
            return (u, w, v)
        return (w, u, v)

    bm = bmesh.new()
    loops = [[bm.verts.new(to_space(u, v, w)) for u, v in contour]
            for contour, w in ((outer, offset), (inner, offset), (inner, offset + depth), (outer, offset + depth))]
    count = len(outer)
    for index, lower in enumerate(loops):
        upper = loops[(index + 1) % len(loops)]
        for i in range(count):
            j = (i + 1) % count
            bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    return _bevel_sharp(_object_from_bmesh("part", bm, mat(material)), bevel)


def _catmull_rom(points, steps):
    """Плавная кривая через точки (сплайн Катмулла — Рома), steps отрезков между соседними точками."""
    vectors = [Vector(point) for point in points]
    padded = [vectors[0]] + vectors + [vectors[-1]]
    result = []
    for i in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[i - 1], padded[i], padded[i + 1], padded[i + 2]
        for step in range(steps):
            t = step / steps
            result.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
                    + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
    result.append(vectors[-1])
    return result


def tube(points, radius, material, smooth=True, steps=6, sides=8):
    """Трубка радиуса radius вдоль точек points. smooth=True — плавная кривая, иначе ломаная."""
    path = _catmull_rom(points, steps) if smooth and len(points) > 2 else [Vector(point) for point in points]
    curve = bpy.data.curves.new("part", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = max(sides // 4 - 1, 0)
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    spline.points.add(len(path) - 1)
    for point, position in zip(spline.points, path):
        point.co = (position.x, position.y, position.z, 1.0)
    obj = bpy.data.objects.new("part", curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    obj.data.materials.append(mat(material))
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.use_auto_smooth = True
    obj.data.auto_smooth_angle = math.radians(SMOOTH_ANGLE_DEG)
    return obj


def shell(top, bottom, material):
    """Замкнутое тело между двумя сетками точек одинакового размера top и bottom ([ряд][столбец] -> (x, y, z)):
    верхняя поверхность, нижняя и стенка по краю. Так делаются мягкие вещи — одеяло, подушка, лист растения.
    Сетки нигде не должны совпадать: у края оставляй хотя бы миллиметр толщины."""
    rows = len(top)
    columns = len(top[0])
    bm = bmesh.new()
    upper = [[bm.verts.new(point) for point in row] for row in top]
    lower = [[bm.verts.new(point) for point in row] for row in bottom]
    for i in range(rows - 1):
        for j in range(columns - 1):
            bm.faces.new((upper[i][j], upper[i][j + 1], upper[i + 1][j + 1], upper[i + 1][j]))
            bm.faces.new((lower[i][j], lower[i + 1][j], lower[i + 1][j + 1], lower[i][j + 1]))
    border = [(0, j) for j in range(columns)] + [(i, columns - 1) for i in range(1, rows)] \
            + [(rows - 1, j) for j in range(columns - 2, -1, -1)] + [(i, 0) for i in range(rows - 2, 0, -1)]
    for index, (i, j) in enumerate(border):
        k, m = border[(index + 1) % len(border)]
        bm.faces.new((upper[i][j], lower[i][j], lower[k][m], upper[k][m]))
    return _object_from_bmesh("part", bm, mat(material))


def cushion(size, loc, material, puff=0.5, dent=0.0, steps=10, rot=None, firm=True):
    """Подушка size = (x, y, z) с центром в loc: тонкая по краю и пухлая в середине (puff 0..1 — насколько
    край тоньше середины), dent — глубина вмятины посередине сверху (в долях толщины). firm=True — упругая
    обивка с ровной серединой (сиденье), False — мягкая подушка куполом (постель)."""
    half_x, half_y, half_z = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    top, bottom = [], []
    for i in range(steps + 1):
        v = -1.0 + 2.0 * i / steps
        row_top, row_bottom = [], []
        for j in range(steps + 1):
            u = -1.0 + 2.0 * j / steps
            # Контур — «суперэллипс»: углы подушки скруглены и чуть оттянуты наружу.
            power = 4.0 if firm else 2.2
            edge = (1.0 - abs(u) ** power) * (1.0 - abs(v) ** power)
            rise = half_z * ((1.0 - puff) + puff * max(edge, 0.0) ** 0.6)
            pinch = 1.0 - 0.06 * (1.0 - abs(u * v))
            hollow = dent * half_z * math.exp(-(u * u + v * v) * 3.5)
            x, y = u * half_x * pinch, v * half_y * pinch
            row_top.append((x, y, rise - hollow))
            row_bottom.append((x, y, -rise * 0.8))
        top.append(row_top)
        bottom.append(row_bottom)
    obj = shell(top, bottom, material)
    obj.location = loc
    if rot is not None:
        obj.rotation_euler = rot
    return obj


def cushion_rim(size, puff=0.5, steps=10):
    """Точки верхней кромки подушки cushion() с теми же параметрами в её локальных координатах (замкнутый
    обход) — по ним кладут кант."""
    half_x, half_y, half_z = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    square = [(-1.0 + 2.0 * j / steps, -1.0) for j in range(steps)] + [(1.0, -1.0 + 2.0 * i / steps) for i in range(steps)] \
            + [(1.0 - 2.0 * j / steps, 1.0) for j in range(steps)] + [(-1.0, 1.0 - 2.0 * i / steps) for i in range(steps)]
    square.append(square[0])
    points = []
    for u, v in square:
        pinch = 1.0 - 0.06 * (1.0 - abs(u * v))
        points.append((u * half_x * pinch, v * half_y * pinch, half_z * (1.0 - puff)))
    return points


def bolt(loc, axis="z", radius=0.012, material="grey", depth=0.01):
    """Головка болта или винта: низкий цилиндр с фаской, ось вдоль axis."""
    return cyl(radius, depth, loc, material, axis=axis, bevel=min(0.003, depth * 0.3), vertices=8)


def arc_points(radius_inner, radius_outer, angle_from_deg, angle_to_deg, steps=10, center=(0.0, 0.0)):
    """Контур дуги-сектора для prism(): углы в градусах, 0° — вправо (+u), 90° — вверх (+v)."""
    outer = []
    inner = []
    for i in range(steps + 1):
        angle = math.radians(angle_from_deg + (angle_to_deg - angle_from_deg) * i / steps)
        outer.append((center[0] + radius_outer * math.cos(angle), center[1] + radius_outer * math.sin(angle)))
        inner.append((center[0] + radius_inner * math.cos(angle), center[1] + radius_inner * math.sin(angle)))
    return outer + list(reversed(inner))


def rounded_rect_points(width, height, radius, steps=4, center=(0.0, 0.0)):
    """Контур прямоугольника со скруглёнными углами для prism()."""
    points = []
    half_w = width * 0.5 - radius
    half_h = height * 0.5 - radius
    for corner, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        for i in range(steps + 1):
            angle = math.radians(90.0 * corner + 90.0 * i / steps)
            points.append((center[0] + sx * half_w + radius * math.cos(angle),
                    center[1] + sy * half_h + radius * math.sin(angle)))
    return points


def clip_polygon_x(points, x_min, x_max):
    """Обрезает выпуклый многоугольник вертикальными границами x_min и x_max."""
    def clip(polygon, limit, keep_greater):
        result = []
        for i, current in enumerate(polygon):
            previous = polygon[i - 1]
            current_in = current[0] >= limit if keep_greater else current[0] <= limit
            previous_in = previous[0] >= limit if keep_greater else previous[0] <= limit
            if current_in != previous_in:
                t = (limit - previous[0]) / (current[0] - previous[0])
                result.append((limit, previous[1] + t * (current[1] - previous[1])))
            if current_in:
                result.append(current)
        return result

    clipped = clip(list(points), x_min, True)
    return clip(clipped, x_max, False) if clipped else []


class Frame:
    """Наклонная система координат: детали на скошенной панели задаются в её локальных координатах.

    at(x, y, z) переводит локальную точку в мировую; rot — углы для параметра rot у фигур;
    rot_axis("y") — поворот для круглой детали, чья ось смотрит вдоль локальной оси панели.
    """

    def __init__(self, origin, rot):
        self.origin = Vector(origin)
        self.rot = tuple(rot)
        self.matrix = Euler(rot).to_matrix()

    def at(self, x, y, z):
        return tuple(self.origin + self.matrix @ Vector((x, y, z)))

    def rot_axis(self, axis):
        return self.rot_local(_axis_rotation(axis))

    def rot_local(self, rot):
        """Углы для детали, повёрнутой на rot внутри этой системы координат."""
        return tuple((self.matrix @ Euler(rot).to_matrix()).to_euler())


def _gltf_key(vector):
    """Точка или нормаль Blender (x, y, z) -> байты трёх float в осях glTF (x, z, -y), без отрицательных нулей."""
    return struct.pack("<3f", vector[0] + 0.0, vector[2] + 0.0, 0.0 - vector[1])


def _canonicalize_glb(path, normal_tables):
    """Переписывает .glb в каноническом виде, чтобы повторный запуск генератора давал тот же файл байт в байт.

    Blender от запуска к запуску слегка «шумит» в нормалях (кодирование пользовательских нормалей, знак нуля),
    а экспортёр раскладывает вершины и треугольники в зависимости от этих значений. Поэтому буфер геометрии
    собирается заново: нормали берутся точные из normal_tables ({имя меша: {позиция: [нормали]}} — их посчитал
    _set_weighted_normals), одинаковые вершины склеиваются, вершины и треугольники каждой поверхности
    сортируются. Узлы, материалы и сама геометрия не меняются.
    """
    float_type, short_type, int_type = 5126, 5123, 5125
    index_formats = {5121: "B", short_type: "H", int_type: "I"}
    array_buffer, element_buffer = 34962, 34963
    with open(path, "rb") as handle:
        data = handle.read()
    json_length = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20:20 + json_length].decode("utf-8"))
    binary_start = 20 + json_length + 8
    for unsupported in ("images", "skins", "animations"):
        if document.get(unsupported):
            raise ValueError("%s: в файле есть %s, канонизация их не умеет" % (path, unsupported))

    def read(accessor_index, text_format, width):
        accessor = document["accessors"][accessor_index]
        buffer_view = document["bufferViews"][accessor["bufferView"]]
        start = binary_start + buffer_view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        values = struct.unpack_from("<%d%s" % (accessor["count"] * width, text_format), data, start)
        return [values[i * width:(i + 1) * width] for i in range(accessor["count"])]

    blob = bytearray()
    accessors = []
    views = []

    def write(payload, target, accessor):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteLength": len(payload), "byteOffset": len(blob), "target": target})
        blob.extend(payload)
        accessor["bufferView"] = len(views) - 1
        accessors.append(accessor)
        return len(accessors) - 1

    for mesh in document["meshes"]:
        table = normal_tables[mesh["name"]]
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            if sorted(attributes) != ["NORMAL", "POSITION"]:
                raise ValueError("%s: неожиданные атрибуты вершин %s" % (path, sorted(attributes)))
            positions = read(attributes["POSITION"], "f", 3)
            rough_normals = read(attributes["NORMAL"], "f", 3)
            index_accessor = document["accessors"][primitive["indices"]]
            indices = [row[0] for row in read(primitive["indices"], index_formats[index_accessor["componentType"]], 1)]
            vertices = []
            for position, rough in zip(positions, rough_normals):
                # «+ 0.0» превращает отрицательный ноль в обычный, как и в _gltf_key.
                key = struct.pack("<3f", *[value + 0.0 for value in position])
                # Из точных нормалей в этой точке берём ближайшую к той, что записал Blender.
                best = max(table[key], key=lambda candidate: sum(
                        a * b for a, b in zip(struct.unpack("<3f", candidate), rough)))
                vertices.append((key, best))
            unique = sorted(set(vertices))
            new_index = {vertex: index for index, vertex in enumerate(unique)}
            triangles = []
            for i in range(0, len(indices), 3):
                triangle = [new_index[vertices[index]] for index in indices[i:i + 3]]
                turn = triangle.index(min(triangle))
                triangles.append(tuple(triangle[turn:] + triangle[:turn]))
            triangles.sort()
            points = [struct.unpack("<3f", vertex[0]) for vertex in unique]
            primitive["attributes"] = {
                "POSITION": write(b"".join(vertex[0] for vertex in unique), array_buffer, {
                    "componentType": float_type, "count": len(unique), "type": "VEC3",
                    "max": [max(point[axis] for point in points) for axis in range(3)],
                    "min": [min(point[axis] for point in points) for axis in range(3)]}),
                "NORMAL": write(b"".join(vertex[1] for vertex in unique), array_buffer, {
                    "componentType": float_type, "count": len(unique), "type": "VEC3"}),
            }
            wide = len(unique) > 65535
            flat = [index for triangle in triangles for index in triangle]
            primitive["indices"] = write(struct.pack("<%d%s" % (len(flat), "I" if wide else "H"), *flat),
                    element_buffer, {"componentType": int_type if wide else short_type, "count": len(flat),
                    "type": "SCALAR"})
    while len(blob) % 4:
        blob.append(0)
    document["accessors"] = accessors
    document["bufferViews"] = views
    document["buffers"] = [{"byteLength": len(blob)}]
    text = json.dumps(document, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<4sII", b"glTF", 2, total))
        handle.write(struct.pack("<I4s", len(text), b"JSON"))
        handle.write(text)
        handle.write(struct.pack("<I4s", len(blob), b"BIN\x00"))
        handle.write(blob)


def _merge(objects, name, local):
    """Склеивает детали в один меш строго в порядке списка; вершины сразу в координатах local.

    bpy.ops.object.join и Mesh.transform дают от запуска к запуску чуть разный результат (порядок обхода,
    округление в потоках), поэтому точки переносятся здесь по одной.
    """
    bpy.context.view_layer.update()
    inverse = local.inverted()
    materials = []
    bm = bmesh.new()
    for obj in objects:
        mesh = obj.data
        matrix = inverse @ obj.matrix_world
        first_vert = len(bm.verts)
        first_face = len(bm.faces)
        bm.from_mesh(mesh)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        for index in range(first_vert, len(bm.verts)):
            bm.verts[index].co = matrix @ bm.verts[index].co
        slots = []
        for material in mesh.materials:
            if material not in materials:
                materials.append(material)
            slots.append(materials.index(material))
        for index in range(first_face, len(bm.faces)):
            face = bm.faces[index]
            face.material_index = slots[face.material_index] if slots else 0
            face.smooth = True
    merged_mesh = bpy.data.meshes.new(name)
    bm.to_mesh(merged_mesh)
    bm.free()
    # Текстуры накладываются проекцией (triplanar), развёртка не нужна: без неё меньше вершин и файл стабильнее.
    while merged_mesh.uv_layers:
        merged_mesh.uv_layers.remove(merged_mesh.uv_layers[0])
    for material in materials:
        merged_mesh.materials.append(material)
    merged = bpy.data.objects.new(name, merged_mesh)
    bpy.context.scene.collection.objects.link(merged)
    merged.matrix_world = local
    for obj in objects:
        old_mesh = obj.data
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(old_mesh)
    return merged


def _set_weighted_normals(mesh):
    """Нормали, взвешенные по площади граней: большие плоскости остаются плоскими, блик лежит на фасках.

    То же, что модификатор Weighted Normal, но считается здесь по порядку и поэтому даёт одинаковый файл
    при каждом запуске (модификатор при равных площадях граней выдаёт разный результат).
    Рёбра с изломом больше SMOOTH_ANGLE_DEG остаются жёсткими.
    Возвращает таблицу {позиция: [нормали]} в виде байтов glTF — по ней _canonicalize_glb правит файл.
    """
    bm = bmesh.new()
    bm.from_mesh(mesh)
    cos_limit = math.cos(math.radians(SMOOTH_ANGLE_DEG))
    loop_index = {}
    counter = 0
    for face in bm.faces:
        for loop in face.loops:
            loop_index[(face.index, loop.vert.index)] = counter
            counter += 1
    # Нормаль грани, умноженная на площадь, по формуле Ньюэлла — на чистом Python: встроенный расчёт
    # Blender идёт в несколько потоков и от запуска к запуску расходится в последнем знаке.
    weighted = {}
    unit = {}
    for face in bm.faces:
        points = [(vert.co.x, vert.co.y, vert.co.z) for vert in face.verts]
        # Обход начинаем с «наименьшей» точки: от того, с какой вершины начать, зависит последний знак суммы.
        start = points.index(min(points))
        points = points[start:] + points[:start]
        total = [0.0, 0.0, 0.0]
        for i, (ax, ay, az) in enumerate(points):
            bx, by, bz = points[(i + 1) % len(points)]
            total[0] += (ay * bz - az * by) * 0.5
            total[1] += (az * bx - ax * bz) * 0.5
            total[2] += (ax * by - ay * bx) * 0.5
        weighted[face.index] = Vector(total)
        unit[face.index] = Vector(total).normalized()
    normals = [(0.0, 0.0, 1.0)] * counter
    table = {}
    for vert in bm.verts:
        # Грани вокруг вершины объединяются в группы сглаживания через гладкие рёбра.
        parent = {face.index: face.index for face in vert.link_faces}

        def root(index):
            while parent[index] != index:
                index = parent[index]
            return index

        for edge in vert.link_edges:
            faces = edge.link_faces
            if len(faces) == 2 and unit[faces[0].index].dot(unit[faces[1].index]) >= cos_limit:
                first, second = root(faces[0].index), root(faces[1].index)
                if first != second:
                    parent[max(first, second)] = min(first, second)
        # Складываем в порядке, заданном самой геометрией: номера граней и порядок их обхода вокруг вершины
        # у Blender от запуска к запуску меняются, а от порядка сложения зависит последний знак результата.
        around = sorted(vert.link_faces, key=lambda face: tuple(weighted[face.index]))
        sums = {}
        for face in around:
            key = root(face.index)
            sums[key] = sums.get(key, Vector((0.0, 0.0, 0.0))) + weighted[face.index]
        for face in around:
            total = sums[root(face.index)]
            normal = total.normalized() if total.length > 1e-12 else unit[face.index]
            normals[loop_index[(face.index, vert.index)]] = (normal.x, normal.y, normal.z)
            table.setdefault(_gltf_key(vert.co), set()).add(_gltf_key(normal))
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.use_auto_smooth = True
    mesh.auto_smooth_angle = math.radians(180.0)
    mesh.normals_split_custom_set(normals)
    return {position: sorted(candidates) for position, candidates in table.items()}


class Model:
    """Собирает модель из деталей. Детали одной группы склеиваются в один меш с именем группы.

    Группа по умолчанию — "Body". Отдельные группы нужны подвижным частям (рычаг, стрелка, крышка):
    в Godot это отдельные MeshInstance3D с началом координат в точке вращения (см. origins в export).
    """

    DEFAULT_GROUP = "Body"

    def __init__(self, name):
        common.reset_scene()
        self.name = name
        self.groups = {}

    def add(self, obj, group=None):
        self.groups.setdefault(group or self.DEFAULT_GROUP, []).append(obj)
        return obj

    def extend(self, objects, group=None):
        for obj in objects:
            self.add(obj, group)

    def export(self, path, origins=None):
        """origins: {группа: точка или (точка, углы)} — начало координат группы (по умолчанию 0, 0, 0).

        С углами Эйлера локальные оси группы поворачиваются вместе с деталью (ось колеса на скошенном пульте).
        """
        origins = origins or {}
        triangles = 0
        normal_tables = {}
        for group, objects in self.groups.items():
            origin = origins.get(group, (0.0, 0.0, 0.0))
            if len(origin) == 2:
                local = Matrix.Translation(Vector(origin[0])) @ Euler(origin[1]).to_matrix().to_4x4()
            else:
                local = Matrix.Translation(Vector(origin))
            joined = _merge(objects, group, local)
            mesh = joined.data
            mesh.name = self.name + "_" + group
            normal_tables[mesh.name] = _set_weighted_normals(mesh)
            mesh.calc_loop_triangles()
            triangles += len(mesh.loop_triangles)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        common.export_glb(path)
        _canonicalize_glb(path, normal_tables)
        print("MODEL %s: %d triangles, groups: %s" % (self.name, triangles, ", ".join(self.groups)))


# ---------- Префабы Godot ----------

def _number(value):
    text = "%.4f" % value
    text = text.rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def pascal_case(name):
    return "".join(part.capitalize() for part in name.split("_"))


def write_prefab(path, name, model_resource_path, boxes, extra_nodes=None):
    """Пишет сцену-префаб: модель .glb плюс StaticBody3D с коробками столкновений (слой 1).

    boxes — список (размер, центр) в координатах Blender; здесь они переводятся в координаты Godot:
    (x, y, z) Blender -> (x, z, -y) Godot. extra_nodes — готовые строки .tscn с дополнительными узлами
    (например, светильник внутри потолочной панели).
    """
    lines = ["[gd_scene format=3]", "",
            "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_model\"]" % model_resource_path, ""]
    for index, (size, _center) in enumerate(boxes, start=1):
        lines += ["[sub_resource type=\"BoxShape3D\" id=\"BoxShape3D_%d\"]" % index,
                "size = Vector3(%s, %s, %s)" % (_number(size[0]), _number(size[2]), _number(size[1])), ""]
    lines += ["[node name=\"%s\" type=\"Node3D\"]" % pascal_case(name), "",
            "[node name=\"Model\" parent=\".\" instance=ExtResource(\"1_model\")]", "",
            "[node name=\"Collision\" type=\"StaticBody3D\" parent=\".\"]", ""]
    for index, (_size, center) in enumerate(boxes, start=1):
        lines += ["[node name=\"Shape%d\" type=\"CollisionShape3D\" parent=\"Collision\"]" % index,
                "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % (
                        _number(center[0]), _number(center[2]), _number(-center[1])),
                "shape = SubResource(\"BoxShape3D_%d\")" % index, ""]
    lines += extra_nodes or []
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    print("PREFAB", path)


def run_generator(builders, model_dir, prefab_dir, prefab_names=None, prefab_extras=None):
    """Общая точка входа kit.py и props.py.

    builders: {имя: функция}, функция возвращает (Model, origins или None, список коробок столкновений).
    Аргументы после "--": имена моделей (по умолчанию все) и флаг --prefabs — заодно переписать сцены-префабы
    (без флага сцены не трогаются: в них могли что-то поправить руками).
    prefab_names — для каких моделей вообще бывают префабы (None — для всех).
    prefab_extras — {имя: строки .tscn} с дополнительными узлами префаба.
    """
    args = common.script_args()
    write_prefabs = "--prefabs" in args
    names = [arg for arg in args if not arg.startswith("--")] or list(builders)
    for name in names:
        model, origins, boxes = builders[name]()
        model.export(os.path.join(REPO_ROOT, model_dir, name + ".glb"), origins)
        if write_prefabs and (prefab_names is None or name in prefab_names):
            write_prefab(os.path.join(REPO_ROOT, prefab_dir, name + ".tscn"), name,
                    "res://%s/%s.glb" % (model_dir, name), boxes, (prefab_extras or {}).get(name))
