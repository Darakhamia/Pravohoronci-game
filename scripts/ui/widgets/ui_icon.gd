class_name UiIcon
extends Control
## Маленький значок, нарисованный линиями. Размер задаёт сцена (custom_minimum_size).

enum Kind {
	## Знак тревоги: саботаж, ошибка подключения.
	ALERT,
	## Глаз: ты наблюдаешь.
	EYE,
	## Точка состояния.
	DOT,
	## Пустая точка состояния: чего-то ещё не хватает.
	RING,
	## Галочка: готово, подтвердить.
	CHECK,
	## Стереть последний символ.
	ERASE,
}

const STROKE_RATIO: float = 0.09
const MIN_STROKE: float = 2.0
## Галочка рисуется жирнее остальных значков: у неё всего два штриха.
const CHECK_STROKE_SCALE: float = 1.4

@export var kind: Kind = Kind.ALERT
@export var color: Color = UiTokens.TEXT


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(new_kind: Kind, new_color: Color) -> void:
	kind = new_kind
	color = new_color
	queue_redraw()


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	var rect: Rect2 = Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	var stroke: float = maxf(MIN_STROKE, side * STROKE_RATIO)
	match kind:
		Kind.ALERT:
			UiDraw.alert(self, rect.grow(-stroke / 2.0), color, stroke)
		Kind.EYE:
			UiDraw.eye(self, rect.grow(-stroke / 2.0), color, stroke)
		Kind.DOT:
			draw_circle(rect.get_center(), side / 2.0, color, true, -1.0, true)
		Kind.RING:
			draw_circle(rect.get_center(), (side - stroke) / 2.0, color, false, stroke, true)
		Kind.CHECK:
			UiDraw.check(self, rect.grow(-stroke), color, stroke * CHECK_STROKE_SCALE)
		Kind.ERASE:
			UiDraw.erase(self, rect.grow(-stroke / 2.0), color, stroke)
