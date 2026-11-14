"""Помощники синтеза текстур (numpy + PIL): бесшовный шум, размытие, карты нормалей, запись PNG и .import.

Все функции детерминированы: шум берётся из numpy.random.default_rng(seed), размытие и нормали считаются
с заворотом через край, поэтому любая текстура повторяется без швов. Модуль только импортируют.
"""

import os

import numpy as np
from PIL import Image, ImageDraw

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEXTURE_DIR = os.path.join(REPO_ROOT, "assets", "textures")

# Значение roughness/mode «шероховатость лежит в зелёном канале» (0 — определить, 1 — выключено, 2 — красный...).
ROUGHNESS_FROM_GREEN = 3

# Параметры импорта текстуры в Godot 4.7 (секция [params] файла .import).
_IMPORT_PARAMS = [
    ("compress/mode", "2"),
    ("compress/high_quality", "false"),
    ("compress/lossy_quality", "0.7"),
    ("compress/uastc_level", "0"),
    ("compress/rdo_quality_loss", "0.0"),
    ("compress/hdr_compression", "1"),
    ("compress/normal_map", "0"),
    ("compress/channel_pack", "0"),
    ("mipmaps/generate", "true"),
    ("mipmaps/limit", "-1"),
    ("roughness/mode", "0"),
    ("roughness/src_normal", "\"\""),
    ("process/channel_remap/red", "0"),
    ("process/channel_remap/green", "1"),
    ("process/channel_remap/blue", "2"),
    ("process/channel_remap/alpha", "3"),
    ("process/fix_alpha_border", "true"),
    ("process/premult_alpha", "false"),
    ("process/normal_map_invert_y", "false"),
    ("process/hdr_as_srgb", "false"),
    ("process/hdr_clamp_exposure", "false"),
    ("process/size_limit", "0"),
    ("detect_3d/compress_to", "0"),
]


# ---------- Шум и фильтры ----------

def _frequencies(n):
    """Сетка частот в периодах на плитку для rfft2 картинки n x n."""
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.rfftfreq(n)[None, :] * n
    return fx, fy


def noise(n, seed, beta=2.0, low=0.0, high=None, stretch=(1.0, 1.0)):
    """Бесшовный спектральный шум 0..1. beta — наклон спектра (0 — белый, 2 — «облака», 3+ — крупные пятна).

    low и high ограничивают полосу частот (в периодах на плитку); stretch = (по вертикали, по горизонтали)
    растягивает шум: (1, 0.03) даёт горизонтальные штрихи, (0.03, 1) — вертикальные.
    """
    rng = np.random.default_rng(seed)
    fx, fy = _frequencies(n)
    f = np.sqrt((fx * stretch[1]) ** 2 + (fy * stretch[0]) ** 2)
    f[0, 0] = 1.0
    spectrum = (rng.normal(size=f.shape) + 1j * rng.normal(size=f.shape)) / f ** (beta / 2.0)
    radius = np.sqrt(fx * fx + fy * fy)
    if low > 0.0:
        spectrum = spectrum * (radius >= low)
    if high is not None:
        spectrum = spectrum * (radius <= high)
    spectrum[0, 0] = 0.0
    image = np.fft.irfft2(spectrum, s=(n, n))
    image -= image.min()
    peak = image.max()
    return image / peak if peak > 0.0 else image


def blur(image, sigma, sigma_x=None):
    """Размытие по Гауссу с заворотом через край. sigma — по вертикали (и по горизонтали, если sigma_x нет)."""
    n_y, n_x = image.shape
    sigma_y = float(sigma)
    sigma_x = sigma_y if sigma_x is None else float(sigma_x)
    fy = np.fft.fftfreq(n_y)[:, None]
    fx = np.fft.rfftfreq(n_x)[None, :]
    kernel = np.exp(-2.0 * np.pi ** 2 * ((fy * sigma_y) ** 2 + (fx * sigma_x) ** 2))
    return np.fft.irfft2(np.fft.rfft2(image) * kernel, s=image.shape)


def normalize(image):
    low, high = float(image.min()), float(image.max())
    return (image - low) / (high - low) if high > low else np.zeros_like(image)


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def remap(image, low, high):
    """Линейно переводит 0..1 в low..high."""
    return low + (high - low) * image


def grid(n):
    """Координаты пикселей (y, x) в долях плитки 0..1."""
    axis = (np.arange(n) + 0.5) / n
    return np.meshgrid(axis, axis, indexing="ij")


# ---------- Рисование с заворотом ----------

class WrapCanvas:
    """Чёрно-белый холст, на котором фигуры рисуются с заворотом через край (бесшовно).

    Рисуем в увеличенном масштабе scale и уменьшаем — это сглаживание. Координаты — в пикселях итоговой
    текстуры.
    """

    def __init__(self, n, scale=2):
        self.n = n
        self.scale = scale
        self.image = Image.new("L", (n * scale, n * scale), 0)
        self.draw = ImageDraw.Draw(self.image)

    def _offsets(self, x0, y0, x1, y1):
        xs = [0]
        ys = [0]
        if x0 < 0:
            xs.append(self.n)
        if x1 > self.n:
            xs.append(-self.n)
        if y0 < 0:
            ys.append(self.n)
        if y1 > self.n:
            ys.append(-self.n)
        return [(ox, oy) for ox in xs for oy in ys]

    def line(self, points, value, width):
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        pad = width + 1
        s = self.scale
        for ox, oy in self._offsets(min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad):
            self.draw.line([((x + ox) * s, (y + oy) * s) for x, y in points], fill=int(value),
                    width=max(1, int(round(width * s))), joint="curve")

    def ellipse(self, cx, cy, rx, ry, value):
        s = self.scale
        for ox, oy in self._offsets(cx - rx, cy - ry, cx + rx, cy + ry):
            self.draw.ellipse([((cx - rx + ox) * s, (cy - ry + oy) * s), ((cx + rx + ox) * s, (cy + ry + oy) * s)],
                    fill=int(value))

    def polygon(self, points, value):
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        s = self.scale
        for ox, oy in self._offsets(min(xs), min(ys), max(xs), max(ys)):
            self.draw.polygon([((x + ox) * s, (y + oy) * s) for x, y in points], fill=int(value))

    def array(self):
        """Холст как массив 0..1 размера n x n."""
        small = self.image.resize((self.n, self.n), Image.LANCZOS) if self.scale != 1 else self.image
        return np.clip(np.asarray(small, dtype=np.float64) / 255.0, 0.0, 1.0)


# ---------- Сборка карт ----------

def normal_map(height, strength):
    """Карта нормалей (формат OpenGL, как ждёт Godot) из карты высот. strength — крутизна рельефа:
    перепад высоты 1.0 на одном пикселе при strength = 1 даёт наклон 45°."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    length = np.sqrt(dx * dx + dy * dy + 1.0)
    normal = np.stack([-dx / length, dy / length, 1.0 / length], axis=-1)
    return to_bytes(normal * 0.5 + 0.5)


def to_bytes(image):
    return (np.clip(image, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def rgb(red, green=None, blue=None):
    """Складывает три канала 0..1 в картинку; один аргумент — серая картинка."""
    green = red if green is None else green
    blue = red if blue is None else blue
    return np.stack([red, green, blue], axis=-1)


def orm(ao, roughness, metallic):
    """Упаковка ORM: R — затенение (AO), G — шероховатость, B — металл. Скаляры разворачиваются в карты."""
    shape = None
    for channel in (ao, roughness, metallic):
        if isinstance(channel, np.ndarray):
            shape = channel.shape
    planes = [channel if isinstance(channel, np.ndarray) else np.full(shape, float(channel))
            for channel in (ao, roughness, metallic)]
    return to_bytes(np.stack(planes, axis=-1))


def linear_to_srgb(value):
    value = np.clip(value, 0.0, 1.0)
    return np.where(value <= 0.0031308, value * 12.92, 1.055 * np.power(value, 1.0 / 2.4) - 0.055)


def save_png(relative_path, pixels, is_normal=False, mipmaps=True, vram=True, roughness_normal=None):
    """Пишет PNG в assets/textures/<relative_path> и файл .import рядом с ним.

    roughness_normal — путь res:// карты нормалей того же набора (только для ORM): см. write_import."""
    path = os.path.join(TEXTURE_DIR, relative_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    array = pixels if pixels.dtype == np.uint8 else to_bytes(pixels)
    Image.fromarray(array).save(path, optimize=False, compress_level=6)
    write_import(path, is_normal=is_normal, mipmaps=mipmaps, vram=vram, roughness_normal=roughness_normal)
    print("TEXTURE", os.path.relpath(path, REPO_ROOT).replace(os.sep, "/"))


def write_import(png_path, is_normal=False, mipmaps=True, vram=True, roughness_normal=None):
    """Файл .import: сжатие VRAM, мип-уровни (без них плиточная текстура рябит), признак карты нормалей.

    roughness_normal: Godot при импорте ORM поднимает шероховатость (зелёный канал) в мелких мип-уровнях там,
    где карта нормалей «шумит». Издали рельеф превращается в матовость, а не в искрящие блики.

    Строки uid и path внутри уже существующего файла сохраняются: их проставляет сам Godot при импорте.
    """
    params = dict(_IMPORT_PARAMS)
    params["compress/mode"] = "2" if vram else "0"
    params["compress/normal_map"] = "1" if is_normal else "2"
    params["mipmaps/generate"] = "true" if mipmaps else "false"
    if roughness_normal:
        params["roughness/mode"] = str(ROUGHNESS_FROM_GREEN)
        params["roughness/src_normal"] = "\"%s\"" % roughness_normal
    import_path = png_path + ".import"
    header = ["[remap]", "", "importer=\"texture\"", "type=\"CompressedTexture2D\"", ""]
    if os.path.exists(import_path):
        with open(import_path, "r", encoding="utf-8") as handle:
            text = handle.read()
        if "[params]" in text:
            header = text.split("[params]")[0].rstrip("\n").split("\n") + [""]
    lines = header + ["[params]", ""] + ["%s=%s" % (key, params[key]) for key, _ in _IMPORT_PARAMS] + [""]
    with open(import_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
