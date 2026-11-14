class_name UiTokens
extends RefCounted
## Дизайн-токены интерфейса: палитра, сетка, радиусы, кегли.
## Единственное место, где у UI записаны цвета и размеры. Из них build_theme.gd собирает
## resources/ui/theme.tres; сцены берут всё из темы, а скрипты с собственной отрисовкой
## (_draw) — отсюда.

# --- Палитра ---
const BG: Color = Color("0e1020")
const SURFACE: Color = Color("171a30")
const SURFACE_2: Color = Color("20243f")
const LINE: Color = Color("2c3152")
const TEXT: Color = Color("f2f3f7")
const TEXT_DIM: Color = Color("9aa0b8")
## Единственный акцент: главное действие и главное число на экране.
const ACCENT: Color = Color("ffd23f")
const DANGER: Color = Color("ff5d73")
const CYAN: Color = Color("3ddbd9")
const SUCCESS: Color = Color("57e39a")
## Повреждение, которое ещё не критично: раненая часть тела, здоровье ниже половины.
const WARNING: Color = Color("ff9f1c")

# --- Производные цвета ---
const ACCENT_HOVER: Color = Color("ffdf70")
const ACCENT_PRESSED: Color = Color("e6b92e")
const DANGER_PRESSED: Color = Color("e04a60")
## Тихий текст: пустые слоты, выключенные кнопки.
const TEXT_FAINT: Color = Color("9aa0b8", 0.5)
## Второстепенный текст HUD: светлее TEXT_DIM, в бою его читают краем глаза.
const TEXT_SOFT: Color = Color("c9cdde")
## Подложка элементов HUD: читается и на светлой, и на тёмной сцене.
const HUD_BACKING: Color = Color("0e1020", 0.86)
## Затемнение матча под паузой: мир остаётся виден, матч идёт дальше.
const SCRIM: Color = Color("0e1020", 0.58)
## Дорожка полос прогресса.
const TRACK: Color = Color("f2f3f7", 0.2)
## Подчёркивание поля ввода: заметнее обычного волоска, поле должно читаться как поле.
const FIELD_LINE: Color = Color("9aa0b8", 0.6)
const SELECTION: Color = Color("f2f3f7", 0.24)
## Контур вокруг светлых значков поверх 3D (прицел).
const OUTLINE: Color = Color("0e1020", 0.7)
const TRANSPARENT: Color = Color("0e1020", 0.0)
## Красный отсвет тревоги: самый плотный цвет у верхней кромки экрана.
const ALERT_GLOW: Color = Color("ff5d73", 0.3)
## Карточка изгнанного: поверхность с примесью красного.
const SURFACE_DANGER: Color = Color("3c253b")
## Карточка выбывшего: поверхность почти сливается с фоном.
const SURFACE_FAINT: Color = Color("171a30", 0.45)
## Шлем игрока: визор и глаза одинаковые у всех, цвет шлема — цвет игрока.
const VISOR: Color = Color("14172b")
const EYES: Color = Color("a8f7f4")
## Пустое место экипажа: шлем без хозяина.
const HELMET_EMPTY: Color = Color("20243f")
## Насколько шлем выбывшего уходит в фон.
const HELMET_DEAD_FADE: float = 0.62
## Призрак потерянной конечности на схеме тела.
const LIMB_GHOST: Color = Color("f2f3f7", 0.1)
## Зелёная зона шкалы калибровки: полупрозрачная, сквозь неё видно заполнение.
const GAUGE_ZONE: Color = Color("57e39a", 0.6)
## Ячейка кода с ошибкой: поверхность с примесью красного (как карточка изгнанного).
const CELL_ERROR: Color = Color("3c253b")

# --- Сетка 8 px (в пространстве 1920x1080) ---
const UNIT: int = 8
const SPACE_XS: int = 8
const SPACE_S: int = 16
const SPACE_M: int = 24
const SPACE_L: int = 32
const SPACE_XL: int = 48
const SPACE_XXL: int = 64
## Поля страницы меню: контент живёт в колонке 1600 px.
const PAGE_MARGIN_X: int = 160
const PAGE_MARGIN_Y: int = 80
## Отступ элементов HUD от краёв экрана.
const HUD_MARGIN: int = 48

# --- Геометрия ---
const RADIUS_S: int = 4
const RADIUS_M: int = 6
const LINE_WIDTH: int = 2
const FOCUS_OFFSET: int = 4
## Оптическое выравнивание: у крупного заголовка левый край буквы отстоит от края строки.
const DISPLAY_XL_INSET: int = 10

# --- Кегли (меньше CAPTION не бывает: на 1280x720 всё уменьшается в полтора раза) ---
const FONT_DISPLAY_XL: int = 168
const FONT_DISPLAY: int = 96
const FONT_NUMBER: int = 96
## Итог собрания: встаёт на место заголовка экрана, до двух строк.
const FONT_VERDICT: int = 64
## Главные числа HUD: здоровье, патроны, таймер тревоги.
const FONT_HUD_NUMBER: int = 56
const FONT_TITLE: int = 48
const FONT_HEADING: int = 32
const FONT_NAME: int = 30
const FONT_BODY: int = 28
## Текст HUD: на 1280x720 остаётся не мельче 17 px.
const FONT_HUD: int = 26
const FONT_BODY_S: int = 24
const FONT_CAPTION: int = 22
## Разрядка цифр кода на наклейке и в ячейках ввода: цифры читаются по одной.
const TRACKING_CODE: int = 6

# --- Состояния здоровья ---
## Ниже этой доли здоровья состояние считается критическим, ниже HEALTH_HURT — раненым.
const HEALTH_CRITICAL: float = 0.3
const HEALTH_HURT: float = 0.6
## С этой доли часть тела считается целой.
const PART_INTACT: float = 0.999

# --- Движение ---
const FADE_SEC: float = 0.16
const SLIDE_PX: float = 16.0
## Встряска при ошибке ввода: размах в пикселях, число качаний и длительность.
const SHAKE_PX: float = 12.0
const SHAKE_SWINGS: int = 4
const SHAKE_SEC: float = 0.32


## Цвет части тела: целая — цвет текста, раненая — оранжевая, чем меньше осталось, тем краснее.
static func damage_color(fraction: float) -> Color:
	if fraction >= PART_INTACT:
		return TEXT
	return DANGER.lerp(WARNING, clampf(fraction, 0.0, 1.0))


## Цвет полосы здоровья: зелёная, оранжевая, красная.
static func health_color(fraction: float) -> Color:
	if fraction <= HEALTH_CRITICAL:
		return DANGER
	return WARNING if fraction <= HEALTH_HURT else SUCCESS
