class_name HudGauge
extends HBoxContainer
## Шкала калибровки под подсказкой действия: заполняется, пока игрок держит E, зелёная
## зона показывает, когда клавишу нужно отпустить. Заполнение белое до зоны, зелёное в зоне
## и красное после неё. Только показывает то, что ей передали; скрыта, пока её не вызовут.

## Где сейчас край заполнения относительно зелёной зоны.
enum Zone { BEFORE, INSIDE, AFTER }

const TEXT_HINT: String = "Отпусти в зелёной зоне"
const TRACK_HEIGHT: float = 16.0
## Засечки по краям зоны и стрелка заполнения выступают за дорожку.
const ZONE_OVERHANG: float = 6.0
const ZONE_EDGE_WIDTH: float = 3.0
const NEEDLE_WIDTH: float = 6.0
const FULL: float = 1.0

var _zone_start: float = 0.0
var _zone_end: float = 0.0
var _fraction: float = 0.0
var _box: StyleBoxFlat = StyleBoxFlat.new()

@onready var _bar: Control = %Bar
@onready var _hint: Label = %Hint


func _ready() -> void:
	_hint.text = TEXT_HINT
	_bar.draw.connect(_draw_bar)


## Показывает шкалу с зелёной зоной от zone_start до zone_end (доли удержания, 0..1).
func show_gauge(zone_start: float, zone_end: float) -> void:
	_zone_start = clampf(minf(zone_start, zone_end), 0.0, FULL)
	_zone_end = clampf(maxf(zone_start, zone_end), 0.0, FULL)
	_bar.queue_redraw()
	if not visible:
		visible = true
		UiMotion.fade_in(self)


## Доля удержания клавиши от 0 до 1.
func set_fraction(fraction: float) -> void:
	_fraction = clampf(fraction, 0.0, FULL)
	_bar.queue_redraw()


func hide_gauge() -> void:
	visible = false
	_fraction = 0.0


func get_fraction() -> float:
	return _fraction


## Зелёная зона, которая сейчас показана: x — начало, y — конец.
func get_zone() -> Vector2:
	return Vector2(_zone_start, _zone_end)


## Где доля fraction относительно зоны: до неё, внутри или после.
static func zone_of(fraction: float, zone_start: float, zone_end: float) -> Zone:
	if fraction < zone_start:
		return Zone.BEFORE
	return Zone.INSIDE if fraction <= zone_end else Zone.AFTER


func _draw_bar() -> void:
	var width: float = _bar.size.x
	var top: float = roundf((_bar.size.y - TRACK_HEIGHT) / 2.0)
	_fill(Rect2(0.0, top, width, TRACK_HEIGHT), UiTokens.TRACK, TRACK_HEIGHT / 2.0)
	var zone_from: float = roundf(width * _zone_start)
	var zone_to: float = roundf(width * _zone_end)
	_fill(Rect2(zone_from, top, zone_to - zone_from, TRACK_HEIGHT), UiTokens.GAUGE_ZONE, 0.0)
	var head: float = roundf(width * _fraction)
	if head > 0.0:
		var color: Color = UiTokens.TEXT
		match zone_of(_fraction, _zone_start, _zone_end):
			Zone.INSIDE:
				color = UiTokens.SUCCESS
			Zone.AFTER:
				color = UiTokens.DANGER
		_fill(Rect2(0.0, top, head, TRACK_HEIGHT), color, TRACK_HEIGHT / 2.0)
		_fill(Rect2(head - NEEDLE_WIDTH / 2.0, top - ZONE_OVERHANG, NEEDLE_WIDTH, TRACK_HEIGHT + ZONE_OVERHANG * 2.0),
				color, NEEDLE_WIDTH / 2.0)
	# Засечки зоны рисуем поверх заполнения: границы видны и тогда, когда полоса их уже прошла.
	for edge: float in [zone_from, zone_to - ZONE_EDGE_WIDTH]:
		_fill(Rect2(edge, top - ZONE_OVERHANG, ZONE_EDGE_WIDTH, TRACK_HEIGHT + ZONE_OVERHANG * 2.0),
				UiTokens.SUCCESS, 0.0)


func _fill(rect: Rect2, color: Color, radius: float) -> void:
	_box.bg_color = color
	_box.set_corner_radius_all(roundi(radius))
	_bar.draw_style_box(_box, rect)
