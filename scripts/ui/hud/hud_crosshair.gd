class_name HudCrosshair
extends Control
## Прицел: точка и четыре штриха. Светлый с тёмным контуром — виден на любом фоне.

const DOT_RADIUS: float = 2.0
const TICK_GAP: float = 7.0
const TICK_LENGTH: float = 7.0
const TICK_WIDTH: float = 2.0
const OUTLINE_WIDTH: float = 1.5
const DIRECTIONS: PackedVector2Array = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center: Vector2 = size / 2.0
	# Сначала контур, потом светлые штрихи поверх.
	for direction: Vector2 in DIRECTIONS:
		draw_line(center + direction * (TICK_GAP - OUTLINE_WIDTH),
				center + direction * (TICK_GAP + TICK_LENGTH + OUTLINE_WIDTH),
				UiTokens.OUTLINE, TICK_WIDTH + OUTLINE_WIDTH * 2.0)
	draw_circle(center, DOT_RADIUS + OUTLINE_WIDTH, UiTokens.OUTLINE, true, -1.0, true)
	for direction: Vector2 in DIRECTIONS:
		draw_line(center + direction * TICK_GAP, center + direction * (TICK_GAP + TICK_LENGTH),
				UiTokens.TEXT, TICK_WIDTH)
	draw_circle(center, DOT_RADIUS, UiTokens.TEXT, true, -1.0, true)
