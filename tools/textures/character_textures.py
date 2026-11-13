#!/usr/bin/env python3
"""Текстуры персонажа и ручного оружия: тайловые PBR-наборы (albedo, normal, ORM), сколы краски
для кромок (RGBA), атлас наклеек и подсветка стекла шлема. Только numpy + PIL, результат
одинаковый при каждом запуске.

Запуск из корня репозитория:
    python3 tools/textures/character_textures.py            # в assets/textures/characters/
    python3 tools/textures/character_textures.py <папка>

Рядом с каждой картинкой пишется .import (если его ещё нет): мип-уровни, сжатие VRAM, для
нормалей — режим карты нормалей. Godot при импорте дописывает в него uid и остальные поля.

Все albedo нейтральные (почти белые): цвет задаёт материал (albedo_color), а у костюма — игра
(цвет игрока умножается на текстуру). ORM: R — затенение, G — шероховатость, B — металл.
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from character_atlas import DECAL_ATLAS_SIZE, DECAL_CELLS

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEFAULT_OUT_DIR = os.path.join(ROOT, "assets", "textures", "characters")
FONT_BOLD = os.path.join(ROOT, "assets", "fonts", "Unbounded.ttf")
FONT_TEXT = os.path.join(ROOT, "assets", "fonts", "Onest.ttf")

LARGE = 1024    # то, что видно в упор от первого лица
SMALL = 512     # мелкая деталь

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/normal_map={normal_map}
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
detect_3d/compress_to=0
"""


# ---------------------------------------------------------------------------------------------
# Кирпичики
# ---------------------------------------------------------------------------------------------

def fractal(size, beta, seed, stretch=(1.0, 1.0), band=None):
    """Тайловый шум 0..1 через обратное БПФ: спектр ~ 1/f^beta. stretch вытягивает узор вдоль
    осей (y, x); band = (низ, верх) в циклах на тайл оставляет только полосу частот."""
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(size)[:, None] * size * stretch[0]
    fx = np.fft.rfftfreq(size)[None, :] * size * stretch[1]
    freq = np.sqrt(fx * fx + fy * fy)
    freq[0, 0] = 1.0
    spectrum = (rng.normal(size=freq.shape) + 1j * rng.normal(size=freq.shape)) / freq ** (beta * 0.5)
    if band is not None:
        spectrum *= (freq >= band[0]) & (freq <= band[1])
    spectrum[0, 0] = 0.0
    image = np.fft.irfft2(spectrum, s=(size, size))
    image -= image.min()
    return image / max(image.max(), 1.0e-9)


def blur(image, radius):
    """Тайловое размытие по Гауссу (через БПФ)."""
    size = image.shape[0]
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.rfftfreq(size)[None, :]
    kernel = np.exp(-2.0 * (math.pi * radius) ** 2 * (fx * fx + fy * fy))
    return np.fft.irfft2(np.fft.rfft2(image) * kernel, s=image.shape)


def strokes(size, count, seed, length=(20.0, 160.0), width=1, softness=0.6, angle=None, curve=0.0):
    """Тайловые штрихи-царапины 0..1. angle = (центр, разброс) в радианах или None — любые."""
    rng = np.random.default_rng(seed)
    canvas = Image.new("L", (size * 3, size * 3), 0)
    draw = ImageDraw.Draw(canvas)
    for _ in range(count):
        x, y = rng.uniform(size, 2 * size, 2)
        direction = rng.uniform(0.0, math.pi) if angle is None else rng.normal(angle[0], angle[1])
        span = rng.uniform(*length)
        level = int(rng.uniform(90, 255))
        bend = rng.normal(0.0, curve)
        points = []
        steps = 6
        for step in range(steps + 1):
            t = step / steps
            turn = direction + bend * (t - 0.5)
            points.append((x + math.cos(turn) * span * (t - 0.5), y + math.sin(turn) * span * (t - 0.5)))
        for offset_x in (-size, 0, size):
            for offset_y in (-size, 0, size):
                draw.line([(px + offset_x, py + offset_y) for px, py in points], fill=level, width=width)
    canvas = canvas.filter(ImageFilter.GaussianBlur(softness)).crop((size, size, 2 * size, 2 * size))
    return np.asarray(canvas, dtype=np.float32) / 255.0


def normal_map(height, strength):
    """Карта нормалей (OpenGL, +Y вверх) из тайловой карты высот."""
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
    length = np.sqrt(dx * dx + dy * dy + 1.0)
    normal = np.stack([-dx / length, dy / length, 1.0 / length], -1)
    return to_bytes(normal * 0.5 + 0.5)


def to_bytes(image):
    return (np.clip(image, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def grey(value):
    return np.stack([value, value, value], -1)


def orm(occlusion, roughness, metallic):
    shape = roughness.shape
    return to_bytes(np.stack([np.broadcast_to(occlusion, shape), roughness, np.broadcast_to(metallic, shape)], -1))


class Writer:
    def __init__(self, out_dir):
        self.out_dir = out_dir
        os.makedirs(out_dir, exist_ok=True)

    def save(self, name, pixels, is_normal=False):
        path = os.path.join(self.out_dir, name)
        Image.fromarray(pixels).save(path, optimize=False, compress_level=9)
        sidecar = path + ".import"
        if not os.path.exists(sidecar):
            with open(sidecar, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(IMPORT_TEMPLATE.format(normal_map=1 if is_normal else 0))
        print("TEXTURE", os.path.relpath(path, ROOT))

    def save_set(self, name, albedo, height, strength, occlusion, roughness, metallic):
        self.save("%s_albedo.png" % name, to_bytes(albedo))
        self.save("%s_normal.png" % name, normal_map(height, strength), is_normal=True)
        self.save("%s_orm.png" % name, orm(occlusion, roughness, metallic))


# ---------------------------------------------------------------------------------------------
# Наборы
# ---------------------------------------------------------------------------------------------

def make_paint(writer):
    """Крашеный композит скафандра: ровная эмаль с лёгкой «шагренью», крупные пятна потёртостей
    (матовые и заполированные), редкие короткие царапины. Сколы до металла сюда не входят: они
    лежат на кромках отдельной оболочкой (make_chips). Тайл — 0.5 м."""
    size = LARGE
    stain = fractal(size, 2.6, 11)
    smudge = fractal(size, 1.8, 12, band=(2, 60))
    peel = fractal(size, 0.6, 13, band=(90, 260))
    fine = strokes(size, 120, 14, length=(10.0, 60.0), width=1, softness=0.6, curve=0.2)
    deep = strokes(size, 7, 15, length=(20.0, 90.0), width=2, softness=0.8, curve=0.3)
    # Редкие точечные сколы: в несколько раз реже, чем царапины.
    chip_field = fractal(size, 1.7, 16, band=(6, 140)) * 0.65 + fractal(size, 2.4, 17) * 0.35
    chips = np.clip((chip_field - np.quantile(chip_field, 0.9965)) * 30.0, 0.0, 1.0)
    chip_rim = np.clip(blur(chips, 2.0) * 2.2 - chips, 0.0, 1.0)
    # Потёртости: большие матовые пятна и заполированные до блеска места.
    scuff_field = fractal(size, 2.0, 18, band=(1, 14))
    scuff = np.clip((scuff_field - np.quantile(scuff_field, 0.6)) * 9.0, 0.0, 1.0)
    polish_field = fractal(size, 2.0, 19, band=(1, 10))
    polish = np.clip((polish_field - np.quantile(polish_field, 0.72)) * 9.0, 0.0, 1.0) * (1.0 - scuff)
    haze = fractal(size, 1.2, 20, band=(8, 120))

    value = 0.94 - 0.05 * stain - 0.03 * (smudge - 0.5) - 0.045 * fine - 0.13 * deep - 0.05 * scuff + 0.015 * polish
    value = value * (1.0 - 0.5 * chips) + 0.03 * chip_rim
    albedo = grey(value)
    albedo[..., 2] += 0.02 * chips
    height = 0.05 * peel - 0.3 * fine - 0.8 * deep - 0.7 * chips + 0.25 * chip_rim
    roughness = (0.3 + 0.26 * scuff - 0.1 * polish + 0.07 * (smudge - 0.5) + 0.1 * scuff * (haze - 0.5) + 0.14 * fine
            + 0.22 * deep - 0.04 * chips)
    occlusion = 1.0 - 0.3 * deep - 0.2 * chips
    writer.save_set("suit_paint", albedo, height, 3.0, occlusion, roughness, 0.85 * chips)


def make_chips(writer):
    """Сколы краски до металла для оболочки на кромках сегментов: RGBA, отсечение по альфе.
    Голый алюминий в середине скола, по краю — тёмная кайма грунта. Тайл — около 0.14 м."""
    size = SMALL
    field = fractal(size, 1.3, 91, band=(10, 150)) * 0.6 + fractal(size, 2.2, 92, band=(1, 7)) * 0.4
    grain = fractal(size, 0.6, 93, band=(40, 220))
    # Сколы занимают около седьмой части оболочки и собраны в гроздья; кайма грунта чуть шире скола.
    level = np.quantile(field, 0.86)
    core = np.clip((field - level - 0.014) * 60.0, 0.0, 1.0)
    cover = np.clip((field - level) * 60.0, 0.0, 1.0)
    value = 0.42 + 0.3 * core + 0.07 * (grain - 0.5)
    pixels = np.dstack([to_bytes(grey(value)), to_bytes(cover)])
    writer.save("suit_chips.png", pixels)


def make_fabric(writer):
    """Ткань гофр и перчаток: плотное полотняное плетение с сеткой «рипстоп». Тайл — 0.16 м."""
    size = SMALL
    pitch = 8
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    cell = (np.floor(xx / pitch) + np.floor(yy / pitch)) % 2.0
    along_x = np.abs(np.sin(math.pi * (xx + 0.5) / pitch))
    along_y = np.abs(np.sin(math.pi * (yy + 0.5) / pitch))
    # Где нить основы сверху — валик идёт по Y, иначе по X.
    weave = cell * along_x * (0.55 + 0.45 * along_y) + (1.0 - cell) * along_y * (0.55 + 0.45 * along_x)
    rip_period = pitch * 8
    rip = np.maximum(np.clip(1.0 - np.abs((xx % rip_period) - pitch) / pitch, 0.0, 1.0),
            np.clip(1.0 - np.abs((yy % rip_period) - pitch) / pitch, 0.0, 1.0))
    fuzz = fractal(size, 0.4, 21, band=(60, 250))
    wear = fractal(size, 2.4, 22)
    height = weave * 0.7 + rip * 0.35 + fuzz * 0.12
    value = 0.74 + 0.16 * weave + 0.05 * rip - 0.1 * wear - 0.06 * fuzz
    roughness = 0.9 - 0.1 * weave + 0.05 * wear
    occlusion = 0.72 + 0.28 * np.clip(weave * 1.4, 0.0, 1.0)
    writer.save_set("suit_fabric", grey(value), height, 2.6, occlusion, roughness, 0.0)


def make_metal(writer):
    """Точёный анодированный металл колец: тонкие риски вдоль U, редкие забоины. Тайл — 0.25 м."""
    size = SMALL
    lathe = fractal(size, 1.3, 31, stretch=(0.012, 1.0))
    lathe = (lathe - lathe.mean()) / lathe.std() * 0.18 + 0.5
    cloud = fractal(size, 2.4, 32)
    nicks = strokes(size, 50, 33, length=(6.0, 40.0), width=1, softness=0.6)
    drag = strokes(size, 26, 34, length=(80.0, 260.0), width=1, softness=0.7, angle=(0.0, 0.08))
    value = 0.9 - 0.1 * (lathe - 0.5) - 0.05 * cloud + 0.06 * nicks + 0.04 * drag
    height = 0.5 * lathe - 0.6 * nicks - 0.4 * drag
    roughness = 0.3 + 0.28 * (lathe - 0.5) + 0.1 * cloud + 0.22 * nicks + 0.12 * drag
    writer.save_set("suit_metal", grey(value), height, 1.6, 1.0 - 0.25 * nicks, roughness, 1.0)


def make_rubber(writer):
    """Резина ботинок, перчаток и шлангов: мелкое зерно «под кожу», затёртости. Тайл — 0.12 м."""
    size = SMALL
    pebble = fractal(size, 0.9, 41, band=(24, 110))
    pebble = np.clip((pebble - 0.5) * 3.0 + 0.5, 0.0, 1.0)
    cloud = fractal(size, 2.3, 42)
    dust = np.clip((fractal(size, 1.6, 43, band=(3, 80)) - 0.55) * 3.5, 0.0, 1.0)
    value = 0.78 + 0.12 * pebble - 0.08 * cloud + 0.12 * dust
    roughness = 0.72 - 0.14 * pebble + 0.1 * cloud + 0.14 * dust
    occlusion = 0.8 + 0.2 * pebble
    writer.save_set("suit_rubber", grey(value), pebble, 2.4, occlusion, roughness, 0.0)


def make_gunmetal(writer):
    """Воронёная сталь оружия: матовое покрытие, по рискам и кромкам проступает светлый металл.
    Риски идут вдоль U (вдоль ствола). Тайл — 0.2 м."""
    size = SMALL
    grain = fractal(size, 0.5, 51, band=(70, 250))
    brush = fractal(size, 1.4, 52, stretch=(0.03, 1.0))
    brush = (brush - brush.mean()) / brush.std() * 0.2 + 0.5
    cloud = fractal(size, 2.4, 53)
    rub = np.clip((fractal(size, 1.9, 54, band=(2, 50)) - 0.66) * 4.0, 0.0, 1.0)
    marks = strokes(size, 60, 55, length=(10.0, 120.0), width=1, softness=0.6, angle=(0.0, 0.5))
    bare = np.clip(rub * 0.45 + marks * 0.8, 0.0, 1.0)
    value = 0.5 + 0.06 * (brush - 0.5) - 0.06 * cloud + 0.42 * bare + 0.04 * grain
    height = 0.25 * grain + 0.2 * brush - 0.5 * marks
    roughness = 0.56 + 0.1 * (brush - 0.5) + 0.08 * cloud - 0.22 * bare + 0.06 * grain
    writer.save_set("weapon_gunmetal", grey(value), height, 1.5, 1.0 - 0.2 * marks, roughness, 1.0)


def make_polymer(writer):
    """Полимерная рамка: литьевая «шагрень». Тайл — 0.1 м."""
    size = SMALL
    stipple = fractal(size, 0.3, 61, band=(40, 180))
    stipple = np.clip((stipple - 0.5) * 2.6 + 0.5, 0.0, 1.0)
    cloud = fractal(size, 2.3, 62)
    shine = np.clip((fractal(size, 1.8, 63, band=(2, 40)) - 0.6) * 4.0, 0.0, 1.0)
    marks = strokes(size, 40, 64, length=(10.0, 90.0), width=1, softness=0.7)
    value = 0.8 + 0.08 * stipple - 0.06 * cloud + 0.1 * marks
    roughness = 0.62 - 0.1 * stipple + 0.06 * cloud - 0.16 * shine + 0.1 * marks
    writer.save_set("weapon_polymer", grey(value), stipple - 0.5 * marks, 2.0, 0.85 + 0.15 * stipple, roughness, 0.0)


def make_grip(writer):
    """Прорезиненная накладка рукояти: ромбическая насечка. Тайл — 0.04 м (ромб около 2.5 мм)."""
    size = SMALL
    count = 16
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    u = (xx + yy) / size * count
    v = (xx - yy) / size * count
    pyramid = np.minimum(1.0 - np.abs((u % 1.0) * 2.0 - 1.0), 1.0 - np.abs((v % 1.0) * 2.0 - 1.0))
    pyramid = np.clip(pyramid * 1.6, 0.0, 1.0)
    cloud = fractal(size, 2.2, 71)
    polish = np.clip((fractal(size, 1.8, 72, band=(1, 12)) - 0.5) * 3.0, 0.0, 1.0)
    height = blur(pyramid, 1.2) * (1.0 - 0.35 * polish)
    value = 0.62 + 0.3 * pyramid - 0.08 * cloud + 0.06 * polish
    roughness = 0.86 - 0.12 * pyramid - 0.25 * polish * pyramid
    writer.save_set("weapon_grip", grey(value), height, 5.0, 0.6 + 0.4 * pyramid, roughness, 0.0)


# ---------------------------------------------------------------------------------------------
# Наклейки и подсветка шлема
# ---------------------------------------------------------------------------------------------

INK = (26, 30, 44, 255)
PAPER = (232, 234, 238, 255)
RED = (214, 52, 60, 255)
AMBER = (240, 176, 32, 255)
BLUE = (40, 92, 190, 255)


def _font(path, size):
    return ImageFont.truetype(path, size)


def _text(draw, box, text, font, fill, anchor="mm"):
    x, y, width, height = box
    draw.text((x + width * 0.5, y + height * 0.5), text, font=font, fill=fill, anchor=anchor)


def make_decals(writer):
    """Атлас наклеек: эмблема отдела, номер, предупреждения. Юмор живёт в надписях."""
    scale = 2
    size = DECAL_ATLAS_SIZE * scale
    atlas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)

    def cell(name, pad=0):
        x, y, width, height = DECAL_CELLS[name]
        return (x * scale + pad, y * scale + pad, width * scale - 2 * pad, height * scale - 2 * pad)

    def plate(name, fill, radius=14, pad=8, outline=None):
        x, y, width, height = cell(name, pad * scale // 2)
        draw.rounded_rectangle((x, y, x + width, y + height), radius * scale, fill=fill, outline=outline,
                width=3 * scale)
        return (x, y, width, height)

    # Эмблема: планета с кольцом, вокруг — название отдела.
    x, y, width, height = cell("patch", 8)
    cx, cy, radius = x + width / 2, y + height / 2, width / 2
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(24, 34, 70, 255))
    draw.ellipse((cx - radius + 14, cy - radius + 14, cx + radius - 14, cy + radius - 14), outline=AMBER, width=10)
    inner = radius * 0.62
    draw.ellipse((cx - inner, cy - inner, cx + inner, cy + inner), fill=(14, 20, 44, 255))
    rng = np.random.default_rng(81)
    for _ in range(46):
        angle, distance = rng.uniform(0, math.tau), inner * math.sqrt(rng.uniform(0, 0.95))
        star = rng.uniform(2, 6)
        sx, sy = cx + math.cos(angle) * distance, cy + math.sin(angle) * distance
        draw.ellipse((sx - star, sy - star, sx + star, sy + star), fill=(235, 238, 250, 255))
    planet = inner * 0.5
    draw.ellipse((cx - planet, cy - planet + 10, cx + planet, cy + planet + 10), fill=(226, 92, 64, 255))
    draw.chord((cx - planet, cy - planet + 10, cx + planet, cy + planet + 10), 20, 160, fill=(180, 58, 52, 255))
    ring = Image.new("RGBA", atlas.size, (0, 0, 0, 0))
    ring_draw = ImageDraw.Draw(ring)
    ring_draw.ellipse((cx - planet * 1.75, cy - planet * 0.42 + 10, cx + planet * 1.75, cy + planet * 0.42 + 10),
            outline=AMBER, width=16)
    ring = ring.rotate(-18, center=(cx, cy + 10), resample=Image.BICUBIC)
    atlas.alpha_composite(ring)
    draw = ImageDraw.Draw(atlas)
    # Верх планеты перекрывает дальнюю часть кольца.
    draw.chord((cx - planet, cy - planet + 10, cx + planet, cy + planet + 10), 172, 352, fill=(226, 92, 64, 255))
    font = _font(FONT_BOLD, 52)
    for text, start, direction in (("ОТДЕЛ КАДРОВ", 205.0, 1.0), ("ОРБИТА · 7", 142.0, -1.0)):
        step = 11.4 * direction
        for index, letter in enumerate(text):
            angle = math.radians(start + step * index)
            glyph = Image.new("RGBA", (120, 120), (0, 0, 0, 0))
            ImageDraw.Draw(glyph).text((60, 60), letter, font=font, fill=(240, 240, 244, 255), anchor="mm")
            turn = -math.degrees(angle) - 90.0 if direction > 0 else -math.degrees(angle) + 90.0
            glyph = glyph.rotate(turn, resample=Image.BICUBIC)
            px = cx + math.cos(angle) * radius * 0.8
            py = cy + math.sin(angle) * radius * 0.8
            atlas.alpha_composite(glyph, (int(px - 60), int(py - 60)))
    draw = ImageDraw.Draw(atlas)

    # Номер борта по трафарету.
    box = cell("number", 16)
    _text(draw, box, "EVA-07", _font(FONT_BOLD, 150), INK)

    # Шеврон смены: выдуманный знак станции, без государственной символики.
    x, y, width, height = plate("chevron", (24, 34, 70, 255), radius=8, outline=AMBER)
    mark_x = x + width * 0.36
    for index in range(2):
        top = y + height * (0.2 + 0.26 * index)
        draw.line([(mark_x - width * 0.2, top + height * 0.24), (mark_x, top),
                (mark_x + width * 0.2, top + height * 0.24)], fill=AMBER, width=26, joint="curve")
    planet_x, planet_y, planet_radius = x + width * 0.76, y + height * 0.5, height * 0.2
    draw.ellipse((planet_x - planet_radius, planet_y - planet_radius, planet_x + planet_radius,
            planet_y + planet_radius), fill=(226, 92, 64, 255))
    draw.line([(planet_x - planet_radius * 1.7, planet_y + planet_radius * 0.35),
            (planet_x + planet_radius * 1.7, planet_y - planet_radius * 0.35)], fill=PAPER, width=10)

    box = plate("warning", AMBER, radius=10)
    _text(draw, (box[0], box[1], box[2], box[3] * 0.6), "НЕ ОТКРЫВАТЬ", _font(FONT_BOLD, 76), INK)
    _text(draw, (box[0], box[1] + box[3] * 0.52, box[2], box[3] * 0.44), "В КОСМОСЕ. СОВСЕМ.", _font(FONT_TEXT, 62), INK)

    box = plate("oxygen", (236, 238, 242, 255), radius=10, outline=BLUE)
    _text(draw, box, "O₂  →", _font(FONT_BOLD, 96), BLUE)

    x, y, width, height = cell("arrow", 12)
    draw.polygon([(x + width / 2, y), (x + width, y + height * 0.55), (x + width * 0.68, y + height * 0.55),
            (x + width * 0.68, y + height), (x + width * 0.32, y + height), (x + width * 0.32, y + height * 0.55),
            (x, y + height * 0.55)], fill=RED)

    box = plate("label", PAPER, radius=10)
    lines = ("СКАФАНДР СЛУЖЕБНЫЙ", "Инв. № 00042 · выдан под роспись", "Стирать нельзя. Гладить нельзя.",
            "Терять конечности — за свой счёт.")
    fonts = (_font(FONT_BOLD, 54), _font(FONT_TEXT, 46), _font(FONT_TEXT, 46), _font(FONT_TEXT, 46))
    for index, (line, font) in enumerate(zip(lines, fonts)):
        draw.text((box[0] + 36, box[1] + 30 + index * 82), line, font=font, fill=INK)

    x, y, width, height = plate("barcode", PAPER, radius=6)
    rng = np.random.default_rng(82)
    position = x + 28
    while position < x + width - 40:
        bar = int(rng.choice([4, 4, 8, 12]))
        draw.rectangle((position, y + 22, position + bar, y + height - 60), fill=INK)
        position += bar + int(rng.choice([4, 6, 10]))
    draw.text((x + 30, y + height - 54), "00042 · ОК-7", font=_font(FONT_TEXT, 40), fill=INK)

    x, y, width, height = cell("hazard", 6)
    draw.rounded_rectangle((x, y, x + width, y + height), 10, fill=AMBER)
    stripes = Image.new("RGBA", atlas.size, (0, 0, 0, 0))
    stripe_draw = ImageDraw.Draw(stripes)
    for offset in range(-height, width + height, 96):
        stripe_draw.polygon([(x + offset, y + height), (x + offset + 48, y + height), (x + offset + 48 + height, y),
                (x + offset + height, y)], fill=INK)
    mask = Image.new("L", atlas.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((x, y, x + width, y + height), 10, fill=255)
    atlas.paste(stripes, (0, 0), Image.composite(stripes.split()[3], Image.new("L", atlas.size, 0), mask))
    draw = ImageDraw.Draw(atlas)

    # Пульт на груди: шкалы и подписи.
    x, y, width, height = plate("panel", (40, 44, 54, 255), radius=10, pad=6)
    font = _font(FONT_TEXT, 34)
    for row, title in enumerate(("O2", "CO2", "КОФЕ", "ТЕРПЕНИЕ")):
        top = y + 36 + row * 108
        draw.text((x + 26, top), title, font=font, fill=(206, 210, 220, 255))
        draw.rounded_rectangle((x + 26, top + 48, x + width - 26, top + 78), 8, outline=(150, 156, 170, 255), width=4)
        level = (0.82, 0.3, 0.12, 0.05)[row]
        colour = ((92, 214, 150, 255), (92, 214, 150, 255), AMBER, RED)[row]
        draw.rounded_rectangle((x + 32, top + 54, x + 32 + (width - 64) * level, top + 72), 5, fill=colour)

    box = cell("serial", 10)
    _text(draw, box, "КРЕПИТЬ ДО ЩЕЛЧКА  >> <<", _font(FONT_BOLD, 58), (236, 238, 242, 255))

    # Экранчик блока управления: тёмное стекло, в материале светится.
    x, y, width, height = plate("screen", (10, 26, 30, 255), radius=10, pad=6)
    font = _font(FONT_BOLD, 60)
    draw.text((x + 30, y + 26), "98%", font=font, fill=(110, 240, 220, 255))
    draw.text((x + 30, y + 120), "КИСЛОРОД", font=_font(FONT_TEXT, 44), fill=(110, 240, 220, 255))
    for index in range(9):
        bar_height = 30 + int(60 * abs(math.sin(index * 1.3)))
        left = x + 30 + index * 46
        draw.rectangle((left, y + height - 40 - bar_height, left + 28, y + height - 40), fill=(60, 190, 180, 255))

    x, y, width, height = plate("caution", (236, 238, 242, 255), radius=12, outline=RED)
    draw.polygon([(x + 110, y + 60), (x + 190, y + 200), (x + 30, y + 200)], fill=AMBER, outline=INK)
    draw.text((x + 110, y + 150), "!", font=_font(FONT_BOLD, 100), fill=INK, anchor="mm")
    font = _font(FONT_BOLD, 50)
    draw.text((x + 220, y + 50), "РАНЕЦ", font=font, fill=RED)
    draw.text((x + 220, y + 120), "НЕ РЮКЗАК", font=_font(FONT_BOLD, 42), fill=INK)
    small = _font(FONT_TEXT, 40)
    for index, line in enumerate(("Обеды не класть.", "Кошку не класть.", "Отчёты — можно.")):
        draw.text((x + 40, y + 250 + index * 62), line, font=small, fill=INK)

    # Решётка вентиляции ранца (тёмные щели на светлой пластине).
    x, y, width, height = plate("vent", (206, 210, 218, 255), radius=12, pad=6)
    for row in range(9):
        top = y + 44 + row * 46
        draw.rounded_rectangle((x + 40, top, x + width - 40, top + 22), 10, fill=(22, 24, 30, 255))

    atlas = atlas.resize((DECAL_ATLAS_SIZE, DECAL_ATLAS_SIZE), Image.LANCZOS)
    writer.save("suit_decals.png", np.asarray(atlas).copy())


def make_visor_hud(writer):
    """Свечение на внутренней пластине шлема: неяркая разметка приборов вместо лица."""
    scale = 3
    size = 256 * scale
    image = Image.new("RGB", (size, size), (0, 0, 0))
    draw = ImageDraw.Draw(image)
    teal = (70, 220, 215)
    dim = (30, 110, 120)
    centre = size / 2
    # Линия горизонта и шкала крена.
    draw.arc((centre - 250, centre - 250, centre + 250, centre + 250), 200, 340, fill=dim, width=5)
    for index in range(-4, 5):
        angle = math.radians(270 + index * 15)
        inner, outer = 232, 262 if index % 2 == 0 else 250
        draw.line((centre + math.cos(angle) * inner, centre + math.sin(angle) * inner,
                centre + math.cos(angle) * outer, centre + math.sin(angle) * outer), fill=teal, width=5)
    draw.line((centre - 150, centre + 8, centre - 46, centre + 8), fill=teal, width=6)
    draw.line((centre + 46, centre + 8, centre + 150, centre + 8), fill=teal, width=6)
    draw.ellipse((centre - 14, centre - 6, centre + 14, centre + 22), outline=teal, width=5)
    # Столбики по бокам.
    for side in (-1, 1):
        for index in range(7):
            top = centre - 110 + index * 34
            length = 26 + 30 * abs(math.sin(index * 1.7 + side))
            left = centre + side * 268
            draw.rectangle((min(left, left - side * length), top, max(left, left - side * length), top + 14),
                    fill=teal if index < 5 else dim)
    font = _font(FONT_TEXT, 44)
    draw.text((centre, centre + 208), "О₂ 98%   ·   ПУЛЬС 72", font=font, fill=dim, anchor="mm")
    draw.text((centre, centre - 290), "СВЯЗЬ: ЕСТЬ", font=font, fill=dim, anchor="mm")
    image = image.filter(ImageFilter.GaussianBlur(1.6)).resize((256, 256), Image.LANCZOS)
    glow = image.filter(ImageFilter.GaussianBlur(5.0))
    pixels = np.clip(np.asarray(image, dtype=np.float32) + 0.5 * np.asarray(glow, dtype=np.float32), 0, 255)
    writer.save("visor_hud.png", pixels.astype(np.uint8))


def main():
    out_dir = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT_DIR
    writer = Writer(out_dir)
    make_paint(writer)
    make_chips(writer)
    make_fabric(writer)
    make_metal(writer)
    make_rubber(writer)
    make_gunmetal(writer)
    make_polymer(writer)
    make_grip(writer)
    make_decals(writer)
    make_visor_hud(writer)


if __name__ == "__main__":
    main()
