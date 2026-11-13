class_name UiDraw
extends RefCounted
## Значки и фигуры, нарисованные линиями: галочка, крестик, знак тревоги, глаз, «стереть»,
## рамка прогресса.
## В шрифтах проекта этих знаков нет, а картинки ради нескольких штрихов не нужны.

## Точки галочки в долях прямоугольника.
const CHECK_POINTS: PackedVector2Array = [Vector2(0.14, 0.54), Vector2(0.4, 0.78), Vector2(0.86, 0.26)]
## Вершины знака тревоги в долях прямоугольника: верх, правый низ, левый низ.
const ALERT_POINTS: PackedVector2Array = [Vector2(0.5, 0.08), Vector2(0.96, 0.9), Vector2(0.04, 0.9)]
## Восклицательный знак внутри знака тревоги: палочка и точка, в долях высоты.
const ALERT_BAR_TOP: float = 0.38
const ALERT_BAR_BOTTOM: float = 0.62
const ALERT_DOT_Y: float = 0.76
## Глаз: высота века в долях ширины значка и радиус зрачка.
const EYE_LID_HEIGHT: float = 0.3
const EYE_PUPIL_RADIUS: float = 0.15
const EYE_SEGMENTS: int = 12
## Клавиша «стереть»: пятиугольник со стрелкой влево, в долях прямоугольника, и крестик внутри.
const ERASE_POINTS: PackedVector2Array = [
	Vector2(0.04, 0.5), Vector2(0.32, 0.18), Vector2(0.96, 0.18), Vector2(0.96, 0.82), Vector2(0.32, 0.82),
]
const ERASE_CROSS: Rect2 = Rect2(0.5, 0.36, 0.28, 0.28)
## На сколько отрезков делится каждый скруглённый угол рамки.
const CORNER_SEGMENTS: int = 6


static func check(item: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var points: PackedVector2Array = []
	for point: Vector2 in CHECK_POINTS:
		points.append(rect.position + point * rect.size)
	item.draw_polyline(points, color, width, true)


static func cross(item: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	item.draw_line(rect.position, rect.end, color, width, true)
	item.draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), color, width, true)


## Знак «стереть последний символ», как на клавише Backspace.
static func erase(item: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var points: PackedVector2Array = []
	for point: Vector2 in ERASE_POINTS:
		points.append(rect.position + point * rect.size)
	points.append(points[0])
	item.draw_polyline(points, color, width, true)
	for index: int in ERASE_POINTS.size():
		item.draw_circle(points[index], width / 2.0, color, true, -1.0, true)
	cross(item, Rect2(rect.position + ERASE_CROSS.position * rect.size, ERASE_CROSS.size * rect.size), color, width)


## Знак тревоги: треугольник с восклицательным знаком.
static func alert(item: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var points: PackedVector2Array = []
	for point: Vector2 in ALERT_POINTS:
		points.append(rect.position + point * rect.size)
	points.append(points[0])
	item.draw_polyline(points, color, width, true)
	# Стыки ломаной острые: кружки скругляют вершины.
	for index: int in ALERT_POINTS.size():
		item.draw_circle(points[index], width / 2.0, color, true, -1.0, true)
	var center_x: float = rect.position.x + rect.size.x / 2.0
	item.draw_line(Vector2(center_x, rect.position.y + rect.size.y * ALERT_BAR_TOP),
			Vector2(center_x, rect.position.y + rect.size.y * ALERT_BAR_BOTTOM), color, width, true)
	item.draw_circle(Vector2(center_x, rect.position.y + rect.size.y * ALERT_DOT_Y), width * 0.6, color, true, -1.0, true)


## Глаз: два века и зрачок.
static func eye(item: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var center: Vector2 = rect.get_center()
	var half_width: float = rect.size.x / 2.0
	var lid: float = rect.size.x * EYE_LID_HEIGHT
	for side: float in [-1.0, 1.0]:
		var points: PackedVector2Array = []
		for index: int in EYE_SEGMENTS + 1:
			var t: float = float(index) / EYE_SEGMENTS
			# Парабола от левого уголка к правому.
			points.append(center + Vector2(lerpf(-half_width, half_width, t), side * lid * 4.0 * t * (1.0 - t)))
		item.draw_polyline(points, color, width, true)
	item.draw_circle(center, rect.size.x * EYE_PUPIL_RADIUS, color, true, -1.0, true)


## Замкнутый контур скруглённого прямоугольника: от середины верхней стороны по часовой стрелке.
static func rounded_path(rect: Rect2, radius: float) -> PackedVector2Array:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var start: Vector2 = Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y)
	var points: PackedVector2Array = [start]
	# Центры углов по часовой стрелке от правого верхнего и угол, с которого начинается дуга.
	var centers: PackedVector2Array = [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r),
	]
	for corner: int in centers.size():
		var from_angle: float = -PI / 2.0 + corner * PI / 2.0
		for step: int in CORNER_SEGMENTS + 1:
			var angle: float = from_angle + PI / 2.0 * step / CORNER_SEGMENTS
			points.append(centers[corner] + Vector2(cos(angle), sin(angle)) * r)
	points.append(start)
	return points


## Рисует долю контура от его начала: fraction от 0 до 1.
static func path_progress(item: CanvasItem, path: PackedVector2Array, fraction: float, color: Color, width: float) -> void:
	if path.size() < 2 or fraction <= 0.0:
		return
	var total: float = 0.0
	for index: int in path.size() - 1:
		total += path[index].distance_to(path[index + 1])
	var left: float = total * clampf(fraction, 0.0, 1.0)
	var points: PackedVector2Array = [path[0]]
	for index: int in path.size() - 1:
		var segment: float = path[index].distance_to(path[index + 1])
		if segment >= left:
			if segment > 0.0:
				points.append(path[index].lerp(path[index + 1], left / segment))
			break
		points.append(path[index + 1])
		left -= segment
	if points.size() >= 2:
		item.draw_polyline(points, color, width, true)
