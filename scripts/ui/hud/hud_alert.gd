class_name HudAlert
extends Control
## Тревога критического саботажа: плашка в верхней строке HUD с названием и крупным обратным
## отсчётом и красный отсвет по верхней кромке экрана. Отсвет рисуется под остальными
## элементами HUD (тревога — первый узел ведущего матча), поэтому плашки сохраняют свои цвета.
## Единственный мигающий элемент HUD. Скрыта, пока её не вызовут.

const PULSE_LOW_ALPHA: float = 0.4
const PULSE_PERIOD_SEC: float = 1.6

@onready var _glow: Control = %Glow
@onready var _title: Label = %Title
@onready var _time: Label = %Time


func _ready() -> void:
	_glow.draw.connect(_draw_glow)
	visibility_changed.connect(_on_visibility_changed)


## Вызывают при каждом изменении таймера: title — что сломано, seconds_left — сколько осталось.
func show_alert(title: String, seconds_left: float) -> void:
	_title.text = title
	_time.text = MatchText.time(seconds_left)
	visible = true


func hide_alert() -> void:
	visible = false


## Отсвет «дышит», только пока тревога на экране: скрытый HUD ничего не анимирует.
func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		UiMotion.pulse(_glow, PULSE_LOW_ALPHA, PULSE_PERIOD_SEC)
	else:
		UiMotion.stop(_glow)


## Полоса вдоль верхнего края: цвет у кромки экрана, прозрачность у нижней стороны.
func _draw_glow() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _glow.size)
	var edge: Color = UiTokens.ALERT_GLOW
	var clear: Color = Color(edge, 0.0)
	_glow.draw_polygon(
			[rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)],
			[edge, edge, clear, clear])
