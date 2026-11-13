#!/usr/bin/env python3
"""Материалы персонажа и ручного оружия: пишет ресурсы StandardMaterial3D и привязывает их к моделям.

Запуск из корня репозитория (после character_textures.py и генераторов моделей):
    python3 tools/textures/character_materials.py

1. Пишет resources/materials/characters/<имя>.tres по таблице MATERIALS ниже.
2. В .glb.import моделей персонажа и оружия прописывает подмену материалов по имени
   (_subresources -> materials -> use_external): после импорта каждый экземпляр модели
   пользуется общим внешним материалом. Остальные параметры импорта не трогает.

Suit — единственный материал, который игра красит под игрока (PlayerVisuals.make_suit_material):
его текстура нейтральная, цвет задаёт albedo_color. В цвете вершин моделей лежит затенение
в щелях, поэтому почти у всех материалов включено vertex_color_use_as_albedo.
"""

import json
import os
import re
import struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MATERIAL_DIR = "resources/materials/characters"
TEXTURE_DIR = "res://assets/textures/characters"
MODELS = (
    "assets/models/characters/crewmate.glb",
    "assets/models/characters/crewmate_arm.glb",
    "assets/models/weapons/pistol.glb",
    "assets/models/weapons/knife.glb",
)

# Прозрачность и отсечение по альфе (BaseMaterial3D.Transparency).
ALPHA = 1
ALPHA_SCISSOR = 2


def pbr(texture, color, roughness=1.0, metallic=1.0, normal=1.0, **extra):
    """Материал на тайловом наборе <texture>_albedo/_normal/_orm."""
    return dict(texture=texture, color=color, roughness=roughness, metallic=metallic, normal=normal, **extra)


def flat(color, roughness, metallic=0.0, **extra):
    return dict(texture=None, color=color, roughness=roughness, metallic=metallic, **extra)


# Имя материала в модели -> описание. Файл ресурса — то же имя в snake_case.
MATERIALS = {
    # --- Скафандр ---
    # Эмаль под лаком: clearcoat даёт чёткое ядро блика поверх потёртой краски. Цвет здесь —
    # запасной: игра красит костюм сама (PlayerVisuals.suit_paint_color).
    "Suit": pbr("suit_paint", (0.7, 0.43, 0.08), clearcoat=0.5, clearcoat_roughness=0.15),
    "SuitWhite": pbr("suit_paint", (0.8, 0.81, 0.83), clearcoat=0.35, clearcoat_roughness=0.2),
    "SuitRed": pbr("suit_paint", (0.62, 0.07, 0.05), clearcoat=0.4, clearcoat_roughness=0.2),
    # Сколы краски до металла: оболочка на кромках сегментов.
    "SuitChips": flat((1.0, 1.0, 1.0), 0.42, metallic=0.85, albedo_texture="suit_chips", transparency=ALPHA_SCISSOR,
            vertex_color=False),
    "SuitFabric": pbr("suit_fabric", (0.33, 0.34, 0.37), normal=1.2),
    "SuitMetal": pbr("suit_metal", (0.8, 0.81, 0.83)),
    "SuitMetalDark": pbr("suit_metal", (0.17, 0.18, 0.2), roughness=1.0),
    "SuitRubber": pbr("suit_rubber", (0.06, 0.062, 0.07)),
    # Перчатки — тёмная плотная ткань; ладонь и напальчники — резина (SuitRubber).
    "SuitGlove": pbr("suit_fabric", (0.17, 0.175, 0.19), normal=0.9),
    "SuitBoot": pbr("suit_rubber", (0.4, 0.41, 0.44)),
    "SuitDecal": flat((1.0, 1.0, 1.0), 0.55, albedo_texture="suit_decals", transparency=ALPHA_SCISSOR),
    "SuitScreen": flat((1.0, 1.0, 1.0), 0.2, albedo_texture="suit_decals", emission_texture="suit_decals",
            emission=(1.0, 1.0, 1.0), emission_energy=2.2),
    "SuitGlow": flat((0.2, 0.85, 0.84), 0.3, emission=(0.24, 0.86, 0.85), emission_energy=3.0, vertex_color=False),
    "SuitLamp": flat((1.0, 0.95, 0.84), 0.3, emission=(1.0, 0.93, 0.8), emission_energy=2.6, vertex_color=False),
    "SuitAlert": flat((1.0, 0.2, 0.16), 0.3, emission=(1.0, 0.16, 0.12), emission_energy=2.5, vertex_color=False),
    # Стекло: затемнённое, с тёплым напылением — отражает комнату, но лицо за ним видно.
    "Visor": flat((0.16, 0.125, 0.075, 0.8), 0.04, metallic=0.55, transparency=ALPHA, specular=1.0, vertex_color=False),
    # Пластина за стеклом: по умолчанию тёмная с подсветкой приборов; фото лица заменяет материал.
    "FacePlate": flat((0.01, 0.014, 0.018), 0.6, emission_texture="visor_hud", emission=(1.0, 1.0, 1.0),
            emission_energy=1.6, vertex_color=False),
    # --- Оружие ---
    "WeaponGunmetal": pbr("weapon_gunmetal", (0.3, 0.31, 0.34)),
    "WeaponSteel": pbr("suit_metal", (0.62, 0.63, 0.66), roughness=1.2, normal=0.5),
    "WeaponEdge": pbr("suit_metal", (0.93, 0.93, 0.94), roughness=0.5, normal=0.3),
    "WeaponPolymer": pbr("weapon_polymer", (0.1, 0.105, 0.12), normal=0.6),
    "WeaponGrip": pbr("weapon_grip", (0.085, 0.088, 0.1)),
    "WeaponAccent": pbr("suit_metal", (0.7, 0.09, 0.07), roughness=1.2),
    "WeaponGlow": flat((0.2, 0.85, 0.84), 0.3, emission=(0.24, 0.86, 0.85), emission_energy=3.5, vertex_color=False),
    "WeaponSight": flat((0.5, 1.0, 0.4), 0.3, emission=(0.45, 1.0, 0.35), emission_energy=2.0, vertex_color=False),
}


def snake_case(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def material_path(name):
    return "%s/%s.tres" % (MATERIAL_DIR, snake_case(name))


def color_text(color):
    alpha = color[3] if len(color) > 3 else 1.0
    return "Color(%s, %s, %s, %s)" % tuple(("%g" % value) for value in (*color[:3], alpha))


def material_text(name, spec):
    textures = []
    lines = ['resource_name = "%s"' % name]

    def texture(file_name):
        identifier = "%d_%s" % (len(textures) + 1, file_name)
        for known, known_file in textures:
            if known_file == file_name:
                return 'ExtResource("%s")' % known
        textures.append((identifier, file_name))
        return 'ExtResource("%s")' % identifier

    if spec.get("transparency"):
        lines.append("transparency = %d" % spec["transparency"])
        if spec["transparency"] == ALPHA_SCISSOR:
            lines.append("alpha_scissor_threshold = 0.5")
    if spec.get("vertex_color", True):
        lines.append("vertex_color_use_as_albedo = true")
    lines.append("albedo_color = %s" % color_text(spec["color"]))
    base = spec.get("texture")
    if base is not None:
        lines.append("albedo_texture = %s" % texture(base + "_albedo"))
        lines.append("metallic = %g" % spec["metallic"])
        lines.append("metallic_texture = %s" % texture(base + "_orm"))
        lines.append("metallic_texture_channel = 2")
        lines.append("roughness = %g" % spec["roughness"])
        lines.append("roughness_texture = %s" % texture(base + "_orm"))
        lines.append("roughness_texture_channel = 1")
        lines.append("normal_enabled = true")
        lines.append("normal_scale = %g" % spec["normal"])
        lines.append("normal_texture = %s" % texture(base + "_normal"))
        lines.append("ao_enabled = true")
        lines.append("ao_texture = %s" % texture(base + "_orm"))
        lines.append("ao_texture_channel = 0")
    else:
        if "albedo_texture" in spec:
            lines.append("albedo_texture = %s" % texture(spec["albedo_texture"]))
        lines.append("metallic = %g" % spec["metallic"])
        if "specular" in spec:
            lines.append("metallic_specular = %g" % spec["specular"])
        lines.append("roughness = %g" % spec["roughness"])
    if "clearcoat" in spec:
        lines.append("clearcoat_enabled = true")
        lines.append("clearcoat = %g" % spec["clearcoat"])
        lines.append("clearcoat_roughness = %g" % spec["clearcoat_roughness"])
    if "emission" in spec:
        lines.append("emission_enabled = true")
        lines.append("emission = %s" % color_text(spec["emission"]))
        lines.append("emission_energy_multiplier = %g" % spec["emission_energy"])
        if "emission_texture" in spec:
            # Умножение: светится только то, что нарисовано на текстуре.
            lines.append("emission_operator = 1")
            lines.append("emission_texture = %s" % texture(spec["emission_texture"]))
    header = ['[gd_resource type="StandardMaterial3D" format=3]', ""]
    for identifier, file_name in textures:
        header.append('[ext_resource type="Texture2D" path="%s/%s.png" id="%s"]' % (TEXTURE_DIR, file_name, identifier))
    if textures:
        header.append("")
    return "\n".join(header + ["[resource]"] + lines) + "\n"


def write_materials():
    os.makedirs(os.path.join(ROOT, MATERIAL_DIR), exist_ok=True)
    for name, spec in MATERIALS.items():
        path = os.path.join(ROOT, material_path(name))
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(material_text(name, spec))
        print("MATERIAL", material_path(name))


def glb_material_names(path):
    """Имена материалов из JSON-блока .glb."""
    with open(path, "rb") as handle:
        data = handle.read()
    length = struct.unpack("<I", data[12:16])[0]
    document = json.loads(data[20:20 + length])
    return [material["name"] for material in document.get("materials", [])]


def subresources_text(names):
    known = sorted(name for name in names if name in MATERIALS)
    if not known:
        return "_subresources={}"
    entries = []
    for name in known:
        resource = "res://" + material_path(name)
        entries.append('"%s": {\n"use_external/enabled": true,\n"use_external/fallback_path": "%s",\n'
                '"use_external/path": "%s"\n}' % (name, resource, resource))
    return '_subresources={\n"materials": {\n%s\n}\n}' % ",\n".join(entries)


def bind_models():
    for model in MODELS:
        path = os.path.join(ROOT, model)
        sidecar = path + ".import"
        if not os.path.exists(path) or not os.path.exists(sidecar):
            print("SKIP", model, "(нет модели или .import: сначала сгенерируй и импортируй её)")
            continue
        with open(sidecar, encoding="utf-8") as handle:
            text = handle.read()
        start = text.index("_subresources=")
        end = text.index("\ngltf/", start)
        updated = text[:start] + subresources_text(glb_material_names(path)) + text[end:]
        if updated != text:
            with open(sidecar, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(updated)
        print("BOUND", model)


if __name__ == "__main__":
    write_materials()
    bind_models()
