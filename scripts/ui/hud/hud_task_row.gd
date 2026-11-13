class_name HudTaskRow
extends HBoxContainer
## Строка личного задания: отметка и название. Невыполненное — пустой квадрат и светлый текст,
## выполненное — зелёный квадрат с галочкой и приглушённый текст. Строки создаёт HudTasks.

const MARK_SIZE: float = 22.0
const MARK_INSET: float = 4.0
const CHECK_WIDTH: float = 3.0
## Строка просит ширину своего текста, но не больше этого: дальше название обрезается
## многоточием. Панель заданий растёт до самого длинного задания («Название — Место»).
const MAX_TITLE_WIDTH: float = 520.0
const TODO_STYLE: StringName = &"LabelHud"
const DONE_STYLE: StringName = &"LabelHudDim"

var _done: bool = false
var _mark: Control = Control.new()
var _title: Label = Label.new()
var _box: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"HBoxSnug"
	_mark.custom_minimum_size = Vector2(MARK_SIZE, MARK_SIZE)
	_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.draw.connect(_draw_mark)
	add_child(_mark)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.theme_type_variation = TODO_STYLE
	add_child(_title)
	_box.set_border_width_all(UiTokens.LINE_WIDTH)
	_box.set_corner_radius_all(UiTokens.RADIUS_S)


func set_task(title: String, done: bool) -> void:
	_done = done
	_title.text = title
	_title.theme_type_variation = DONE_STYLE if done else TODO_STYLE
	# Надпись с многоточием сама ширины не просит: даём ей ширину текста в пределах разумного.
	var font: Font = _title.get_theme_font(&"font")
	var font_size: int = _title.get_theme_font_size(&"font_size")
	var text_width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_title.custom_minimum_size.x = minf(ceilf(text_width), MAX_TITLE_WIDTH)
	_mark.queue_redraw()


func get_title() -> String:
	return _title.text


func is_done() -> bool:
	return _done


func _draw_mark() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _mark.size)
	_box.draw_center = _done
	_box.bg_color = UiTokens.SUCCESS
	_box.border_color = UiTokens.SUCCESS if _done else UiTokens.TEXT_SOFT
	_mark.draw_style_box(_box, rect)
	if _done:
		UiDraw.check(_mark, rect.grow(-MARK_INSET), UiTokens.BG, CHECK_WIDTH)
