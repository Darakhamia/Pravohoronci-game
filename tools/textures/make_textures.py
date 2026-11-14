"""Синтез плиточных PBR-текстур станции: albedo, normal и ORM (R — AO, G — шероховатость, B — металл).

Обычный Python 3 с numpy и PIL, запуск из корня репозитория:
    python3 tools/textures/make_textures.py                 все наборы -> assets/textures/surfaces/
    python3 tools/textures/make_textures.py floor wood      только наборы, в имени которых есть эти слова

Каждый набор — функция ниже. Зёрна шума заданы числами, поэтому повторный запуск даёт те же файлы.
Физический размер плитки (сколько метров занимает одна текстура) задаётся не здесь, а масштабом uv1_scale
материала: см. tools/textures/apply_materials.py, словарь SURFACES. Рядом с каждым PNG пишется .import
(сжатие VRAM, мип-уровни, признак карты нормалей) — см. texlib.write_import.

Цвет у большинства наборов почти белый: оттенок задаёт albedo_color материала, один набор обслуживает
несколько цветов. Исключения — пол, дерево и листва: у них цвет записан в самой текстуре.
"""

import sys

import numpy as np

import texlib
from texlib import WrapCanvas, blur, grid, noise, normal_map, normalize, orm, remap, rgb, save_png, smoothstep

OUT = "surfaces"
LARGE = 1024
SMALL = 512


def _strokes(n, seed, count, length, width, angle_deg, value=(120, 255), bend=0.0):
    """Случайные штрихи (царапины, потёртости): длина и ширина в пикселях, угол в градусах от горизонтали."""
    rng = np.random.default_rng(seed)
    canvas = WrapCanvas(n)
    for _ in range(count):
        x, y = rng.uniform(0, n, 2)
        angle = np.radians(rng.uniform(*angle_deg))
        size = rng.uniform(*length)
        curve = rng.uniform(-bend, bend)
        points = []
        steps = 6
        for step in range(steps + 1):
            t = step / steps - 0.5
            along = t * size
            across = curve * size * (t * t - 0.25)
            points.append((x + np.cos(angle) * along - np.sin(angle) * across,
                    y + np.sin(angle) * along + np.cos(angle) * across))
        canvas.line(points, rng.uniform(*value), rng.uniform(*width))
    return canvas.array()


def _drips(n, seed, count, length, width):
    """Подтёки: вертикальные полосы, плотные сверху и тающие книзу."""
    rng = np.random.default_rng(seed)
    canvas = WrapCanvas(n)
    for _ in range(count):
        x = rng.uniform(0, n)
        y = rng.uniform(0, n)
        size = rng.uniform(*length)
        line_width = rng.uniform(*width)
        strength = rng.uniform(110, 255)
        steps = 12
        for step in range(steps):
            fade = (1.0 - step / steps) ** 1.4
            y0 = y + size * step / steps
            y1 = y + size * (step + 1) / steps + 1.0
            wobble = rng.uniform(-0.6, 0.6)
            canvas.line([(x + wobble, y0), (x + wobble, y1)], strength * fade, max(1.0, line_width * (0.5 + 0.5 * fade)))
    return canvas.array()


def _islands(n, seed, coverage, scale_low=20, scale_high=90, cluster=0.75):
    """Редкие островки неправильной формы (сколы краски): собраны в несколько скоплений."""
    shape = noise(n, seed, beta=1.6, low=scale_low, high=scale_high)
    zones = noise(n, seed + 1, beta=3.0, low=1, high=5)
    mask = smoothstep(cluster, cluster + 0.12, zones)
    threshold = np.quantile(shape, 1.0 - coverage * 6.0)
    return smoothstep(threshold, threshold + 0.03, shape) * mask


def _save_set(name, albedo, height, strength, ao, roughness, metallic):
    save_png("%s/%s_albedo.png" % (OUT, name), albedo)
    save_png("%s/%s_normal.png" % (OUT, name), normal_map(height, strength), is_normal=True)
    save_png("%s/%s_orm.png" % (OUT, name), orm(ao, roughness, metallic),
            roughness_normal="res://assets/textures/%s/%s_normal.png" % (OUT, name))


# ---------- Наборы ----------

def paint_panel():
    """Крашеные металлические панели стен: ровная матовая эмаль, лёгкие разводы, редкие подтёки и потёртости."""
    n = LARGE
    clouds = noise(n, 101, beta=3.2, low=1, high=24)
    mottling = noise(n, 102, beta=1.8, low=6, high=60)
    drips = blur(_drips(n, 103, 9, (90, 330), (2.0, 5.0)), 2.5, 1.2)
    scuffs = blur(_strokes(n, 104, 10, (40, 170), (1.5, 3.5), (-12, 12), bend=0.15), 1.0)
    smudge = smoothstep(0.62, 0.9, noise(n, 105, beta=2.6, low=2, high=18))
    value = 0.955 - 0.045 * clouds ** 1.5 - 0.02 * mottling - 0.085 * drips - 0.10 * scuffs
    # Подтёки и грязь чуть теплее чистой краски.
    warm = 0.03 * clouds + 0.05 * drips
    albedo = rgb(value, value * (1.0 - 0.35 * warm), value * (1.0 - warm))
    # Панель слегка «ведёт»: по этим пологим волнам гуляет блик.
    warp = noise(n, 106, beta=3.4, low=1, high=7)
    height = warp * 18.0 + mottling * 0.6 + drips * 1.2 - scuffs * 0.8
    roughness = 0.44 + 0.08 * clouds + 0.05 * mottling + 0.16 * drips + 0.2 * scuffs - 0.12 * smudge
    _save_set("paint_panel", albedo, height, 1.0, 1.0, roughness, 0.0)


def micro_paint():
    """Слой мелких деталей для краски: «апельсиновая корка» шагом 2–5 мм (плитка 25 см)."""
    n = SMALL
    peel = noise(n, 111, beta=0.6, low=45, high=140)
    speck = noise(n, 112, beta=0.2, low=60, high=250)
    value = 1.0 - 0.035 * speck
    # Альфа 0,5: материал смешивает этот слой с основным пополам (см. apply_materials.py).
    detail = np.concatenate([rgb(value), np.full((n, n, 1), 0.5)], axis=-1)
    save_png("%s/micro_paint_detail.png" % OUT, detail)
    save_png("%s/micro_paint_normal.png" % OUT, normal_map(peel, 0.9), is_normal=True)


def enamel():
    """Цветная эмаль реквизита и дверных рам: полуглянец с «апельсиновой коркой», редкие волосяные царапины
    и сколы до металла. Царапины тоньше пикселя по силе: крупные читались бы как складки кожзама."""
    n = SMALL
    clouds = noise(n, 121, beta=3.0, low=1, high=20)
    peel = noise(n, 122, beta=0.8, low=50, high=140)
    scratches = blur(_strokes(n, 123, 9, (14, 70), (0.7, 1.0), (0, 180), value=(60, 170), bend=0.05), 0.4)
    chips = _islands(n, 124, 0.0012, cluster=0.82)
    value = (0.97 - 0.045 * clouds + 0.012 * scratches) * (1.0 - chips) + 0.34 * chips
    albedo = rgb(value, value, value + 0.02 * chips)
    height = peel * 0.2 - scratches * 0.15 - chips * 2.0
    roughness = 0.27 + 0.08 * clouds + 0.1 * scratches + 0.14 * chips
    _save_set("enamel", albedo, height, 0.8, 1.0 - 0.25 * chips, roughness, chips * 0.9)


def composite():
    """Тёмные композитные панели: фактурный пластик с мелким зерном, пыль, светлые потёртости."""
    n = LARGE
    grain = noise(n, 131, beta=0.4, low=130, high=420)
    dust = noise(n, 132, beta=2.6, low=1, high=30)
    rub = smoothstep(0.55, 0.85, noise(n, 133, beta=3.0, low=1, high=10))
    scuffs = blur(_strokes(n, 134, 16, (30, 160), (1.2, 3.0), (-25, 25), bend=0.2), 0.9)
    value = 0.80 + 0.03 * (grain - 0.5) + 0.11 * dust ** 2 + 0.07 * scuffs - 0.03 * rub
    albedo = rgb(value, value, value * (1.0 - 0.03 * dust))
    height = grain * 1.0 - scuffs * 0.6
    roughness = 0.66 + 0.06 * (grain - 0.5) + 0.12 * dust ** 2 - 0.13 * rub + 0.1 * scuffs
    _save_set("composite", albedo, height, 0.7, 1.0, roughness, 0.0)


def _floor_wear(n, seed):
    """Маска износа пола: широкие протоптанные зоны и мелкие пятна внутри них."""
    paths = noise(n, seed, beta=3.4, low=1, high=6)
    patches = noise(n, seed + 1, beta=2.2, low=4, high=40)
    return smoothstep(0.3, 0.8, 0.65 * paths + 0.35 * patches)


def floor_rubber():
    """Противоскользящая резина с круглыми «монетами» (шаг 31 мм): пыль в углублениях, натёртые вершины."""
    n = LARGE
    y, x = grid(n)
    cells = 32
    fx = (x * cells) % 1.0 - 0.5
    fy = (y * cells) % 1.0 - 0.5
    distance = np.sqrt(fx * fx + fy * fy) * (n / cells)
    stud = smoothstep(11.5, 9.0, distance)
    wear = _floor_wear(n, 141)
    dirt = noise(n, 143, beta=2.4, low=1, high=40)
    grain = noise(n, 144, beta=0.3, low=150, high=500)
    base = np.array([0.30, 0.345, 0.54])
    tone = 0.86 + 0.14 * stud * (0.5 + 0.5 * wear) - 0.14 * dirt * (1.0 - stud) + 0.04 * (grain - 0.5)
    dust = 0.03 * (1.0 - stud) * smoothstep(0.5, 0.9, noise(n, 145, beta=2.8, low=1, high=12))
    albedo = np.stack([base[c] * tone + dust for c in range(3)], axis=-1)
    height = stud * 3.0 + grain * 0.35
    ao = 0.72 + 0.28 * blur(stud, 2.0)
    # Натёртые вершины «монет» почти глянцевые: в них живут отражения ламп и экранов.
    roughness = 0.5 - stud * (0.18 + 0.1 * wear) + 0.08 * dirt * (1.0 - stud) + 0.05 * (grain - 0.5)
    _save_set("floor_rubber", albedo, height, 1.0, ao, roughness, 0.0)


def floor_plate():
    """Крашеный рифлёный лист («чечевица», шаг 62 мм): краска стёрта на вершинах рифлей, грязь между ними."""
    n = LARGE
    y, x = grid(n)
    cells = 16
    pitch = n / cells

    def lugs(offset, angle_deg):
        fx = ((x * cells + offset) % 1.0 - 0.5) * pitch
        fy = ((y * cells + offset) % 1.0 - 0.5) * pitch
        angle = np.radians(angle_deg)
        along = fx * np.cos(angle) + fy * np.sin(angle)
        across = -fx * np.sin(angle) + fy * np.cos(angle)
        return np.sqrt((along / 19.0) ** 2 + (across / 4.6) ** 2)

    distance = np.minimum(lugs(0.0, 45.0), lugs(0.5, -45.0))
    lug = smoothstep(1.0, 0.45, distance)
    crest = smoothstep(0.62, 0.25, distance)
    wear = _floor_wear(n, 151)
    dirt = noise(n, 153, beta=2.4, low=1, high=40)
    grain = noise(n, 154, beta=0.5, low=120, high=450)
    scratches = blur(_strokes(n, 155, 40, (30, 200), (0.8, 1.6), (0, 180), bend=0.1), 0.5)
    # Голый металл проступает на вершинах рифлей там, где ходят, и в царапинах.
    bare = np.clip(crest * smoothstep(0.25, 0.75, wear) + 0.5 * scratches * wear, 0.0, 1.0)
    paint = np.array([0.265, 0.305, 0.49])
    steel = np.array([0.62, 0.63, 0.66])
    tone = 0.9 - 0.16 * dirt * (1.0 - lug) + 0.05 * (grain - 0.5) + 0.06 * lug
    albedo = np.stack([paint[c] * tone * (1.0 - bare) + steel[c] * bare for c in range(3)], axis=-1)
    height = lug * 3.2 + grain * 0.3 - scratches * 0.4
    ao = 0.78 + 0.22 * blur(lug, 2.5)
    # Затёртая ногами краска между рифлями — полуглянец (0,25–0,35): на ней видны дорожки от ламп и ядра.
    roughness = (0.29 + 0.18 * dirt * (1.0 - lug) + 0.05 * (grain - 0.5) - 0.08 * wear * (1.0 - lug)) * (1.0 - bare) \
            + 0.28 * bare
    _save_set("floor_plate", albedo, height, 0.95, ao, roughness, bare * 0.95)


def metal_brushed():
    """Шлифованная сталь: штрихи вдоль U, редкие царапины. Металл везде."""
    n = SMALL
    streaks = noise(n, 161, beta=1.2, stretch=(1.0, 0.012))
    fine = noise(n, 162, beta=0.3, stretch=(1.0, 0.03), low=40)
    clouds = noise(n, 163, beta=3.0, low=1, high=12)
    scratches = blur(_strokes(n, 164, 22, (20, 140), (0.8, 1.3), (0, 180), bend=0.1), 0.5)
    value = 0.93 - 0.07 * streaks - 0.03 * clouds + 0.05 * scratches
    height = streaks * 0.8 + fine * 0.5 - scratches * 1.0
    roughness = 0.33 + 0.12 * streaks + 0.07 * clouds + 0.15 * scratches
    _save_set("metal_brushed", rgb(value), height, 1.6, 1.0, roughness, 1.0)


def metal_anodized():
    """Анодированный алюминий: ровный сатин после дробеструйки, волосяные светлые царапины."""
    n = SMALL
    satin = noise(n, 171, beta=0.2, low=90, high=256)
    clouds = noise(n, 172, beta=3.0, low=1, high=10)
    scratches = blur(_strokes(n, 173, 18, (15, 110), (0.7, 1.2), (0, 180), bend=0.08), 0.45)
    value = 0.95 - 0.04 * clouds + 0.05 * scratches + 0.02 * (satin - 0.5)
    height = satin * 0.5 - scratches * 0.8
    roughness = 0.36 + 0.08 * clouds + 0.05 * (satin - 0.5) + 0.2 * scratches
    _save_set("metal_anodized", rgb(value), height, 1.3, 1.0, roughness, 1.0)


def plastic():
    """Литой пластик корпусов: мелкая «искровая» фактура, залоснившиеся места от рук."""
    n = SMALL
    spark = noise(n, 181, beta=0.3, low=70, high=256)
    clouds = noise(n, 182, beta=2.8, low=1, high=14)
    gloss = smoothstep(0.6, 0.9, noise(n, 183, beta=3.0, low=1, high=8))
    scratches = blur(_strokes(n, 184, 10, (15, 90), (0.8, 1.3), (0, 180), bend=0.1), 0.5)
    value = 0.96 - 0.04 * clouds + 0.02 * (spark - 0.5) + 0.04 * scratches
    height = spark * 0.9 - scratches * 0.7
    roughness = 0.5 + 0.07 * clouds + 0.06 * (spark - 0.5) - 0.16 * gloss + 0.12 * scratches
    _save_set("plastic", rgb(value), height, 1.5, 1.0, roughness, 0.0)


def vinyl():
    """Винил (искусственная кожа) сидений и матрасов: сетка мягких складок."""
    n = SMALL
    cells = noise(n, 191, beta=1.0, low=18, high=60)
    creases = 1.0 - np.abs(2.0 * cells - 1.0) ** 0.6
    creases = normalize(blur(creases, 0.8))
    fine = noise(n, 192, beta=0.3, low=90, high=256)
    clouds = noise(n, 193, beta=3.0, low=1, high=10)
    value = 0.97 - 0.12 * (1.0 - creases) ** 2 - 0.04 * clouds
    height = creases * 2.0 + fine * 0.15
    ao = 0.8 + 0.2 * creases
    roughness = 0.56 + 0.12 * (1.0 - creases) + 0.06 * clouds + 0.04 * (fine - 0.5)
    _save_set("vinyl", rgb(value), height, 0.8, ao, roughness, 0.0)


def laminate():
    """Столешница из пластика HPL: ровный полуглянец, едва заметная «крошка» в цвете, кольца от кружек
    и матовые следы протирки. Рельефа почти нет — на таком столе лежат блики ламп."""
    n = LARGE
    speck = noise(n, 281, beta=0.2, low=120, high=480)
    flakes = smoothstep(0.80, 0.92, speck)
    clouds = noise(n, 282, beta=3.0, low=1, high=10)
    wipe = smoothstep(0.5, 0.9, noise(n, 283, beta=2.4, stretch=(1.0, 0.3), low=2, high=30))
    rng = np.random.default_rng(284)
    canvas = WrapCanvas(n)
    for _ in range(5):
        cx, cy = rng.uniform(0, n, 2)
        radius = rng.uniform(26.0, 34.0)
        points = [(cx + radius * np.cos(a), cy + radius * np.sin(a)) for a in np.linspace(0.0, rng.uniform(4.2, 6.3), 40)]
        canvas.line(points, rng.uniform(90, 200), rng.uniform(2.0, 3.5))
    rings = blur(canvas.array(), 1.4)
    scratches = blur(_strokes(n, 285, 14, (20, 120), (0.7, 1.0), (0, 180), value=(60, 160), bend=0.05), 0.4)
    value = 0.965 - 0.03 * clouds - 0.035 * flakes - 0.05 * rings
    albedo = rgb(value, value * (1.0 - 0.02 * rings), value * (1.0 - 0.07 * rings))
    height = speck * 0.05 - scratches * 0.1
    roughness = 0.24 + 0.05 * clouds + 0.12 * wipe + 0.16 * rings + 0.12 * scratches
    _save_set("laminate", albedo, height, 0.5, 1.0, roughness, 0.0)


def fabric():
    """Плотная ткань полотняного переплетения (нить 2,5 мм): для обивки и постели."""
    n = SMALL
    y, x = grid(n)
    threads = 64
    u = x * threads
    v = y * threads
    across_u = np.sin(np.pi * (u % 1.0))
    across_v = np.sin(np.pi * (v % 1.0))
    over = (np.floor(u) + np.floor(v)) % 2.0
    warp = across_u * (0.55 + 0.45 * across_v)
    weft = across_v * (0.55 + 0.45 * across_u)
    weave = np.where(over > 0.5, warp, weft)
    fuzz = noise(n, 201, beta=0.4, low=60, high=256)
    clouds = noise(n, 202, beta=2.8, low=1, high=12)
    thread_tone = np.where(over > 0.5, 1.0, 0.93)
    value = (0.72 + 0.26 * weave) * thread_tone - 0.05 * clouds + 0.05 * (fuzz - 0.5)
    height = weave * 2.0 + fuzz * 0.5
    ao = 0.62 + 0.38 * weave
    roughness = 0.86 + 0.08 * (fuzz - 0.5)
    _save_set("fabric", rgb(value), height, 1.4, ao, roughness, 0.0)


def wood():
    """Ламинат под дерево: волокна вдоль U, годовые полосы, лаковый блеск."""
    n = SMALL
    y, _x = grid(n)
    warp = noise(n, 211, beta=2.6, low=1, high=6, stretch=(1.0, 0.06))
    # Годовые полосы идут вдоль U и лишь слегка изгибаются.
    rings = 0.5 + 0.5 * np.sin(2.0 * np.pi * (y * 9.0 + warp * 2.2))
    fibres = noise(n, 212, beta=0.8, stretch=(1.0, 0.02), low=20)
    pores = smoothstep(0.72, 0.9, noise(n, 213, beta=0.6, stretch=(1.0, 0.05), low=60))
    clouds = noise(n, 214, beta=3.0, low=1, high=8)
    tone = 0.78 + 0.16 * rings + 0.08 * (fibres - 0.5) - 0.2 * pores - 0.05 * clouds
    light = np.array([0.80, 0.60, 0.40])
    dark = np.array([0.52, 0.34, 0.20])
    mix = np.clip(1.25 - tone, 0.0, 1.0)
    albedo = np.stack([light[c] * (1.0 - mix) + dark[c] * mix for c in range(3)], axis=-1)
    height = fibres * 0.5 - pores * 1.2 + rings * 0.2
    roughness = 0.36 + 0.1 * (1.0 - rings) + 0.2 * pores + 0.06 * clouds
    _save_set("wood", albedo, height, 1.2, 1.0 - 0.2 * pores, roughness, 0.0)


def rubber():
    """Матовая резина и чёрный пластик: мелкая шагрень, сероватая пыль."""
    n = SMALL
    pebble = noise(n, 221, beta=0.5, low=60, high=200)
    dust = noise(n, 222, beta=2.6, low=1, high=20)
    scuffs = blur(_strokes(n, 223, 12, (20, 110), (1.0, 2.5), (0, 180), bend=0.2), 0.8)
    value = 0.76 + 0.16 * dust ** 2 + 0.03 * (pebble - 0.5) + 0.05 * scuffs
    height = pebble * 0.8 - scuffs * 0.4
    roughness = 0.74 + 0.1 * dust ** 2 + 0.05 * (pebble - 0.5) - 0.08 * scuffs
    _save_set("rubber", rgb(value, value, value * 0.99), height, 1.4, 1.0, roughness, 0.0)


def ceiling_perf():
    """Перфорированная потолочная панель: ровная краска и сетка отверстий 6 мм с шагом 19 мм."""
    n = LARGE
    y, x = grid(n)
    cells = 64
    fx = (x * cells) % 1.0 - 0.5
    fy = (y * cells) % 1.0 - 0.5
    distance = np.sqrt(fx * fx + fy * fy) * (n / cells)
    hole = smoothstep(3.6, 2.2, distance)
    clouds = noise(n, 231, beta=3.0, low=1, high=16)
    stains = smoothstep(0.7, 0.95, noise(n, 232, beta=3.2, low=1, high=6))
    grain = noise(n, 233, beta=0.4, low=150, high=450)
    value = (0.95 - 0.06 * clouds - 0.07 * stains + 0.02 * (grain - 0.5)) * (1.0 - 0.9 * hole)
    albedo = rgb(value, value * (1.0 - 0.03 * stains), value * (1.0 - 0.08 * stains))
    height = -hole * 1.4 + grain * 0.2
    ao = 1.0 - 0.75 * blur(hole, 1.2)
    roughness = 0.7 + 0.08 * clouds + 0.1 * stains + 0.2 * hole
    _save_set("ceiling_perf", albedo, height, 0.8, ao, roughness, 0.0)


def glass():
    """Стекло: в альфа-канале и шероховатости — разводы от протирки, отпечатки и пыль по краям пятен."""
    n = SMALL
    smears = noise(n, 241, beta=2.2, stretch=(1.0, 0.25), low=2, high=40)
    wipe = smoothstep(0.55, 0.9, smears)
    prints = smoothstep(0.78, 0.95, noise(n, 242, beta=2.4, low=6, high=30))
    dust = noise(n, 243, beta=0.3, low=120, high=256)
    specks = smoothstep(0.86, 0.95, dust)
    haze = np.clip(0.5 * wipe + 0.8 * prints + 0.5 * specks, 0.0, 1.0)
    alpha = 0.15 + 0.85 * haze
    albedo = np.concatenate([rgb(np.full((n, n), 1.0)), alpha[..., None]], axis=-1)
    save_png("%s/glass_albedo.png" % OUT, albedo)
    # Не зеркало: блик потолочной лампы на идеально гладком стекле выгорает в белый диск размером с солнце.
    save_png("%s/glass_orm.png" % OUT, orm(1.0, 0.11 + 0.2 * haze, 0.0))


def screen():
    """Экран: сетка пикселей с шагом 2,5 мм и строки развёртки. Текстура умножает цвет свечения."""
    n = SMALL
    y, x = grid(n)
    pixels = 64
    fx = (x * pixels) % 1.0
    fy = (y * pixels) % 1.0
    cell = smoothstep(0.0, 0.16, fx) * smoothstep(1.0, 0.84, fx) * smoothstep(0.0, 0.2, fy) * smoothstep(1.0, 0.8, fy)
    scan = 0.86 + 0.14 * np.sin(np.pi * ((y * pixels / 2.0) % 1.0)) ** 2
    flicker = noise(n, 251, beta=2.5, low=1, high=8)
    value = (0.34 + 0.66 * cell) * scan * (0.9 + 0.1 * flicker)
    # Субпиксели: левая треть пикселя теплее, правая холоднее — вблизи экран «живой», издали цвет ровный.
    red = value * (1.0 + 0.10 * np.cos(2.0 * np.pi * (fx - 0.2)))
    blue = value * (1.0 + 0.10 * np.cos(2.0 * np.pi * (fx - 0.8)))
    save_png("%s/screen_emission.png" % OUT, rgb(red, value, blue))
    smears = smoothstep(0.6, 0.92, noise(n, 252, beta=2.3, low=3, high=30))
    save_png("%s/screen_orm.png" % OUT, orm(1.0, 0.08 + 0.25 * smears, 0.0))


def foliage():
    """Листва: пятнистая зелень с желтоватыми участками и восковым блеском."""
    n = SMALL
    clouds = noise(n, 261, beta=2.4, low=2, high=30)
    cells = noise(n, 262, beta=0.8, low=40, high=160)
    veins = 1.0 - np.abs(2.0 * noise(n, 263, beta=1.6, low=6, high=30, stretch=(0.35, 1.0)) - 1.0) ** 0.5
    tone = 0.82 + 0.18 * clouds - 0.1 * veins
    yellow = smoothstep(0.6, 0.95, noise(n, 264, beta=3.0, low=1, high=8))
    albedo = rgb(tone * (0.70 + 0.3 * yellow), tone, tone * (0.72 - 0.15 * yellow))
    height = cells * 0.6 - veins * 1.0
    roughness = 0.42 + 0.12 * clouds + 0.08 * (cells - 0.5)
    _save_set("foliage", albedo, height, 1.3, 1.0 - 0.15 * veins, roughness, 0.0)


def water():
    """Вода в бутыли: только карта нормалей с мягкой рябью."""
    n = SMALL
    ripples = noise(n, 271, beta=2.0, low=3, high=26)
    save_png("%s/water_normal.png" % OUT, normal_map(ripples, 9.0), is_normal=True)


SETS = [paint_panel, micro_paint, enamel, composite, floor_rubber, floor_plate, metal_brushed, metal_anodized,
        plastic, vinyl, laminate, fabric, wood, rubber, ceiling_perf, glass, screen, foliage, water]


def main(arguments):
    for build in SETS:
        if arguments and not any(word in build.__name__ for word in arguments):
            continue
        build()


if __name__ == "__main__":
    main(sys.argv[1:])
