"""Библиотека материалов станции и её подключение к моделям.

Обычный Python 3, запуск из корня репозитория:
    python3 tools/textures/apply_materials.py

Что делает:
1. Пишет resources/materials/<имя>.tres для каждого материала из MATERIALS (имена совпадают с именами
   материалов в моделях: env_white, env_panel, ...). Это вариант «для предметов»: текстура привязана
   к самому предмету (triplanar в координатах модели), поэтому не «плывёт», когда предмет двигают.
2. Для материалов, которые встречаются в деталях набора (assets/models/kit), пишет второй вариант
   resources/materials/world/<имя>.tres: текстура привязана к миру (world triplanar). Соседние стены и
   плиты пола получают разные участки текстуры — повторов не видно, швов на стыках нет.
3. Переписывает _subresources во всех assets/models/kit/*.glb.import и assets/models/props/*.glb.import:
   каждый материал модели заменяется при импорте на материал из библиотеки (набор — на вариант world).
   После запуска нужен переимпорт: godot --headless --import.

Развёртки (UV) у моделей нет: текстуры накладываются проекцией с трёх сторон (triplanar). Размер плитки
в метрах задан в SURFACES. Цвета ниже — sRGB, как в редакторе Godot.
"""

import glob
import json
import os
import struct
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MATERIAL_DIR = "resources/materials"
WORLD_SUBDIR = "world"
TEXTURE_RES = "res://assets/textures/surfaces/"
KIT_MODELS = "assets/models/kit"
PROP_MODELS = "assets/models/props"

# Фильтрация: линейная с мип-уровнями и анизотропией (пол под острым углом не мылится).
TEXTURE_FILTER_ANISOTROPIC = 5
TRANSPARENCY_ALPHA = 1
# Смешивание premultiplied alpha: освещённый цвет ПРИБАВЛЯЕТСЯ к фону целиком, без умножения на альфу.
# Годится только чистому стеклу с чёрным albedo (остаются одни блики, фон темнеет на альфу). Цветным
# прозрачным материалам (колпак, вода) нужно обычное смешивание, иначе они светятся молочной вуалью.
BLEND_PREMULTIPLIED = 4
DETAIL_BLEND_MULTIPLY = 3
DETAIL_UV2 = 1
EMISSION_MULTIPLY = 1

# Наборы текстур: tile — сколько метров занимает одна плитка; maps — какие карты есть у набора;
# mean — средняя яркость albedo (цвет материала делится на неё, чтобы итог совпал с задуманным);
# specular — сила бликов неметалла (metallic_specular: 0.5 — обычный диэлектрик). У матовых фактур
# (ткань, резина, перфорированный потолок) она снижена: иначе под острым углом они блестят, как лакированные.
SURFACES = {
    "paint_panel": dict(tile=2.4, maps=("albedo", "normal", "orm"), mean=0.93, specular=0.4),
    "enamel": dict(tile=0.8, maps=("albedo", "normal", "orm"), mean=0.95, specular=0.5),
    "composite": dict(tile=1.6, maps=("albedo", "normal", "orm"), mean=0.83, specular=0.3),
    "floor_rubber": dict(tile=1.0, maps=("albedo", "normal", "orm"), mean=1.0, specular=0.4),
    "floor_plate": dict(tile=1.0, maps=("albedo", "normal", "orm"), mean=1.0, specular=0.5),
    "metal_brushed": dict(tile=0.6, maps=("albedo", "normal", "orm"), mean=0.9, specular=0.5),
    "metal_anodized": dict(tile=0.5, maps=("albedo", "normal", "orm"), mean=0.94, specular=0.5),
    "plastic": dict(tile=0.4, maps=("albedo", "normal", "orm"), mean=0.95, specular=0.45),
    "vinyl": dict(tile=0.3, maps=("albedo", "normal", "orm"), mean=0.92, specular=0.3),
    "laminate": dict(tile=1.2, maps=("albedo", "normal", "orm"), mean=0.95, specular=0.5),
    "fabric": dict(tile=0.16, maps=("albedo", "normal", "orm"), mean=0.85, specular=0.15),
    "wood": dict(tile=1.0, maps=("albedo", "normal", "orm"), mean=1.0, specular=0.5),
    "rubber": dict(tile=0.5, maps=("albedo", "normal", "orm"), mean=0.8, specular=0.25),
    "ceiling_perf": dict(tile=1.2, maps=("albedo", "normal", "orm"), mean=0.88, specular=0.15),
    "glass": dict(tile=1.2, maps=("albedo", "orm"), mean=1.0, specular=0.5),
    "screen": dict(tile=0.16, maps=("emission", "orm"), mean=1.0, specular=0.5),
    "foliage": dict(tile=0.25, maps=("albedo", "normal", "orm"), mean=1.0, specular=0.4),
    "water": dict(tile=0.4, maps=("normal",), mean=1.0, specular=0.5),
}
# Слой мелких деталей («апельсиновая корка»): плитка 25 см поверх основной текстуры.
DETAIL_TILE = 0.25

# Материалы: surface — набор текстур (None — без текстур), color — цвет (sRGB hex), остальное по желанию:
# roughness/metallic — множители к картам (или значения, если карт нет), normal — сила рельефа,
# detail — добавить слой мелких деталей, alpha — прозрачность, emission/energy — свечение,
# backlight — просвет листьев, tile — свой размер плитки вместо размера набора, specular — своя сила бликов
# (у стекла она снижена: блики ламп на почти зеркальной поверхности иначе выгорают в белые пятна),
# premultiplied — смешивание «только блики» (см. BLEND_PREMULTIPLIED), clearcoat — слой лака поверх.
# Тёмные тона (env_deep, env_panel, env_line) не темнее 4–6 % отражения: чернее не бывает ни краска, ни
# резина, а отскоку света от такой поверхности нечего возвращать — низ комнаты проваливается в черноту.
MATERIALS = {
    # --- конструкция станции ---
    "env_white": dict(surface="paint_panel", color="cdcfd4", detail=True),
    "env_wall_core": dict(surface="paint_panel", color="9da4b6", detail=True, tile=1.9),
    "env_grey": dict(surface="metal_brushed", color="c3c6cd", metallic=1.0, normal=0.5),
    "env_metal": dict(surface="metal_brushed", color="c3c6cd", metallic=1.0, normal=0.5),
    "env_line": dict(surface="composite", color="465286"),
    "env_mid": dict(surface="ceiling_perf", color="5d648a"),
    "env_panel": dict(surface="composite", color="4a527a", tile=1.3),
    "env_deep": dict(surface="rubber", color="3d4566"),
    "env_floor_a": dict(surface="floor_rubber", color="ffffff"),
    "env_floor_b": dict(surface="floor_plate", color="ffffff", metallic=1.0),
    # --- цвета реквизита ---
    "env_yellow": dict(surface="enamel", color="e3b02a", metallic=1.0),
    "env_cyan": dict(surface="metal_anodized", color="2fbcc4", metallic=1.0),
    "env_red": dict(surface="enamel", color="b42b36", metallic=1.0),
    "env_orange": dict(surface="enamel", color="e0832a", metallic=1.0),
    "env_green": dict(surface="plastic", color="4bb783"),
    "env_enamel_violet": dict(surface="enamel", color="7650b4", metallic=1.0),
    "env_chrome": dict(surface="metal_anodized", color="d9dce2", metallic=1.0, roughness=0.5, normal=0.25, tile=1.2),
    "env_rubber": dict(surface="rubber", color="2a2c36"),
    # Дно щелей, отверстий и решёток: почти чёрное, без бликов — читается как глубина, а не как краска.
    "env_void": dict(surface=None, color="0b0c10", roughness=0.95, specular=0.1),
    "env_violet": dict(surface="vinyl", color="5f3d9c", normal=0.45),
    "env_laminate": dict(surface="laminate", color="c9c8c3", clearcoat=0.3),
    "env_fabric_white": dict(surface="fabric", color="d9d9de", normal=0.6),
    "env_fabric_yellow": dict(surface="fabric", color="d8b040", normal=0.6),
    "env_fabric_cyan": dict(surface="fabric", color="3fa9b3", normal=0.6),
    "env_fabric_violet": dict(surface="fabric", color="7d55c2", normal=0.6),
    "env_wood": dict(surface="wood", color="ffffff"),
    "env_leaf": dict(surface="foliage", color="34703f", backlight="1c4a12", roughness=0.8),
    "env_water": dict(surface="water", color="4fb4c4", alpha=0.38, roughness=0.06, normal=0.5),
    "env_glass": dict(surface="glass", color="000000", alpha=0.06, specular=0.06, premultiplied=True),
    "env_cover": dict(surface="glass", color="9fd4de", alpha=0.16, specular=0.3),
    # --- светящиеся детали ---
    "env_lamp": dict(surface=None, color="fff3d6", emission="ffecc8", energy=2.4, roughness=0.4),
    "env_lamp_soft": dict(surface=None, color="dfe9ff", emission="cfe0ff", energy=2.2, roughness=0.4),
    "env_shade": dict(surface=None, color="ffd98a", emission="ffc04a", energy=1.6, roughness=0.8),
    "env_glow_cyan": dict(surface=None, color="3ddbd9", emission="3ddbd9", energy=3.0, roughness=0.3),
    "env_glow_yellow": dict(surface=None, color="ffd23f", emission="ffd23f", energy=2.6, roughness=0.3),
    "env_glow_red": dict(surface=None, color="ff5d73", emission="ff3d57", energy=3.0, roughness=0.3),
    "env_glow_green": dict(surface=None, color="57e39a", emission="57e39a", energy=2.6, roughness=0.3),
    "env_glow_orange": dict(surface=None, color="ff9f1c", emission="ff8a1c", energy=3.2, roughness=0.3),
    "env_glow_violet": dict(surface=None, color="a855f7", emission="a855f7", energy=3.0, roughness=0.3),
    "env_core": dict(surface=None, color="ffd23f", emission="ffb21c", energy=6.0, roughness=0.3),
    "env_button_red": dict(surface="plastic", color="d2303f", emission="ff3048", energy=0.5, roughness=0.6),
    "env_screen": dict(surface="screen", color="06090e", emission="1f9aa6", energy=0.9),
    "env_screen_dark": dict(surface="glass", color="07080c", roughness=1.0),
    # Погашенный светильник: для саботажа «свет» игровой код подменяет им env_lamp на меше.
    "env_lamp_off": dict(surface=None, color="8d8a80", roughness=0.35),
}


def _color(hex_text, alpha=1.0, scale=1.0):
    values = [min(int(hex_text[i:i + 2], 16) / 255.0 * scale, 1.0) for i in (0, 2, 4)]
    return "Color(%s, %s, %s, %s)" % tuple(_number(value) for value in values + [alpha])


def _number(value):
    text = ("%.4f" % value).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def material_text(name, world):
    """Текст .tres материала name; world — привязка текстуры к миру (детали набора) или к предмету."""
    spec = MATERIALS[name]
    surface = SURFACES.get(spec["surface"]) if spec["surface"] else None
    resources = []
    lines = []

    def texture(file_name):
        identifier = "%d_tex" % (len(resources) + 1)
        resources.append("[ext_resource type=\"Texture2D\" path=\"%s%s.png\" id=\"%s\"]" % (
                TEXTURE_RES, file_name, identifier))
        return "ExtResource(\"%s\")" % identifier

    alpha = spec.get("alpha", 1.0)
    maps = surface["maps"] if surface else ()
    scale = 1.0 / surface["mean"] if surface and "albedo" in maps else 1.0
    if alpha < 1.0:
        lines.append("transparency = %d" % TRANSPARENCY_ALPHA)
        if spec.get("premultiplied"):
            lines.append("blend_mode = %d" % BLEND_PREMULTIPLIED)
    lines.append("albedo_color = %s" % _color(spec["color"], alpha, scale))
    if "albedo" in maps:
        lines.append("albedo_texture = %s" % texture(spec["surface"] + "_albedo"))
    orm = texture(spec["surface"] + "_orm") if "orm" in maps else None
    lines.append("metallic = %s" % _number(spec.get("metallic", 0.0)))
    if orm and spec.get("metallic", 0.0) > 0.0:
        lines += ["metallic_texture = %s" % orm, "metallic_texture_channel = 2"]
    specular = spec.get("specular", surface["specular"] if surface else 0.5)
    if specular != 0.5:
        lines.append("metallic_specular = %s" % _number(specular))
    lines.append("roughness = %s" % _number(spec.get("roughness", 1.0 if orm else 0.5)))
    if orm:
        lines += ["roughness_texture = %s" % orm, "roughness_texture_channel = 1"]
    if spec.get("emission"):
        lines += ["emission_enabled = true", "emission = %s" % _color(spec["emission"]),
                "emission_energy_multiplier = %s" % _number(spec["energy"])]
        if "emission" in maps:
            lines += ["emission_operator = %d" % EMISSION_MULTIPLY,
                    "emission_texture = %s" % texture(spec["surface"] + "_emission")]
    if "normal" in maps:
        lines += ["normal_enabled = true", "normal_scale = %s" % _number(spec.get("normal", 1.0)),
                "normal_texture = %s" % texture(spec["surface"] + "_normal")]
    if orm:
        lines += ["ao_enabled = true", "ao_light_affect = 0.35", "ao_texture = %s" % orm, "ao_texture_channel = 0"]
    if spec.get("clearcoat"):
        lines += ["clearcoat_enabled = true", "clearcoat = %s" % _number(spec["clearcoat"]), "clearcoat_roughness = 0.12"]
    if spec.get("backlight"):
        lines += ["backlight_enabled = true", "backlight = %s" % _color(spec["backlight"])]
    if spec.get("detail"):
        lines += ["detail_enabled = true", "detail_blend_mode = %d" % DETAIL_BLEND_MULTIPLY,
                "detail_uv_layer = %d" % DETAIL_UV2,
                "detail_albedo = %s" % texture("micro_paint_detail"),
                "detail_normal = %s" % texture("micro_paint_normal")]
    if surface:
        tile = 1.0 / spec.get("tile", surface["tile"])
        lines += ["uv1_scale = Vector3(%s, %s, %s)" % ((_number(tile),) * 3), "uv1_triplanar = true",
                "uv1_triplanar_sharpness = 4.0"]
        if world:
            lines.append("uv1_world_triplanar = true")
        if spec.get("detail"):
            detail = 1.0 / DETAIL_TILE
            lines += ["uv2_scale = Vector3(%s, %s, %s)" % ((_number(detail),) * 3), "uv2_triplanar = true",
                    "uv2_triplanar_sharpness = 4.0"]
            if world:
                lines.append("uv2_world_triplanar = true")
        lines.append("texture_filter = %d" % TEXTURE_FILTER_ANISOTROPIC)
    header = ["[gd_resource type=\"StandardMaterial3D\" format=3]", ""]
    if resources:
        header += resources + [""]
    return "\n".join(header + ["[resource]"] + lines + [""])


def glb_materials(path):
    """Имена материалов из JSON-блока файла .glb."""
    with open(path, "rb") as handle:
        data = handle.read()
    length = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20:20 + length].decode("utf-8"))
    return [material["name"] for material in document.get("materials", [])]


def model_files(directory):
    return sorted(glob.glob(os.path.join(REPO_ROOT, directory, "*.glb")))


def patch_import(glb_path, names, world_names):
    """Вписывает в <модель>.glb.import замену материалов на библиотечные."""
    import_path = glb_path + ".import"
    if not os.path.exists(import_path):
        print("НЕТ ФАЙЛА %s: сначала выполни godot --headless --import" % import_path)
        return False
    with open(import_path, "r", encoding="utf-8") as handle:
        text = handle.read()
    start = text.index("_subresources=")
    end = text.index("gltf/naming_version=")
    entries = []
    for name in sorted(names):
        folder = MATERIAL_DIR + "/" + WORLD_SUBDIR if name in world_names else MATERIAL_DIR
        path = "res://%s/%s.tres" % (folder, name)
        entries.append("\"%s\": {\n\"use_external/enabled\": true,\n\"use_external/fallback_path\": \"%s\",\n"
                "\"use_external/path\": \"%s\"\n}" % (name, path, path))
    block = "_subresources={\n\"materials\": {\n%s\n}\n}\n" % ",\n".join(entries) if entries else "_subresources={}\n"
    with open(import_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text[:start] + block + text[end:])
    return True


def main():
    kit_names = set()
    used = set()
    models = []
    for directory, is_kit in ((KIT_MODELS, True), (PROP_MODELS, False)):
        for path in model_files(directory):
            names = glb_materials(path)
            models.append((path, names, is_kit))
            used.update(names)
            if is_kit:
                kit_names.update(names)
    missing = sorted(name for name in used if name not in MATERIALS)
    if missing:
        print("В MATERIALS нет материалов: %s" % ", ".join(missing))
        return 1
    for name in sorted(MATERIALS):
        for world in (False, True):
            if world and name not in kit_names:
                continue
            folder = os.path.join(REPO_ROOT, MATERIAL_DIR, WORLD_SUBDIR if world else "")
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, name + ".tres"), "w", encoding="utf-8", newline="\n") as handle:
                handle.write(material_text(name, world))
    print("MATERIALS: %d (из них для набора, world: %d)" % (len(MATERIALS), len(kit_names)))
    patched = 0
    for path, names, is_kit in models:
        if patch_import(path, names, kit_names if is_kit else set()):
            patched += 1
    print("IMPORT: переписано %d файлов .glb.import" % patched)
    return 0


if __name__ == "__main__":
    sys.exit(main())
