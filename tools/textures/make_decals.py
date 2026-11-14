"""Декали станции: разметка, надписи, пятна и потёртости. Текстуры -> assets/textures/decals/,
префабы (узел Decal) -> scenes/maps/decals/<имя>.tscn.

Обычный Python 3 с numpy и PIL, запуск из корня репозитория:
    python3 tools/textures/make_decals.py

Как ставить декаль (узел Decal проецирует картинку вдоль своей локальной оси -Y):
- на пол — префаб без поворота в точку на уровне пола (y = 0); поворот вокруг Y разворачивает рисунок.
  Верх картинки смотрит на -Z (как перёд моделей);
- на стену — локальная ось +Y декали должна смотреть от стены в комнату, локальная -Z — вверх.
  Готовая формула — wall_transform() в tools/assets/environment_preview.py; центр декали ставь на поверхность
  стены (0,13 м от линии сетки).
Размер префаба (size) — ширина, глубина проекции, высота рисунка в метрах; менять его можно прямо на экземпляре.
Декали не отбрасывают теней и почти ничего не стоят: это самый дешёвый способ «состарить» помещение.
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import texlib
from texlib import blur, noise, orm, smoothstep

OUT = "decals"
PREFAB_DIR = os.path.join(texlib.REPO_ROOT, "scenes", "maps", "decals")
FONT_PATH = os.path.join(texlib.REPO_ROOT, "assets", "fonts", "Unbounded.ttf")
FONT_WEIGHT = 700

YELLOW = (0.86, 0.66, 0.14)
WHITE = (0.84, 0.85, 0.86)
BLACK = (0.07, 0.07, 0.08)
RED = (0.74, 0.2, 0.2)
# Глубина проекции: на полу декаль не должна «залезать» на ноги выше щиколотки, на стене — доставать
# до панелей и поясков разной толщины.
FLOOR_DEPTH = 0.16
WALL_DEPTH = 0.36


def _font(size):
    font = ImageFont.truetype(FONT_PATH, size)
    try:
        font.set_variation_by_axes([FONT_WEIGHT])
    except (OSError, AttributeError):
        pass
    return font


def _wear(shape, seed, amount):
    """Маска сохранности краски 0..1: сколы и протёртые места. amount — доля стёртого."""
    n = max(shape)
    chips = noise(n, seed, beta=1.4, low=6, high=120)[:shape[0], :shape[1]]
    large = noise(n, seed + 1, beta=2.8, low=1, high=8)[:shape[0], :shape[1]]
    field = 0.6 * chips + 0.4 * large
    threshold = np.quantile(field, amount)
    return smoothstep(threshold - 0.03, threshold + 0.05, field)


def _edge_fade(shape, margin):
    """Плавное затухание к краям картинки: у декали не должно быть видимой рамки."""
    height, width = shape
    y = np.minimum(np.arange(height), np.arange(height)[::-1])[:, None] / float(margin)
    x = np.minimum(np.arange(width), np.arange(width)[::-1])[None, :] / float(margin)
    return np.clip(np.minimum(x, y), 0.0, 1.0)


def _rgba(color, alpha):
    """Цвет: один на всю картинку (кортеж) или массив H x W x 3; alpha — массив H x W."""
    if isinstance(color, tuple):
        color = np.broadcast_to(np.array(color), alpha.shape + (3,))
    return np.concatenate([color, alpha[..., None]], axis=-1)


def _mask(size, painter):
    """Рисует маску PIL в двойном разрешении и уменьшает (сглаживание). size = (ширина, высота)."""
    scale = 2
    image = Image.new("L", (size[0] * scale, size[1] * scale), 0)
    painter(ImageDraw.Draw(image), scale)
    return np.asarray(image.resize(size, Image.LANCZOS), dtype=np.float64) / 255.0


def _save(name, pixels, roughness=None):
    """Пишет albedo (RGBA) и, если задана шероховатость, ORM декали."""
    texlib.save_png("%s/%s_albedo.png" % (OUT, name), pixels, vram=False)
    if roughness is not None:
        texlib.save_png("%s/%s_orm.png" % (OUT, name), orm(1.0, roughness, 0.0), vram=False)


def _prefab(name, size, depth, has_orm):
    """Сцена-префаб: один узел Decal. size = (ширина, высота рисунка) в метрах."""
    node = "".join(part.capitalize() for part in name.split("_"))
    lines = ["[gd_scene format=3]", "",
            "[ext_resource type=\"Texture2D\" path=\"res://assets/textures/%s/%s_albedo.png\" id=\"1_albedo\"]" % (
                    OUT, name)]
    if has_orm:
        lines.append("[ext_resource type=\"Texture2D\" path=\"res://assets/textures/%s/%s_orm.png\" id=\"2_orm\"]" % (
                OUT, name))
    lines += ["", "[node name=\"%s\" type=\"Decal\"]" % node,
            "size = Vector3(%s, %s, %s)" % (_number(size[0]), _number(depth), _number(size[1])),
            "texture_albedo = ExtResource(\"1_albedo\")"]
    if has_orm:
        lines.append("texture_orm = ExtResource(\"2_orm\")")
    lines += ["normal_fade = 0.5", "upper_fade = 0.01", "lower_fade = 0.01", "distance_fade_enabled = true",
            "distance_fade_begin = 28.0", "distance_fade_length = 6.0", ""]
    os.makedirs(PREFAB_DIR, exist_ok=True)
    path = os.path.join(PREFAB_DIR, name + ".tscn")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    print("PREFAB", os.path.relpath(path, texlib.REPO_ROOT).replace(os.sep, "/"))


def _number(value):
    text = ("%.4f" % value).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


# ---------- Разметка ----------

def hazard_stripe():
    """Жёлто-чёрная полоса 2 x 0,3 м: порог опасной зоны."""
    width, height = 1024, 160
    y, x = np.mgrid[0:height, 0:width]
    stripes = ((x + y) // 64) % 2
    color = np.where(stripes[..., None] == 0, np.array(YELLOW), np.array(BLACK))
    wear = _wear((height, width), 301, 0.2)
    alpha = wear * _edge_fade((height, width), 5) * 0.95
    _save("hazard_stripe", _rgba(color, alpha), 0.5 + 0.2 * (1.0 - wear))
    _prefab("hazard_stripe", (2.0, 0.3125), FLOOR_DEPTH, True)


def hazard_ring():
    """Кольцо разметки вокруг опасного агрегата: наружный диаметр 3,7 м, жёлто-чёрные сегменты."""
    n = 1024
    y, x = np.mgrid[0:n, 0:n]
    dx = (x - n / 2.0 + 0.5) / (n / 2.0)
    dy = (y - n / 2.0 + 0.5) / (n / 2.0)
    radius = np.sqrt(dx * dx + dy * dy)
    angle = np.arctan2(dy, dx)
    band = smoothstep(0.84, 0.85, radius) * smoothstep(0.97, 0.96, radius)
    segments = (np.floor((angle / (2.0 * np.pi) + 0.5) * 48.0 + radius * 6.0) % 2)
    color = np.where(segments[..., None] == 0, np.array(YELLOW), np.array(BLACK))
    wear = _wear((n, n), 311, 0.25)
    _save("hazard_ring", _rgba(color, band * wear * 0.95), 0.5 + 0.2 * (1.0 - wear))
    _prefab("hazard_ring", (3.7, 3.7), FLOOR_DEPTH, True)


def arrow_floor():
    """Стрелка направления на полу, 1,2 x 0,6 м. Остриё смотрит по локальной оси +X декали."""
    width, height = 512, 256

    def paint(draw, scale):
        s = scale
        draw.rectangle([40 * s, 98 * s, 330 * s, 158 * s], fill=255)
        draw.polygon([(310 * s, 40 * s), (472 * s, 128 * s), (310 * s, 216 * s)], fill=255)

    mask = _mask((width, height), paint)
    wear = _wear((height, width), 321, 0.3)
    _save("arrow_floor", _rgba(WHITE, mask * wear * 0.9), 0.5 + 0.2 * (1.0 - wear))
    _prefab("arrow_floor", (1.2, 0.6), FLOOR_DEPTH, True)


# ---------- Надписи ----------

def _label(name, text, color, size_m, font_size, seed, frame=True, subtitle=None):
    width, height = 512, int(round(512 * size_m[1] / size_m[0]))

    def paint(draw, scale):
        font = _font(font_size * scale)
        box = draw.textbbox((0, 0), text, font=font)
        text_height = box[3] - box[1]
        top = (height * scale - text_height) / 2.0 - box[1]
        if subtitle:
            top -= 30 * scale
        draw.text(((width * scale - (box[2] - box[0])) / 2.0 - box[0], top), text, font=font, fill=255)
        if subtitle:
            small = _font(34 * scale)
            small_box = draw.textbbox((0, 0), subtitle, font=small)
            draw.text(((width * scale - (small_box[2] - small_box[0])) / 2.0 - small_box[0],
                    height * scale - 62 * scale - small_box[1]), subtitle, font=small, fill=255)
        if frame:
            inset = 8 * scale
            draw.rounded_rectangle([inset, inset, width * scale - inset, height * scale - inset], radius=14 * scale,
                    outline=255, width=5 * scale)

    mask = _mask((width, height), paint)
    wear = _wear((height, width), seed, 0.12)
    _save(name, _rgba(color, mask * wear * 0.92))
    _prefab(name, size_m, WALL_DEPTH, False)


def labels():
    _label("label_meeting", "ПЕРЕГОВОРНАЯ", BLACK, (1.5, 0.26), 40, 331)
    _label("label_reactor", "РЕАКТОР", BLACK, (1.0, 0.26), 62, 332)
    _label("label_danger", "ОПАСНО", RED, (1.0, 0.3), 72, 333)
    _label("label_storage", "СКЛАД", BLACK, (0.8, 0.26), 62, 334)
    _label("label_quarters", "КАЮТЫ", BLACK, (0.8, 0.26), 62, 335)
    _label("label_exit", "ВЫХОД", (0.16, 0.5, 0.3), (0.8, 0.26), 62, 336)
    for index in range(1, 7):
        _label("number_%02d" % index, "%02d" % index, (0.2, 0.22, 0.34), (0.8, 0.6), 200, 340 + index, frame=False,
                subtitle="ОТСЕК")


# ---------- Пятна и потёртости ----------

def _blob(n, seed, core, softness):
    """Пятно неправильной формы 0..1 с центром в середине картинки."""
    y, x = np.mgrid[0:n, 0:n]
    radius = np.sqrt((x - n / 2.0) ** 2 + (y - n / 2.0) ** 2) / (n / 2.0)
    wobble = noise(n, seed, beta=2.6, low=1, high=10)
    return smoothstep(core + softness, core - softness, radius + (wobble - 0.5) * 0.7)


def stain_oil():
    """Масляное пятно на полу, 1,3 м: тёмное и глянцевое — в нём отражаются лампы."""
    n = 512
    body = _blob(n, 351, 0.52, 0.16)
    ringed = np.clip(body + 0.5 * _blob(n, 352, 0.3, 0.1), 0.0, 1.0)
    drops = smoothstep(0.83, 0.9, noise(n, 353, beta=1.2, low=10, high=60)) * _blob(n, 354, 0.8, 0.15)
    alpha = np.clip(ringed * 0.72 + drops * 0.6, 0.0, 0.85)
    sheen = noise(n, 355, beta=2.2, low=2, high=20)
    color = np.stack([0.035 + 0.02 * sheen, 0.035 + 0.015 * sheen, 0.04 + 0.03 * sheen], axis=-1)
    _save("stain_oil", _rgba(color, alpha), 0.06 + 0.12 * sheen)
    _prefab("stain_oil", (1.3, 1.3), FLOOR_DEPTH, True)


def stain_coffee():
    """Высохшая лужица кофе, 0,5 м: светлая середина и тёмная кайма."""
    n = 256
    body = _blob(n, 361, 0.6, 0.05)
    inner = _blob(n, 361, 0.5, 0.06)
    rim = np.clip(body - inner, 0.0, 1.0)
    alpha = np.clip(0.28 * body + 0.5 * rim, 0.0, 0.8)
    _save("stain_coffee", _rgba((0.2, 0.12, 0.06), alpha), 0.45 + 0.2 * rim)
    _prefab("stain_coffee", (0.5, 0.5), FLOOR_DEPTH, True)


def leak_wall():
    """Ржавый подтёк на стене, 0,7 x 1,5 м: начинается у шва и тает книзу."""
    width, height = 256, 512
    rng = np.random.default_rng(371)
    image = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(image)
    for _ in range(16):
        x = rng.normal(width / 2.0, width / 7.0)
        length = rng.uniform(0.35, 0.95) * height
        line_width = rng.uniform(2.0, 8.0)
        strength = rng.uniform(70, 230)
        steps = 24
        for step in range(steps):
            fade = (1.0 - step / steps) ** 1.3
            y0 = 14 + length * step / steps
            y1 = 14 + length * (step + 1) / steps + 1
            x += rng.uniform(-0.5, 0.5)
            draw.line([(x, y0), (x, y1)], fill=int(strength * fade), width=max(1, int(line_width * (0.4 + 0.6 * fade))))
    streaks = blur(np.asarray(image, dtype=np.float64) / 255.0, 3.0, 1.6)
    streaks = np.clip(streaks * 1.5, 0.0, 1.0) * _edge_fade((height, width), 14)
    tone = noise(512, 372, beta=2.2, low=2, high=30)[:height, :width]
    color = np.stack([0.34 + 0.12 * tone, 0.2 + 0.06 * tone, 0.1 + 0.02 * tone], axis=-1)
    _save("leak_wall", _rgba(color, streaks * 0.62), 0.7 + 0.2 * tone)
    _prefab("leak_wall", (0.7, 1.4), WALL_DEPTH, True)


def scuffs_floor():
    """Следы подошв и колёс на полу, 1,6 м: тёмные дуги и короткие штрихи."""
    n = 512
    rng = np.random.default_rng(381)
    image = Image.new("L", (n * 2, n * 2), 0)
    draw = ImageDraw.Draw(image)
    heading = rng.uniform(0, np.pi)
    for _ in range(22):
        x, y = rng.uniform(0.22, 0.78, 2) * n * 2
        # Следы тянутся в основном вдоль одного направления — по ходу движения людей.
        angle = heading + rng.normal(0.0, 0.45)
        length = rng.uniform(60, 330)
        curve = rng.uniform(-0.45, 0.45)
        points = []
        for step in range(9):
            t = step / 8.0 - 0.5
            points.append((x + np.cos(angle) * t * length - np.sin(angle) * curve * length * (t * t - 0.25),
                    y + np.sin(angle) * t * length + np.cos(angle) * curve * length * (t * t - 0.25)))
        draw.line(points, fill=int(rng.uniform(50, 170)), width=int(rng.uniform(5, 22)), joint="curve")
    marks = np.asarray(image.resize((n, n), Image.LANCZOS), dtype=np.float64) / 255.0
    marks = blur(marks, 2.5) * (0.35 + 0.65 * noise(n, 382, beta=1.0, low=20, high=200))
    alpha = np.clip(marks * 1.0, 0.0, 0.5) * _edge_fade((n, n), 40)
    _save("scuffs_floor", _rgba((0.05, 0.05, 0.06), alpha), 0.5 + 0.3 * marks)
    _prefab("scuffs_floor", (1.6, 1.6), FLOOR_DEPTH, True)


def grime_corner():
    """Грязь в углу у плинтуса, 2 x 0,5 м: кладётся на пол вдоль стены (тёмный край — к +Z)."""
    width, height = 512, 128
    y = np.arange(height)[:, None] / float(height)
    clouds = noise(512, 391, beta=2.4, low=2, high=40)[:height, :width]
    x = np.minimum(np.arange(width), np.arange(width)[::-1])[None, :] / 60.0
    alpha = np.clip((y ** 2.2) * (0.35 + 0.65 * clouds), 0.0, 1.0) * 0.6 * np.clip(x, 0.0, 1.0)
    _save("grime_corner", _rgba((0.06, 0.055, 0.05), alpha), np.full(alpha.shape, 0.85))
    _prefab("grime_corner", (2.0, 0.5), FLOOR_DEPTH, True)


def main():
    for build in (hazard_stripe, hazard_ring, arrow_floor, labels, stain_oil, stain_coffee, leak_wall, scuffs_floor,
            grime_corner):
        build()


if __name__ == "__main__":
    main()
