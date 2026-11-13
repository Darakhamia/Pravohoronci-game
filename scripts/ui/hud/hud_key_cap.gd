class_name HudKeyCap
extends Label
## Клавиша в HUD: одна форма на все подсказки. Светлая шляпка — действие доступно,
## контурная — сейчас недоступно (перезарядка, не на что переключаться). Вокруг шляпки
## может идти рамка удержания: она заполняется по часовой стрелке от середины верхней стороны.

const ACTIVE_STYLE: StringName = &"LabelKey"
const DIMMED_STYLE: StringName = &"LabelKeyDim"
## Насколько рамка удержания отстоит от шляпки наружу.
const RING_OFFSET: float = 4.0
const RING_WIDTH: float = 3.0
const FULL: float = 1.0

var _hold: float = 0.0


func set_key(key_text: String) -> void:
	text = key_text


func set_dimmed(dimmed: bool) -> void:
	theme_type_variation = DIMMED_STYLE if dimmed else ACTIVE_STYLE


## Доля удержания клавиши от 0 до 1; 0 прячет рамку.
func set_hold(fraction: float) -> void:
	_hold = clampf(fraction, 0.0, FULL)
	queue_redraw()


func get_hold() -> float:
	return _hold


func is_dimmed() -> bool:
	return theme_type_variation == DIMMED_STYLE


func _draw() -> void:
	if _hold <= 0.0:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, size).grow(RING_OFFSET)
	var path: PackedVector2Array = UiDraw.rounded_path(rect, UiTokens.RADIUS_S + RING_OFFSET)
	draw_polyline(path, UiTokens.TRACK, RING_WIDTH, true)
	UiDraw.path_progress(self, path, _hold, UiTokens.ACCENT, RING_WIDTH)
