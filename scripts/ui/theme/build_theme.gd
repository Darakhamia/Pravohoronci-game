extends SceneTree
## Генератор темы интерфейса: собирает resources/ui/theme.tres из UiTokens.
## Запуск из корня проекта после любой правки токенов или этого файла:
##   godot --headless -s res://scripts/ui/theme/build_theme.gd
## Тему руками не правим: все цвета, кегли и состояния контролов описаны здесь.

const THEME_PATH: String = "res://resources/ui/theme.tres"
const FONT_DISPLAY_PATH: String = "res://assets/fonts/Unbounded.ttf"
const FONT_TEXT_PATH: String = "res://assets/fonts/Onest.ttf"
const WEIGHT_AXIS: String = "wght"

const WEIGHT_MEDIUM: int = 500
const WEIGHT_SEMIBOLD: int = 600
const WEIGHT_BOLD: int = 700
const WEIGHT_BLACK: int = 800
## Разрядка для надписей капителью (оверлайны, метки), в пикселях между знаками.
const TRACKING_CAPS: int = 2
## Крупный заголовок набираем плотнее.
const TRACKING_DISPLAY: int = -2

const BUTTON_MARGIN_X: int = 32
const BUTTON_MARGIN_Y: int = 21
const BUTTON_ICON_WIDTH: int = 24
const FIELD_MARGIN_Y: int = 12
const TAG_MARGIN_X: int = 10
const TAG_MARGIN_Y: int = 2
const KEY_MARGIN_X: int = 10
const KEY_MARGIN_Y: int = 3
const HUD_PANEL_MARGIN_X: int = 16
const HUD_PANEL_MARGIN_Y: int = 12
## Подсказка действия: вокруг клавиши должно хватать места рамке удержания.
const HUD_PROMPT_MARGIN_X: int = 20
const HUD_PROMPT_MARGIN_Y: int = 14
const MODAL_MARGIN: int = 40
## Клавиша кодовой панели: размер задаёт сцена, поля нужны только чтобы цифра не липла к краю.
const KEYPAD_KEY_MARGIN: int = 8
## Ячейка введённого кода.
const CELL_MARGIN_X: int = 8
const CELL_MARGIN_Y: int = 4
## Наклейка с кодом.
const STICKER_MARGIN_X: int = 24
const STICKER_MARGIN_Y: int = 14
## Уведомление HUD: пилюля чуть просторнее обычной подложки.
const TOAST_MARGIN_X: int = 20
const TOAST_MARGIN_Y: int = 10
const BAR_HALF_HEIGHT: int = 4
const CARET_WIDTH: int = 2
## Промежутки мельче шага сетки: ряд мини-шлемов и строка «значок + подпись».
const MINI_SEPARATION: int = 4
const SNUG_SEPARATION: int = 12
const LINE_SPACING_TEXT: int = 6

var _theme: Theme = Theme.new()
var _fonts: Dictionary[String, FontVariation] = {}


func _init() -> void:
	_build()
	var error: Error = ResourceSaver.save(_theme, THEME_PATH)
	if error == OK:
		print("THEME: сохранена ", THEME_PATH)
	else:
		printerr("THEME: не удалось сохранить %s: %s" % [THEME_PATH, error_string(error)])
	quit(0 if error == OK else 1)


func _build() -> void:
	_theme.default_font = _text_font(WEIGHT_MEDIUM)
	_theme.default_font_size = UiTokens.FONT_BODY
	_build_labels()
	_build_buttons()
	_build_line_edit()
	_build_panels()
	_build_bars_and_lines()
	_build_containers()


# --- Шрифты ---

func _display_font(weight: int, tracking: int = 0) -> FontVariation:
	return _font(FONT_DISPLAY_PATH, weight, tracking)


func _text_font(weight: int) -> FontVariation:
	return _font(FONT_TEXT_PATH, weight, 0)


## Один FontVariation на каждую тройку «файл, насыщенность, разрядка».
func _font(path: String, weight: int, tracking: int) -> FontVariation:
	var key: String = "%s:%d:%d" % [path, weight, tracking]
	if not _fonts.has(key):
		var font: FontVariation = FontVariation.new()
		font.base_font = load(path) as Font
		var axis: int = TextServerManager.get_primary_interface().name_to_tag(WEIGHT_AXIS)
		font.variation_opentype = {axis: weight}
		font.spacing_glyph = tracking
		_fonts[key] = font
	return _fonts[key]


# --- Надписи ---

func _build_labels() -> void:
	_label(&"Label", &"", _text_font(WEIGHT_MEDIUM), UiTokens.FONT_BODY, UiTokens.TEXT)
	_theme.set_constant(&"line_spacing", &"Label", LINE_SPACING_TEXT)
	_label(&"LabelDisplayXL", &"Label", _display_font(WEIGHT_BLACK, TRACKING_DISPLAY), UiTokens.FONT_DISPLAY_XL, UiTokens.TEXT)
	# Роль на экране начала матча: цвет экипажа и цвет предателя — те же, что у плашки роли в HUD.
	_label(&"LabelDisplayXLCyan", &"LabelDisplayXL", null, 0, UiTokens.CYAN)
	_label(&"LabelDisplayXLDanger", &"LabelDisplayXL", null, 0, UiTokens.DANGER)
	_label(&"LabelDisplay", &"Label", _display_font(WEIGHT_BLACK, TRACKING_DISPLAY), UiTokens.FONT_DISPLAY, UiTokens.TEXT)
	_label(&"LabelVerdict", &"Label", _display_font(WEIGHT_BOLD, TRACKING_DISPLAY), UiTokens.FONT_VERDICT, UiTokens.TEXT)
	_theme.set_constant(&"line_spacing", &"LabelVerdict", 0)
	# Личный исход на экране итогов: «Победа» — акцент, «Поражение» — красный.
	_label(&"LabelVerdictAccent", &"LabelVerdict", null, 0, UiTokens.ACCENT)
	_label(&"LabelVerdictDanger", &"LabelVerdict", null, 0, UiTokens.DANGER)
	_label(&"LabelNumber", &"Label", _display_font(WEIGHT_BOLD), UiTokens.FONT_NUMBER, UiTokens.TEXT)
	_label(&"LabelNumberAccent", &"LabelNumber", null, 0, UiTokens.ACCENT)
	_label(&"LabelNumberDim", &"LabelNumber", null, 0, UiTokens.TEXT_DIM)
	_label(&"LabelTitle", &"Label", _display_font(WEIGHT_BOLD), UiTokens.FONT_TITLE, UiTokens.TEXT)
	# Главные числа HUD: здоровье, патроны, таймер тревоги.
	_label(&"LabelHudNumber", &"Label", _display_font(WEIGHT_BOLD), UiTokens.FONT_HUD_NUMBER, UiTokens.TEXT)
	_label(&"LabelHudNumberDanger", &"LabelHudNumber", null, 0, UiTokens.DANGER)
	# Короткие значения HUD: «7/20», «12 с».
	_label(&"LabelHudValue", &"Label", _display_font(WEIGHT_SEMIBOLD), UiTokens.FONT_HUD, UiTokens.TEXT)
	# Текст HUD: названия заданий, оружия, действий.
	_label(&"LabelHud", &"Label", _text_font(WEIGHT_SEMIBOLD), UiTokens.FONT_HUD, UiTokens.TEXT)
	_label(&"LabelHudSoft", &"LabelHud", null, 0, UiTokens.TEXT_SOFT)
	_label(&"LabelHudDim", &"LabelHud", null, 0, UiTokens.TEXT_DIM)
	_label(&"LabelHeading", &"Label", _display_font(WEIGHT_SEMIBOLD), UiTokens.FONT_HEADING, UiTokens.TEXT)
	_label(&"LabelHeadingDim", &"LabelHeading", null, 0, UiTokens.TEXT_DIM)
	_label(&"LabelOverline", &"Label", _display_font(WEIGHT_MEDIUM, TRACKING_CAPS), UiTokens.FONT_CAPTION, UiTokens.TEXT_DIM)
	_label(&"LabelOverlineBright", &"LabelOverline", null, 0, UiTokens.TEXT)
	_label(&"LabelOverlineSoft", &"LabelOverline", null, 0, UiTokens.TEXT_SOFT)
	_label(&"LabelOverlineDanger", &"LabelOverline", null, 0, UiTokens.DANGER)
	_label(&"LabelOverlineCyan", &"LabelOverline", null, 0, UiTokens.CYAN)
	_label(&"LabelStrong", &"Label", _text_font(WEIGHT_BOLD), UiTokens.FONT_NAME, UiTokens.TEXT)
	_label(&"LabelStrongDim", &"LabelStrong", null, 0, UiTokens.TEXT_DIM)
	_label(&"LabelLead", &"Label", _text_font(WEIGHT_SEMIBOLD), UiTokens.FONT_HEADING, UiTokens.TEXT)
	_label(&"LabelDim", &"Label", null, 0, UiTokens.TEXT_DIM)
	_label(&"LabelFaint", &"Label", null, 0, UiTokens.TEXT_FAINT)
	_label(&"LabelError", &"Label", null, 0, UiTokens.DANGER)
	_label(&"LabelCaption", &"Label", _text_font(WEIGHT_MEDIUM), UiTokens.FONT_CAPTION, UiTokens.TEXT_DIM)

	# Метка-плашка в строке игрока: «ХОСТ». Контур светлее волоска: метка должна читаться.
	_label(&"LabelTag", &"LabelOverline", null, 0, UiTokens.TEXT)
	var tag: StyleBoxFlat = _flat(UiTokens.TRANSPARENT, UiTokens.TEXT_DIM, UiTokens.LINE_WIDTH, UiTokens.RADIUS_S)
	_set_margins(tag, TAG_MARGIN_X, TAG_MARGIN_Y)
	_theme.set_stylebox(&"normal", &"LabelTag", tag)
	# Залитая плашка: «ТЫ».
	_label(&"LabelTagSolid", &"LabelTag", null, 0, UiTokens.BG)
	var tag_solid: StyleBoxFlat = _flat(UiTokens.TEXT, UiTokens.TEXT, UiTokens.LINE_WIDTH, UiTokens.RADIUS_S)
	_set_margins(tag_solid, TAG_MARGIN_X, TAG_MARGIN_Y)
	_theme.set_stylebox(&"normal", &"LabelTagSolid", tag_solid)
	_label(&"LabelTagAccent", &"LabelTag", null, 0, UiTokens.BG)
	var tag_accent: StyleBoxFlat = _flat(UiTokens.ACCENT, UiTokens.ACCENT, UiTokens.LINE_WIDTH, UiTokens.RADIUS_S)
	_set_margins(tag_accent, TAG_MARGIN_X, TAG_MARGIN_Y)
	_theme.set_stylebox(&"normal", &"LabelTagAccent", tag_accent)
	_label(&"LabelTagDanger", &"LabelTag", null, 0, UiTokens.BG)
	var tag_danger: StyleBoxFlat = _flat(UiTokens.DANGER, UiTokens.DANGER, UiTokens.LINE_WIDTH, UiTokens.RADIUS_S)
	_set_margins(tag_danger, TAG_MARGIN_X, TAG_MARGIN_Y)
	_theme.set_stylebox(&"normal", &"LabelTagDanger", tag_danger)

	# Клавиша: светлая шляпка с тёмной буквой видна на любом фоне.
	_label(&"LabelKey", &"Label", _display_font(WEIGHT_SEMIBOLD), UiTokens.FONT_CAPTION, UiTokens.BG)
	var key: StyleBoxFlat = _flat(UiTokens.TEXT, UiTokens.TEXT, UiTokens.LINE_WIDTH, UiTokens.RADIUS_S)
	_set_margins(key, KEY_MARGIN_X, KEY_MARGIN_Y)
	_theme.set_stylebox(&"normal", &"LabelKey", key)
	# Клавиша недоступного действия: та же шляпка, но только контуром.
	_label(&"LabelKeyDim", &"LabelKey", null, 0, UiTokens.TEXT_DIM)
	var key_dim: StyleBoxFlat = _flat(UiTokens.TRANSPARENT, UiTokens.TEXT_DIM, UiTokens.LINE_WIDTH, UiTokens.RADIUS_S)
	_set_margins(key_dim, KEY_MARGIN_X, KEY_MARGIN_Y)
	_theme.set_stylebox(&"normal", &"LabelKeyDim", key_dim)

	# Кодовая панель: ячейки введённого кода. Текущая — со светлой рамкой, ошибка — красная.
	_label(&"LabelCell", &"Label", _display_font(WEIGHT_BOLD), UiTokens.FONT_TITLE, UiTokens.TEXT)
	_theme.set_stylebox(&"normal", &"LabelCell", _cell_box(UiTokens.SURFACE_2, UiTokens.LINE))
	_label(&"LabelCellActive", &"LabelCell", null, 0, UiTokens.TEXT)
	_theme.set_stylebox(&"normal", &"LabelCellActive", _cell_box(UiTokens.SURFACE_2, UiTokens.TEXT))
	_label(&"LabelCellError", &"LabelCell", null, 0, UiTokens.DANGER)
	_theme.set_stylebox(&"normal", &"LabelCellError", _cell_box(UiTokens.CELL_ERROR, UiTokens.DANGER))
	# Наклейка с кодом: тёмный текст на акцентной бумажке.
	_label(&"LabelStickerCaption", &"LabelOverline", null, 0, UiTokens.BG)
	_label(&"LabelStickerCode", &"Label", _display_font(WEIGHT_BLACK, UiTokens.TRACKING_CODE), UiTokens.FONT_VERDICT, UiTokens.BG)

	_label(&"TooltipLabel", &"", _text_font(WEIGHT_MEDIUM), UiTokens.FONT_CAPTION, UiTokens.TEXT)


## font == null и size == 0 значат «как у базового типа».
func _label(type: StringName, base: StringName, font: Font, size: int, color: Color) -> void:
	if not base.is_empty():
		_theme.set_type_variation(type, base)
	if font != null:
		_theme.set_font(&"font", type, font)
	if size > 0:
		_theme.set_font_size(&"font_size", type, size)
	_theme.set_color(&"font_color", type, color)


# --- Кнопки ---

func _build_buttons() -> void:
	var focus: StyleBoxFlat = _flat(UiTokens.TRANSPARENT, UiTokens.TEXT, UiTokens.LINE_WIDTH,
			UiTokens.RADIUS_M + UiTokens.FOCUS_OFFSET)
	focus.draw_center = false
	focus.set_expand_margin_all(UiTokens.FOCUS_OFFSET)

	# Button — вторичная: контур-волосок, без заливки.
	_theme.set_font(&"font", &"Button", _display_font(WEIGHT_SEMIBOLD))
	_theme.set_font_size(&"font_size", &"Button", UiTokens.FONT_BODY_S)
	_theme.set_constant(&"h_separation", &"Button", UiTokens.SPACE_S)
	_theme.set_constant(&"icon_max_width", &"Button", BUTTON_ICON_WIDTH)
	_theme.set_stylebox(&"focus", &"Button", focus)
	_button_boxes(&"Button",
			_button_box(UiTokens.TRANSPARENT, UiTokens.LINE),
			_button_box(UiTokens.SURFACE, UiTokens.TEXT_DIM),
			_button_box(UiTokens.SURFACE_2, UiTokens.TEXT),
			_button_box(UiTokens.TRANSPARENT, UiTokens.LINE))
	_button_colors(&"Button", UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT_FAINT)

	# Главное действие экрана: единственная залитая акцентом кнопка.
	_theme.set_type_variation(&"ButtonPrimary", &"Button")
	_theme.set_font(&"font", &"ButtonPrimary", _display_font(WEIGHT_BOLD))
	_button_boxes(&"ButtonPrimary",
			_button_box(UiTokens.ACCENT, UiTokens.ACCENT),
			_button_box(UiTokens.ACCENT_HOVER, UiTokens.ACCENT_HOVER),
			_button_box(UiTokens.ACCENT_PRESSED, UiTokens.ACCENT_PRESSED),
			_button_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2))
	_button_colors(&"ButtonPrimary", UiTokens.BG, UiTokens.BG, UiTokens.BG, UiTokens.TEXT_FAINT)

	# Главная кнопка, пока идёт подключение: выключена, но текст читается — это строка состояния.
	_theme.set_type_variation(&"ButtonBusy", &"ButtonPrimary")
	_button_boxes(&"ButtonBusy",
			_button_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2),
			_button_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2),
			_button_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2),
			_button_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2))
	_button_colors(&"ButtonBusy", UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT)

	# Необратимое действие.
	_theme.set_type_variation(&"ButtonDanger", &"Button")
	_button_boxes(&"ButtonDanger",
			_button_box(UiTokens.TRANSPARENT, UiTokens.DANGER),
			_button_box(UiTokens.DANGER, UiTokens.DANGER),
			_button_box(UiTokens.DANGER_PRESSED, UiTokens.DANGER_PRESSED),
			_button_box(UiTokens.TRANSPARENT, UiTokens.LINE))
	_button_colors(&"ButtonDanger", UiTokens.DANGER, UiTokens.BG, UiTokens.BG, UiTokens.TEXT_FAINT)

	# Тихая кнопка-текст: без контура, для второстепенного выхода.
	_theme.set_type_variation(&"ButtonQuiet", &"Button")
	_button_boxes(&"ButtonQuiet",
			_button_box(UiTokens.TRANSPARENT, UiTokens.TRANSPARENT),
			_button_box(UiTokens.SURFACE, UiTokens.SURFACE),
			_button_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2),
			_button_box(UiTokens.TRANSPARENT, UiTokens.TRANSPARENT))
	_button_colors(&"ButtonQuiet", UiTokens.TEXT_DIM, UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT_FAINT)

	# Выбранный вариант, который уже нельзя изменить («Пропустить» после голоса).
	_theme.set_type_variation(&"ButtonChosen", &"Button")
	_button_boxes(&"ButtonChosen",
			_button_box(UiTokens.SURFACE_2, UiTokens.ACCENT),
			_button_box(UiTokens.SURFACE_2, UiTokens.ACCENT_HOVER),
			_button_box(UiTokens.SURFACE_2, UiTokens.ACCENT_PRESSED),
			_button_box(UiTokens.SURFACE_2, UiTokens.ACCENT))
	_button_colors(&"ButtonChosen", UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT)

	# Клавиша кодовой панели: залитая плитка с крупной цифрой.
	_theme.set_type_variation(&"ButtonKey", &"Button")
	_theme.set_font_size(&"font_size", &"ButtonKey", UiTokens.FONT_HEADING)
	_button_boxes(&"ButtonKey",
			_key_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2),
			_key_box(UiTokens.LINE, UiTokens.TEXT_DIM),
			_key_box(UiTokens.LINE, UiTokens.TEXT),
			_key_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2))
	_button_colors(&"ButtonKey", UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT_FAINT)
	# «Подтвердить» на кодовой панели: главное действие, пока код не набран — выключена.
	_theme.set_type_variation(&"ButtonKeyPrimary", &"ButtonKey")
	_button_boxes(&"ButtonKeyPrimary",
			_key_box(UiTokens.ACCENT, UiTokens.ACCENT),
			_key_box(UiTokens.ACCENT_HOVER, UiTokens.ACCENT_HOVER),
			_key_box(UiTokens.ACCENT_PRESSED, UiTokens.ACCENT_PRESSED),
			_key_box(UiTokens.SURFACE_2, UiTokens.SURFACE_2))
	_button_colors(&"ButtonKeyPrimary", UiTokens.BG, UiTokens.BG, UiTokens.BG, UiTokens.TEXT_FAINT)

	# Карточка игрока на собрании — тоже кнопка: вся её площадь принимает голос.
	_theme.set_type_variation(&"VoteCard", &"Button")
	_button_boxes(&"VoteCard",
			_card_box(UiTokens.SURFACE, UiTokens.SURFACE),
			_card_box(UiTokens.SURFACE_2, UiTokens.TEXT_DIM),
			_card_box(UiTokens.SURFACE_2, UiTokens.TEXT),
			_card_box(UiTokens.SURFACE, UiTokens.SURFACE))
	# Мой выбор.
	_theme.set_type_variation(&"VoteCardChosen", &"VoteCard")
	_button_boxes(&"VoteCardChosen",
			_card_box(UiTokens.SURFACE_2, UiTokens.ACCENT),
			_card_box(UiTokens.SURFACE_2, UiTokens.ACCENT_HOVER),
			_card_box(UiTokens.SURFACE_2, UiTokens.ACCENT_PRESSED),
			_card_box(UiTokens.SURFACE_2, UiTokens.ACCENT))
	# Изгнанный по итогам голосования: красная рамка и красноватая заливка.
	_theme.set_type_variation(&"VoteCardEjected", &"VoteCard")
	_button_boxes(&"VoteCardEjected",
			_card_box(UiTokens.SURFACE_DANGER, UiTokens.DANGER),
			_card_box(UiTokens.SURFACE_DANGER, UiTokens.DANGER),
			_card_box(UiTokens.SURFACE_DANGER, UiTokens.DANGER),
			_card_box(UiTokens.SURFACE_DANGER, UiTokens.DANGER))
	# Выбывший игрок: карточка без рамки почти сливается с фоном.
	_theme.set_type_variation(&"VoteCardDead", &"VoteCard")
	_button_boxes(&"VoteCardDead",
			_card_box(UiTokens.SURFACE_FAINT, UiTokens.TRANSPARENT),
			_card_box(UiTokens.SURFACE_FAINT, UiTokens.TRANSPARENT),
			_card_box(UiTokens.SURFACE_FAINT, UiTokens.TRANSPARENT),
			_card_box(UiTokens.SURFACE_FAINT, UiTokens.TRANSPARENT))


func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = _flat(bg, border, UiTokens.LINE_WIDTH, UiTokens.RADIUS_M)
	_set_margins(box, BUTTON_MARGIN_X, BUTTON_MARGIN_Y)
	return box


func _key_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = _flat(bg, border, UiTokens.LINE_WIDTH, UiTokens.RADIUS_M)
	_set_margins(box, KEYPAD_KEY_MARGIN, KEYPAD_KEY_MARGIN)
	return box


func _cell_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = _flat(bg, border, UiTokens.LINE_WIDTH, UiTokens.RADIUS_M)
	_set_margins(box, CELL_MARGIN_X, CELL_MARGIN_Y)
	return box


func _card_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = _flat(bg, border, UiTokens.LINE_WIDTH, UiTokens.RADIUS_M)
	_set_margins(box, UiTokens.SPACE_M, UiTokens.SPACE_S)
	return box


func _button_boxes(type: StringName, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox) -> void:
	_theme.set_stylebox(&"normal", type, normal)
	_theme.set_stylebox(&"hover", type, hover)
	_theme.set_stylebox(&"pressed", type, pressed)
	_theme.set_stylebox(&"hover_pressed", type, pressed)
	_theme.set_stylebox(&"disabled", type, disabled)


func _button_colors(type: StringName, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	_theme.set_color(&"font_color", type, normal)
	_theme.set_color(&"font_focus_color", type, normal)
	_theme.set_color(&"font_hover_color", type, hover)
	_theme.set_color(&"font_pressed_color", type, pressed)
	_theme.set_color(&"font_hover_pressed_color", type, pressed)
	_theme.set_color(&"font_disabled_color", type, disabled)
	_theme.set_color(&"icon_normal_color", type, normal)
	_theme.set_color(&"icon_focus_color", type, normal)
	_theme.set_color(&"icon_hover_color", type, hover)
	_theme.set_color(&"icon_pressed_color", type, pressed)
	_theme.set_color(&"icon_hover_pressed_color", type, pressed)
	_theme.set_color(&"icon_disabled_color", type, disabled)


# --- Поле ввода: подчёркнутая строка без рамки ---

func _build_line_edit() -> void:
	_theme.set_font(&"font", &"LineEdit", _text_font(WEIGHT_SEMIBOLD))
	_theme.set_font_size(&"font_size", &"LineEdit", UiTokens.FONT_HEADING)
	_theme.set_color(&"font_color", &"LineEdit", UiTokens.TEXT)
	_theme.set_color(&"font_uneditable_color", &"LineEdit", UiTokens.TEXT_DIM)
	_theme.set_color(&"font_placeholder_color", &"LineEdit", UiTokens.TEXT_FAINT)
	_theme.set_color(&"font_selected_color", &"LineEdit", UiTokens.TEXT)
	_theme.set_color(&"caret_color", &"LineEdit", UiTokens.TEXT)
	_theme.set_color(&"selection_color", &"LineEdit", UiTokens.SELECTION)
	_theme.set_constant(&"caret_width", &"LineEdit", CARET_WIDTH)
	_theme.set_stylebox(&"normal", &"LineEdit", _underline(UiTokens.FIELD_LINE))
	_theme.set_stylebox(&"read_only", &"LineEdit", _underline(UiTokens.LINE))
	# Рисуется поверх normal: подчёркивание становится светлым.
	_theme.set_stylebox(&"focus", &"LineEdit", _underline(UiTokens.TEXT))


func _underline(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = color
	box.border_width_bottom = UiTokens.LINE_WIDTH
	_set_margins(box, 0, FIELD_MARGIN_Y)
	return box


# --- Поверхности ---

func _build_panels() -> void:
	# PanelContainer по умолчанию — плоская карточка.
	var card: StyleBoxFlat = _flat(UiTokens.SURFACE, UiTokens.TRANSPARENT, 0, UiTokens.RADIUS_M)
	_set_margins(card, UiTokens.SPACE_M, UiTokens.SPACE_M)
	_theme.set_stylebox(&"panel", &"PanelContainer", card)
	_theme.set_stylebox(&"panel", &"Panel", _flat(UiTokens.SURFACE, UiTokens.TRANSPARENT, 0, UiTokens.RADIUS_M))

	# Фон экрана меню.
	_theme.set_type_variation(&"PanelScreen", &"Panel")
	_theme.set_stylebox(&"panel", &"PanelScreen", _flat(UiTokens.BG, UiTokens.TRANSPARENT, 0, 0))
	# Затемнение матча под паузой.
	_theme.set_type_variation(&"PanelScrim", &"Panel")
	_theme.set_stylebox(&"panel", &"PanelScrim", _flat(UiTokens.SCRIM, UiTokens.TRANSPARENT, 0, 0))

	# Окно паузы: непрозрачная поверхность, кнопки на ней не просвечивают.
	_theme.set_type_variation(&"PanelModal", &"PanelContainer")
	var modal: StyleBoxFlat = _flat(UiTokens.SURFACE, UiTokens.TRANSPARENT, 0, UiTokens.RADIUS_M)
	_set_margins(modal, MODAL_MARGIN, MODAL_MARGIN)
	_theme.set_stylebox(&"panel", &"PanelModal", modal)

	# Подложка элемента HUD.
	_theme.set_type_variation(&"HudPanel", &"PanelContainer")
	var hud: StyleBoxFlat = _flat(UiTokens.HUD_BACKING, UiTokens.TRANSPARENT, 0, UiTokens.RADIUS_M)
	_set_margins(hud, HUD_PANEL_MARGIN_X, HUD_PANEL_MARGIN_Y)
	_theme.set_stylebox(&"panel", &"HudPanel", hud)
	# Подсказка действия: та же подложка, поля шире.
	_theme.set_type_variation(&"HudPanelPrompt", &"PanelContainer")
	var prompt: StyleBoxFlat = _flat(UiTokens.HUD_BACKING, UiTokens.TRANSPARENT, 0, UiTokens.RADIUS_M)
	_set_margins(prompt, HUD_PROMPT_MARGIN_X, HUD_PROMPT_MARGIN_Y)
	_theme.set_stylebox(&"panel", &"HudPanelPrompt", prompt)
	# Тревога: та же подложка с красной чертой снизу.
	_theme.set_type_variation(&"HudPanelAlert", &"PanelContainer")
	var alert: StyleBoxFlat = _flat(UiTokens.HUD_BACKING, UiTokens.DANGER, 0, UiTokens.RADIUS_M)
	alert.border_width_bottom = UiTokens.LINE_WIDTH
	_set_margins(alert, UiTokens.SPACE_M, UiTokens.SPACE_XS)
	_theme.set_stylebox(&"panel", &"HudPanelAlert", alert)

	# Уведомление HUD: та же подложка, поля под одну строку со значком.
	_theme.set_type_variation(&"HudPanelToast", &"PanelContainer")
	var toast: StyleBoxFlat = _flat(UiTokens.HUD_BACKING, UiTokens.TRANSPARENT, 0, UiTokens.RADIUS_M)
	_set_margins(toast, TOAST_MARGIN_X, TOAST_MARGIN_Y)
	_theme.set_stylebox(&"panel", &"HudPanelToast", toast)
	# Наклейка с кодом на кодовой панели: акцентная бумажка.
	_theme.set_type_variation(&"PanelSticker", &"PanelContainer")
	var sticker: StyleBoxFlat = _flat(UiTokens.ACCENT, UiTokens.TRANSPARENT, 0, UiTokens.RADIUS_S)
	_set_margins(sticker, STICKER_MARGIN_X, STICKER_MARGIN_Y)
	_theme.set_stylebox(&"panel", &"PanelSticker", sticker)

	var tooltip: StyleBoxFlat = _flat(UiTokens.SURFACE_2, UiTokens.LINE, UiTokens.LINE_WIDTH, UiTokens.RADIUS_S)
	_set_margins(tooltip, UiTokens.SPACE_S, UiTokens.SPACE_XS)
	_theme.set_stylebox(&"panel", &"TooltipPanel", tooltip)


# --- Полосы и линии ---

func _build_bars_and_lines() -> void:
	var track: StyleBoxFlat = _flat(UiTokens.TRACK, UiTokens.TRANSPARENT, 0, BAR_HALF_HEIGHT)
	_set_margins(track, 0, BAR_HALF_HEIGHT)
	_theme.set_stylebox(&"background", &"ProgressBar", track)
	_theme.set_stylebox(&"fill", &"ProgressBar", _flat(UiTokens.TEXT, UiTokens.TRANSPARENT, 0, BAR_HALF_HEIGHT))
	# Состояния полосы здоровья и прогресс экипажа (его цвет — цвет плашки «ЭКИПАЖ»).
	var bar_colors: Dictionary[StringName, Color] = {
		&"ProgressBarSuccess": UiTokens.SUCCESS,
		&"ProgressBarWarning": UiTokens.WARNING,
		&"ProgressBarDanger": UiTokens.DANGER,
		&"ProgressBarCyan": UiTokens.CYAN,
	}
	for bar_type: StringName in bar_colors:
		_theme.set_type_variation(bar_type, &"ProgressBar")
		_theme.set_stylebox(&"fill", bar_type, _flat(bar_colors[bar_type], UiTokens.TRANSPARENT, 0, BAR_HALF_HEIGHT))

	_theme.set_stylebox(&"separator", &"HSeparator", _line(UiTokens.LINE, false))
	_theme.set_constant(&"separation", &"HSeparator", UiTokens.LINE_WIDTH)
	_theme.set_stylebox(&"separator", &"VSeparator", _line(UiTokens.LINE, true))
	_theme.set_constant(&"separation", &"VSeparator", UiTokens.LINE_WIDTH)
	# Светлая линейка под заголовком страницы.
	_theme.set_type_variation(&"HSeparatorStrong", &"HSeparator")
	_theme.set_stylebox(&"separator", &"HSeparatorStrong", _line(UiTokens.TEXT, false))
	# Разделитель внутри подложки HUD.
	_theme.set_type_variation(&"VSeparatorHud", &"VSeparator")
	_theme.set_stylebox(&"separator", &"VSeparatorHud", _line(UiTokens.TRACK, true))


func _line(color: Color, vertical: bool) -> StyleBoxLine:
	var line: StyleBoxLine = StyleBoxLine.new()
	line.color = color
	line.thickness = UiTokens.LINE_WIDTH
	line.vertical = vertical
	return line


# --- Отступы контейнеров: шаги сетки вместо чисел в сценах ---

func _build_containers() -> void:
	_box_separation(&"VBoxContainer", &"", UiTokens.SPACE_S)
	_box_separation(&"VBoxFlush", &"VBoxContainer", 0)
	_box_separation(&"VBoxMini", &"VBoxContainer", MINI_SEPARATION)
	_box_separation(&"VBoxTight", &"VBoxContainer", UiTokens.SPACE_XS)
	_box_separation(&"VBoxSnug", &"VBoxContainer", SNUG_SEPARATION)
	_box_separation(&"VBoxRoomy", &"VBoxContainer", UiTokens.SPACE_L)
	_box_separation(&"VBoxSection", &"VBoxContainer", UiTokens.SPACE_XL)
	_box_separation(&"HBoxContainer", &"", UiTokens.SPACE_S)
	_box_separation(&"HBoxFlush", &"HBoxContainer", 0)
	_box_separation(&"HBoxMini", &"HBoxContainer", MINI_SEPARATION)
	_box_separation(&"HBoxTight", &"HBoxContainer", UiTokens.SPACE_XS)
	_box_separation(&"HBoxSnug", &"HBoxContainer", SNUG_SEPARATION)

	# Сетка карточек собрания; ряды стоят шире столбцов — метки сидят на верхней кромке карточек.
	_theme.set_constant(&"h_separation", &"GridContainer", UiTokens.SPACE_L)
	_theme.set_constant(&"v_separation", &"GridContainer", UiTokens.SPACE_M)

	# Клавиши кодовой панели стоят плотно.
	_theme.set_type_variation(&"GridKeys", &"GridContainer")
	_theme.set_constant(&"h_separation", &"GridKeys", UiTokens.SPACE_XS)
	_theme.set_constant(&"v_separation", &"GridKeys", UiTokens.SPACE_XS)

	_margins(&"MarginContainer", &"", 0, 0)
	_margins(&"MarginPage", &"MarginContainer", UiTokens.PAGE_MARGIN_X, UiTokens.PAGE_MARGIN_Y)
	_margins(&"MarginHud", &"MarginContainer", UiTokens.HUD_MARGIN, UiTokens.HUD_MARGIN)
	# Крупный заголовок сдвигаем влево, чтобы его буквы встали на линию полей.
	_theme.set_type_variation(&"MarginDisplayXL", &"MarginContainer")
	_theme.set_constant(&"margin_left", &"MarginDisplayXL", -UiTokens.DISPLAY_XL_INSET)


func _box_separation(type: StringName, base: StringName, separation: int) -> void:
	if not base.is_empty():
		_theme.set_type_variation(type, base)
	_theme.set_constant(&"separation", type, separation)


func _margins(type: StringName, base: StringName, horizontal: int, vertical: int) -> void:
	if not base.is_empty():
		_theme.set_type_variation(type, base)
	_theme.set_constant(&"margin_left", type, horizontal)
	_theme.set_constant(&"margin_right", type, horizontal)
	_theme.set_constant(&"margin_top", type, vertical)
	_theme.set_constant(&"margin_bottom", type, vertical)


# --- Помощники ---

func _flat(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box


func _set_margins(box: StyleBox, horizontal: int, vertical: int) -> void:
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
