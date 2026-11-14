"""Общие помощники для генерации моделей в Blender (запуск: blender -b --python <скрипт> -- <аргументы>).

Договорённости для всех моделей проекта:
- 1 единица Blender = 1 метр; низ модели (ноги, основание) стоит на Z = 0;
- перёд модели смотрит по +Y Blender — после экспорта это -Z в Godot (направление «вперёд»);
- правая сторона персонажа — +X и в Blender, и в Godot;
- имена мешей не совпадают с именами костей (иначе Godot переименует кость);
- материалы — простые Principled BSDF: в Godot они станут StandardMaterial3D.
"""

import math
import sys

import bpy
from mathutils import Vector


def script_args():
    """Аргументы после "--" в командной строке Blender."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def hex_color(value):
    """"ffd23f" -> (r, g, b) в линейном пространстве, как ждёт Blender."""
    value = value.lstrip("#")
    srgb = [int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


def material(name, color, roughness=0.6, metallic=0.0, emission=None, emission_strength=1.0):
    """Материал с именем name; повторный вызов с тем же именем вернёт уже созданный."""
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


def _finish(obj, name, mat, smooth_angle):
    obj.name = name
    obj.data.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.use_auto_smooth = True
    obj.data.auto_smooth_angle = math.radians(smooth_angle)
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def rounded_box(name, size, location=(0.0, 0.0, 0.0), bevel=0.03, segments=3, mat=None, smooth_angle=50.0):
    """Параллелепипед size = (x, y, z) со скруглёнными рёбрами, центр в location."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = min(bevel, min(size) * 0.49)
        modifier.segments = segments
        apply_modifiers(obj)
    return _finish(obj, name, mat, smooth_angle)


def cylinder(name, radius, depth, location=(0.0, 0.0, 0.0), vertices=24, bevel=0.0, segments=2, mat=None,
        smooth_angle=50.0, rotation=(0.0, 0.0, 0.0)):
    """Цилиндр вдоль Z (до поворота rotation), центр в location."""
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices, location=location,
            rotation=rotation)
    obj = bpy.context.active_object
    if bevel > 0.0:
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = segments
        modifier.limit_method = "ANGLE"
        apply_modifiers(obj)
    return _finish(obj, name, mat, smooth_angle)


def sphere(name, radius, location=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0), segments=24, rings=14, mat=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings, location=location)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return _finish(obj, name, mat, 180.0)


def capsule(name, radius, length, location=(0.0, 0.0, 0.0), mat=None, rotation=(0.0, 0.0, 0.0)):
    """Капсула вдоль Z: полная длина length (вместе с полусферами), центр в location."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=20, ring_count=12, location=location,
            rotation=rotation)
    obj = bpy.context.active_object
    half = max(length * 0.5 - radius, 0.0)
    for vertex in obj.data.vertices:
        vertex.co.z += half if vertex.co.z > 0.0 else -half
    return _finish(obj, name, mat, 180.0)


def join(objects, name):
    """Склеивает объекты в один меш (материалы сохраняются как отдельные поверхности)."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.active_object
    result.name = name
    result.data.name = name
    return result


def set_origin(obj, point):
    """Переносит начало координат объекта в мировую точку point, геометрия остаётся на месте."""
    cursor = bpy.context.scene.cursor
    saved = cursor.location.copy()
    cursor.location = Vector(point)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    cursor.location = saved


def export_glb(path):
    """Экспортирует всю сцену в один .glb. Сообщение про Draco в выводе Blender безвредно."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
            export_animations=False)
    print("EXPORTED", path)
