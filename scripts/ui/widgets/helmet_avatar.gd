class_name HelmetAvatar
extends Control
## Знак игрока: шлем игрушечного космонавта в цвете игрока — тёмный визор и два светящихся
## глаза, как у персонажей в матче. Размер задаёт сцена (custom_minimum_size), цвет и
## состояние — владелец. Мелкие шлемы (голоса на собрании) рисуются без антенны и ушей.

enum Style {
	## Игрок в игре.
	NORMAL,
	## Свободное место: шлем без хозяина.
	EMPTY,
	## Выбывший: потухший шлем с крестиками вместо глаз.
	DEAD,
}

## С этой стороны и меньше шлем рисуется упрощённо.
const MINI_SIZE: float = 36.0
## Геометрия в долях стороны квадрата. Полный шлем: сверху место под антенну, по бокам — под уши.
const HEAD_TOP: float = 0.14
const HEAD_SIDE: float = 0.07
const HEAD_RADIUS: float = 0.26
const ANTENNA_X: float = 0.3
const ANTENNA_WIDTH: float = 0.05
const ANTENNA_BALL: float = 0.06
const EAR_TOP: float = 0.5
const EAR_HEIGHT: float = 0.24
const EAR_RADIUS: float = 0.04
const EAR_SHADE: float = 0.22
## Визор и глаза — в долях прямоугольника головы.
const VISOR_RECT: Rect2 = Rect2(0.15, 0.26, 0.7, 0.5)
const VISOR_RADIUS: float = 0.16
const EYE_WIDTH: float = 0.1
const EYE_HEIGHT: float = 0.24
const EYE_SPREAD: float = 0.13
const EYE_CENTER_Y: float = 0.51
## На какую долю ширины головы глаза уходят в сторону при look = 1.
const LOOK_SHIFT: float = 0.1
const DEAD_EYE_SIZE: float = 0.15
const DEAD_EYE_WIDTH: float = 0.045
const MIN_STROKE: float = 1.5
## Отметка «проголосовал»: кружок с галочкой на правом нижнем углу, в долях стороны.
const CHECK_SIZE: float = 0.44
const CHECK_OVERHANG: float = 0.1
const CHECK_RING: float = 3.0
const CHECK_INSET: float = 0.22
const CHECK_STROKE: float = 0.1

static var _box: StyleBoxFlat = StyleBoxFlat.new()

var _color: Color = UiTokens.TEXT_DIM
var _style: Style = Style.NORMAL
var _checked: bool = false
var _look: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_player_color(color: Color) -> void:
	_color = color
	queue_redraw()


func set_style(style: Style) -> void:
	_style = style
	queue_redraw()


## Куда смотрят глаза: -1 — влево, 0 — прямо, 1 — вправо (предатель косится на соседей).
func set_look(look: float) -> void:
	_look = clampf(look, -1.0, 1.0)
	queue_redraw()


## Отметка «этот игрок уже проголосовал» на углу шлема.
func set_checked(checked: bool) -> void:
	_checked = checked
	queue_redraw()


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	var rect: Rect2 = Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	match _style:
		Style.NORMAL:
			draw_helmet(self, rect, _color, UiTokens.VISOR, UiTokens.EYES, _look)
		Style.EMPTY:
			draw_helmet(self, rect, UiTokens.HELMET_EMPTY, UiTokens.BG, UiTokens.TRANSPARENT)
		Style.DEAD:
			draw_helmet(self, rect, _color.lerp(UiTokens.BG, UiTokens.HELMET_DEAD_FADE), UiTokens.VISOR,
					UiTokens.TEXT_DIM, 0.0, true)
	if _checked:
		_draw_check(rect)


## Рисует шлем в квадрате rect. look — куда смотрят глаза: -1 влево, 0 прямо, 1 вправо;
## dead — крестики вместо глаз. Прозрачный цвет глаз — шлем пуст.
static func draw_helmet(item: CanvasItem, rect: Rect2, body: Color, visor: Color, eyes: Color,
		look: float = 0.0, dead: bool = false) -> void:
	var side: float = rect.size.x
	var head: Rect2 = rect
	if side > MINI_SIZE:
		head = Rect2(rect.position + Vector2(side * HEAD_SIDE, side * HEAD_TOP),
				Vector2(side * (1.0 - HEAD_SIDE * 2.0), side * (1.0 - HEAD_TOP)))
		# Антенна с шариком и уши-наушники: силуэт персонажа.
		var antenna_x: float = rect.position.x + side * ANTENNA_X
		_fill(item, Rect2(antenna_x - side * ANTENNA_WIDTH / 2.0, rect.position.y + side * ANTENNA_BALL,
				side * ANTENNA_WIDTH, side * HEAD_TOP), body, 0.0)
		item.draw_circle(Vector2(antenna_x, rect.position.y + side * ANTENNA_BALL), side * ANTENNA_BALL, body,
				true, -1.0, true)
		var ear: Color = body.darkened(EAR_SHADE)
		var ear_size: Vector2 = Vector2(side * HEAD_SIDE * 2.0, side * EAR_HEIGHT)
		_fill(item, Rect2(Vector2(rect.position.x, rect.position.y + side * EAR_TOP), ear_size), ear, side * EAR_RADIUS)
		_fill(item, Rect2(Vector2(rect.end.x - ear_size.x, rect.position.y + side * EAR_TOP), ear_size), ear,
				side * EAR_RADIUS)
	_fill(item, head, body, head.size.x * HEAD_RADIUS)
	var visor_rect: Rect2 = Rect2(head.position + VISOR_RECT.position * head.size, VISOR_RECT.size * head.size)
	_fill(item, visor_rect, visor, head.size.x * VISOR_RADIUS)
	if eyes.a <= 0.0:
		return
	var eye_y: float = head.position.y + head.size.y * EYE_CENTER_Y
	var center_x: float = head.position.x + head.size.x * (0.5 + clampf(look, -1.0, 1.0) * LOOK_SHIFT)
	for direction: float in [-1.0, 1.0]:
		var eye_center: Vector2 = Vector2(center_x + direction * head.size.x * EYE_SPREAD, eye_y)
		if dead:
			var half: float = head.size.x * DEAD_EYE_SIZE / 2.0
			UiDraw.cross(item, Rect2(eye_center - Vector2(half, half), Vector2(half, half) * 2.0), eyes,
					maxf(MIN_STROKE, head.size.x * DEAD_EYE_WIDTH))
		else:
			var eye_size: Vector2 = Vector2(maxf(MIN_STROKE * 2.0, head.size.x * EYE_WIDTH), head.size.y * EYE_HEIGHT)
			_fill(item, Rect2(eye_center - eye_size / 2.0, eye_size), eyes, eye_size.x / 2.0)


static func _fill(item: CanvasItem, rect: Rect2, color: Color, radius: float) -> void:
	_box.bg_color = color
	_box.set_corner_radius_all(roundi(radius))
	item.draw_style_box(_box, rect)


func _draw_check(rect: Rect2) -> void:
	var side: float = rect.size.x
	var radius: float = side * CHECK_SIZE / 2.0
	var center: Vector2 = rect.end - Vector2(radius, radius) + Vector2(side, side) * CHECK_OVERHANG
	# Тёмное кольцо отделяет отметку от шлема.
	draw_circle(center, radius + CHECK_RING, UiTokens.BG, true, -1.0, true)
	draw_circle(center, radius, UiTokens.SUCCESS, true, -1.0, true)
	var box: Rect2 = Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	UiDraw.check(self, box.grow(-radius * 2.0 * CHECK_INSET), UiTokens.BG, maxf(MIN_STROKE, side * CHECK_STROKE * CHECK_SIZE * 2.0))
