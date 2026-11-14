class_name Spinner
extends Control
## Индикатор ожидания: дуга, которая вращается, пока контрол виден. Без окна (сервер, боты,
## тесты) и в скриншотных тестах не анимируется — рисует неподвижную дугу.

const TURNS_PER_SEC: float = 0.9
## Какую часть круга занимает дуга.
const ARC_FRACTION: float = 0.7
const WIDTH: float = 3.0
const SEGMENTS: int = 24

@export var color: Color = UiTokens.ACCENT

var _angle: float = -PI / 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_update_processing)
	_update_processing()


func _process(delta: float) -> void:
	_angle = wrapf(_angle + TAU * TURNS_PER_SEC * delta, 0.0, TAU)
	queue_redraw()


func _draw() -> void:
	var radius: float = (minf(size.x, size.y) - WIDTH) / 2.0
	draw_arc(size / 2.0, radius, _angle, _angle + TAU * ARC_FRACTION, SEGMENTS, color, WIDTH, true)


func _update_processing() -> void:
	set_process(UiMotion.enabled and is_visible_in_tree())
