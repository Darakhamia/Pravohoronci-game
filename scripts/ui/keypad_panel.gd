class_name KeypadPanel
extends Control
## Кодовая панель задания «ввести код»: наклейка с кодом, ячейки набранного и клавиши 3x4
## (цифры, «стереть», «подтвердить»). Код набирается мышью или с клавиатуры: цифры,
## Backspace, Enter; Esc закрывает. Неверный код — ячейки краснеют и вздрагивают, набор
## начинается заново. Верный ли код, решает сервер: панель только сообщает наверх
## submitted и cancelled, а закрывает её ведущий матча. Курсор для неё просят у Hud.

## Игрок подтвердил набранный код.
signal submitted(text: String)
## Игрок закрыл панель, не закончив (Esc).
signal cancelled

const DIGITS: String = "123456789"
const ZERO: String = "0"
## Сколько цифр в коде, если сервер его не прислал, и сколько ячеек помещается в панель.
const DEFAULT_LENGTH: int = 4
const MAX_LENGTH: int = 8
const KEY_SIZE: Vector2 = Vector2(96.0, 72.0)
const KEY_COLUMNS: int = 3
## Ячейки делят между собой ширину клавиатуры; шире этого ячейка не бывает.
const CELL_HEIGHT: float = 80.0
const MAX_CELL_WIDTH: float = 72.0
const ICON_SIZE: float = 32.0
## Наклон наклейки: её лепили на бегу.
const STICKER_TILT: float = deg_to_rad(-4.0)

const TEXT_HINT: String = "Набери этот код и подтверди."
const TEXT_HINT_NO_CODE: String = "Набери код и подтверди."
const TEXT_HINT_ERROR: String = "Неверный код. Набери ещё раз."
const HINT_STYLE: StringName = &"LabelDim"
const HINT_ERROR_STYLE: StringName = &"LabelError"
const KEY_STYLE: StringName = &"ButtonKey"
const CONFIRM_STYLE: StringName = &"ButtonKeyPrimary"
const CELL_STYLE: StringName = &"LabelCell"
const CELL_ACTIVE_STYLE: StringName = &"LabelCellActive"
const CELL_ERROR_STYLE: StringName = &"LabelCellError"

var _entry: String = ""
var _length: int = DEFAULT_LENGTH
## Последняя попытка не подошла: набранное показано красным до следующей клавиши.
var _error: bool = false
var _cell_labels: Array[Label] = []
var _confirm_key: Button = null
var _confirm_icon: UiIcon = null

@onready var _panel: Control = %Panel
@onready var _title: Label = %Title
@onready var _note: Control = %Note
@onready var _sticker: Control = %Sticker
@onready var _code: Label = %Code
@onready var _hint: Label = %Hint
@onready var _cells_holder: Control = %CellsHolder
@onready var _cells: HBoxContainer = %Cells
@onready var _keys: GridContainer = %Keys


func _ready() -> void:
	set_process_unhandled_key_input(false)
	for digit: String in DIGITS:
		_add_digit_key(digit)
	var erase_key: Button = _add_key()
	_add_key_icon(erase_key, UiIcon.Kind.ERASE, UiTokens.TEXT)
	erase_key.pressed.connect(_erase)
	_add_digit_key(ZERO)
	_confirm_key = _add_key()
	_confirm_key.theme_type_variation = CONFIRM_STYLE
	_confirm_icon = _add_key_icon(_confirm_key, UiIcon.Kind.CHECK, UiTokens.BG)
	_confirm_key.pressed.connect(_confirm)
	_sticker.resized.connect(_place_sticker)
	_note.resized.connect(_place_sticker)
	_build_cells()
	_refresh()


## Клавиатура: цифры, Backspace, Enter, Esc. Пока панель открыта, эти клавиши дальше не идут —
## иначе Esc заодно открыл бы паузу.
func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.is_action(&"ui_cancel"):
		if not key.echo:
			cancelled.emit()
	elif key.keycode == KEY_BACKSPACE or key.keycode == KEY_DELETE:
		_erase()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		if not key.echo:
			_confirm()
	elif key.unicode >= ZERO.unicode_at(0) and key.unicode <= ZERO.unicode_at(0) + DIGITS.length():
		if not key.echo:
			_type_digit(char(key.unicode))
	else:
		return
	get_viewport().set_input_as_handled()


## Открывает панель. title — название задания, code — код, который нужно набрать (он написан
## на наклейке); пустой код — наклейки нет, ячеек DEFAULT_LENGTH.
func open(title: String, code: String) -> void:
	_title.text = title
	_code.text = code
	_note.visible = not code.is_empty()
	_length = clampi(code.length(), 1, MAX_LENGTH) if not code.is_empty() else DEFAULT_LENGTH
	_entry = ""
	_error = false
	_place_sticker()
	_build_cells()
	_refresh()
	set_process_unhandled_key_input(true)
	if not visible:
		visible = true
		UiMotion.fade_in(_panel)


## Сервер не принял код: набранное краснеет и вздрагивает, следующий ввод начинается заново.
func show_error() -> void:
	_error = true
	_refresh()
	UiMotion.shake(_cells, 0.0)


func close() -> void:
	visible = false
	set_process_unhandled_key_input(false)
	_entry = ""
	_error = false


func is_open() -> bool:
	return visible


## Что сейчас набрано.
func get_entry() -> String:
	return _entry


func is_error_shown() -> bool:
	return _error


func _add_digit_key(digit: String) -> void:
	var key: Button = _add_key()
	key.text = digit
	key.pressed.connect(_type_digit.bind(digit))


func _add_key() -> Button:
	var key: Button = Button.new()
	key.custom_minimum_size = KEY_SIZE
	key.focus_mode = Control.FOCUS_NONE
	key.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	key.theme_type_variation = KEY_STYLE
	_keys.add_child(key)
	return key


func _add_key_icon(key: Button, kind: UiIcon.Kind, color: Color) -> UiIcon:
	var icon: UiIcon = UiIcon.new()
	icon.kind = kind
	icon.color = color
	key.add_child(icon)
	# Значок стоит по центру клавиши и не перехватывает нажатия.
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	icon.offset_left = -ICON_SIZE / 2.0
	icon.offset_top = -ICON_SIZE / 2.0
	icon.offset_right = ICON_SIZE / 2.0
	icon.offset_bottom = ICON_SIZE / 2.0
	return icon


## Ячеек столько, сколько цифр в коде. Ряд лежит в обычном Control, а не в контейнере:
## так его можно встряхнуть.
func _build_cells() -> void:
	while _cell_labels.size() > _length:
		var extra: Label = _cell_labels.pop_back() as Label
		_cells.remove_child(extra)
		extra.queue_free()
	while _cell_labels.size() < _length:
		var cell: Label = Label.new()
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.theme_type_variation = CELL_STYLE
		_cells.add_child(cell)
		_cell_labels.append(cell)
	var separation: float = _cells.get_theme_constant(&"separation")
	var pad_width: float = KEY_SIZE.x * KEY_COLUMNS + _keys.get_theme_constant(&"h_separation") * (KEY_COLUMNS - 1)
	var cell_width: float = floorf((pad_width - separation * (_length - 1)) / _length)
	for cell: Label in _cell_labels:
		cell.custom_minimum_size = Vector2(minf(cell_width, MAX_CELL_WIDTH), CELL_HEIGHT)
	var row_size: Vector2 = _cells.get_combined_minimum_size()
	_cells_holder.custom_minimum_size = row_size
	_cells.position = Vector2.ZERO
	_cells.size = row_size


func _type_digit(digit: String) -> void:
	if _error:
		_entry = ""
		_error = false
	if _entry.length() < _length:
		_entry += digit
	_refresh()


func _erase() -> void:
	if _error:
		_entry = ""
		_error = false
	else:
		_entry = _entry.left(-1)
	_refresh()


func _confirm() -> void:
	if _error or _entry.length() < _length:
		return
	submitted.emit(_entry)


func _refresh() -> void:
	for index: int in _cell_labels.size():
		var cell: Label = _cell_labels[index]
		cell.text = _entry[index] if index < _entry.length() else ""
		if _error:
			cell.theme_type_variation = CELL_ERROR_STYLE
		else:
			cell.theme_type_variation = CELL_ACTIVE_STYLE if index == _entry.length() else CELL_STYLE
	var can_confirm: bool = not _error and _entry.length() >= _length
	_confirm_key.disabled = not can_confirm
	_confirm_key.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_confirm else Control.CURSOR_ARROW
	_confirm_icon.set_icon(UiIcon.Kind.CHECK, UiTokens.BG if can_confirm else UiTokens.TEXT_FAINT)
	if _error:
		_hint.text = TEXT_HINT_ERROR
		_hint.theme_type_variation = HINT_ERROR_STYLE
	else:
		_hint.text = TEXT_HINT if _note.visible else TEXT_HINT_NO_CODE
		_hint.theme_type_variation = HINT_STYLE


## Наклейка лежит в обычном Control (контейнер сбросил бы её поворот): ставим её по центру
## отведённого места и наклоняем вокруг середины. Слишком длинный код уменьшает наклейку,
## чтобы она не залезла на клавиши.
func _place_sticker() -> void:
	var sticker_size: Vector2 = _sticker.get_combined_minimum_size()
	_sticker.size = sticker_size
	_sticker.position = ((_note.size - sticker_size) / 2.0).round()
	_sticker.pivot_offset = sticker_size / 2.0
	_sticker.rotation = STICKER_TILT
	var fit: float = minf(1.0, _note.size.x / maxf(sticker_size.x, 1.0)) if _note.size.x > 0.0 else 1.0
	_sticker.scale = Vector2(fit, fit)
