"""Дополнительные фигуры для генераторов персонажа и оружия (common.py не меняем, всё своё — здесь).

- lathe            тело вращения по профилю (рукава, штанины, стволы);
- extrude_profile  плоский контур, выдавленный в толщину (лицевая пластина, галстук, клинок);
- rounded_rect / pill   готовые контуры для extrude_profile;
- taper, move, rotate_about, mirror_x, freeze, skin_to   правки готовых объектов.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import common


def _new_object(name, bm, mat, smooth_angle):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    if mat is not None:
        mesh.materials.append(mat)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.use_auto_smooth = True
    mesh.auto_smooth_angle = math.radians(smooth_angle)
    return obj


def lathe(name, profile, location=(0.0, 0.0, 0.0), segments=16, mat=None, smooth_angle=50.0,
        squash=(1.0, 1.0), caps=True):
    """Тело вращения вокруг оси Z. profile — список (радиус, z) снизу вверх; радиус 0 на конце
    даёт острую/круглую макушку, иначе торец закрывается плоской крышкой (caps = False — остаётся
    открытым: для колец, чьи торцы спрятаны внутри других деталей).
    squash = (x, y) сплющивает сечение в эллипс."""
    bm = bmesh.new()
    rings = []
    for radius, z in profile:
        if radius <= 1.0e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
            continue
        ring = []
        for index in range(segments):
            angle = math.tau * index / segments
            ring.append(bm.verts.new((radius * math.cos(angle) * squash[0],
                    radius * math.sin(angle) * squash[1], z)))
        rings.append(ring)
    for lower, upper in zip(rings, rings[1:]):
        if len(lower) == 1 and len(upper) == 1:
            continue
        for index in range(segments):
            following = (index + 1) % segments
            if len(lower) == 1:
                bm.faces.new((lower[0], upper[following], upper[index]))
            elif len(upper) == 1:
                bm.faces.new((lower[index], lower[following], upper[0]))
            else:
                bm.faces.new((lower[index], lower[following], upper[following], upper[index]))
    for ring in (rings[0], rings[-1]):
        if caps and len(ring) > 1:
            bm.faces.new(ring)
    obj = _new_object(name, bm, mat, smooth_angle)
    obj.location = Vector(location)
    freeze(obj)
    return obj


def ball_profile(radius, center_z, rings=5):
    """Профиль шара для lathe: суставы с тем же числом сегментов, что и рукава, стыкуются ровно."""
    points = []
    for index in range(rings + 1):
        angle = math.pi * index / rings - math.pi * 0.5
        points.append((0.0 if index in (0, rings) else radius * math.cos(angle), center_z + radius * math.sin(angle)))
    return points


def rounded_rect(width, height, radius, corner_segments=5, center=(0.0, 0.0)):
    """Контур прямоугольника со скруглёнными углами: список (a, b) против часовой стрелки."""
    radius = min(radius, width * 0.5, height * 0.5)
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


def pill(width, height, corner_segments=6, center=(0.0, 0.0)):
    """Контур «таблетки»: прямоугольник с полностью круглыми короткими сторонами."""
    return rounded_rect(width, height, min(width, height) * 0.5, corner_segments, center)


def extrude_profile(name, points, depth, location=(0.0, 0.0, 0.0), bevel=0.0, segments=2, mat=None,
        smooth_angle=40.0, plane="XZ"):
    """Плоский контур points = [(a, b), ...] (против часовой стрелки), выдавленный на depth.
    plane "XZ": a -> X, b -> Z, толщина по Y (пластина смотрит вперёд, +Y);
    plane "YZ": a -> Y, b -> Z, толщина по X (пластина стоит вдоль взгляда, как клинок);
    plane "XY": a -> X, b -> Y, толщина по Z (пластина лежит на полу, как подошва).
    Центр толщины — в location. bevel скругляет только острые рёбра (ободки)."""
    bm = bmesh.new()
    half = depth * 0.5
    if plane == "XZ":
        front = [bm.verts.new((a, half, b)) for a, b in points]
        back = [bm.verts.new((a, -half, b)) for a, b in points]
    elif plane == "YZ":
        front = [bm.verts.new((half, a, b)) for a, b in points]
        back = [bm.verts.new((-half, a, b)) for a, b in points]
    else:
        front = [bm.verts.new((a, b, half)) for a, b in points]
        back = [bm.verts.new((a, b, -half)) for a, b in points]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    count = len(points)
    for index in range(count):
        following = (index + 1) % count
        bm.faces.new((front[index], back[index], back[following], front[following]))
    obj = _new_object(name, bm, mat, smooth_angle)
    obj.location = Vector(location)
    freeze(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = segments
        modifier.limit_method = "ANGLE"
        modifier.angle_limit = math.radians(40.0)
        common.apply_modifiers(obj)
    return obj


def planar_uv(obj, center, width, height, mirror=True):
    """UV-развёртка «проекцией спереди» (вдоль оси Y) для пластины шириной width и высотой height
    с центром center = (x, z). mirror = True: картинка читается правильно для смотрящего на
    модель спереди (левый край картинки — на правой стороне персонажа, +X)."""
    mesh = obj.data
    layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co
        u = (co.x - center[0]) / width
        if mirror:
            u = -u
        layer.data[loop.index].uv = (u + 0.5, (co.z - center[1]) / height + 0.5)


def taper(obj, bottom_scale=(1.0, 1.0), top_scale=(1.0, 1.0)):
    """Сужает объект по X/Y линейно по высоте: bottom_scale внизу, top_scale вверху."""
    zs = [vertex.co.z for vertex in obj.data.vertices]
    low, high = min(zs), max(zs)
    span = max(high - low, 1.0e-6)
    for vertex in obj.data.vertices:
        t = (vertex.co.z - low) / span
        vertex.co.x *= bottom_scale[0] + (top_scale[0] - bottom_scale[0]) * t
        vertex.co.y *= bottom_scale[1] + (top_scale[1] - bottom_scale[1]) * t
    return obj


def transform(obj, matrix):
    """Применяет матрицу к геометрии объекта (сам объект остаётся в нуле)."""
    obj.data.transform(matrix)
    obj.data.update()
    return obj


def move(obj, offset):
    return transform(obj, Matrix.Translation(Vector(offset)))


def rotate_about(obj, pivot, axis, degrees):
    """Поворачивает геометрию вокруг точки pivot по оси axis ("X", "Y", "Z")."""
    pivot = Vector(pivot)
    matrix = (Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(degrees), 4, axis)
            @ Matrix.Translation(-pivot))
    return transform(obj, matrix)


def mirror_x(obj):
    """Отражает геометрию по X (левая/правая половина) и чинит нормали."""
    transform(obj, Matrix.Scale(-1.0, 4, Vector((1.0, 0.0, 0.0))))
    obj.data.flip_normals()
    obj.data.update()
    return obj


def skin_to(obj, bone_name):
    """Жёсткая привязка: все вершины объекта — в группу с именем кости, вес 1."""
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    return obj


def bind_to_armature(obj, armature):
    """Вешает модификатор Armature и делает объект ребёнком скелета (после join)."""
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature
    return obj


def triangle_count():
    """Число треугольников во всех мешах сцены — для контроля бюджета."""
    total = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            total += sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)
    return total


def freeze(obj):
    """Запекает положение/поворот/масштаб объекта в геометрию (примитивы common.cylinder и
    common.capsule оставляют их на объекте)."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj
