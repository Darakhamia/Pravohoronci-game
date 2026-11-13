class_name HudBodyDiagram
extends Control
## Схема тела — игрушечный космонавт, как персонаж в матче: шлем с визором, торс с галстуком,
## руки в перчатках, ноги в ботинках. Целая часть — светлая, раненая — оранжевая и краснеет,
## потерянной конечности нет: от неё остаётся красный обрубок и еле заметный след.
## Как в зеркале: лицо видно, а левая рука слева.

## Сетка схемы: 20 x 30 клеток, части заданы прямоугольниками в клетках.
const GRID: Vector2 = Vector2(20.0, 30.0)
## Квадрат, в который вписан шлем (его рисует HelmetAvatar — тот же, что в лобби и на собрании).
const HEAD_RECT: Rect2 = Rect2(3.2, 0.0, 13.6, 13.6)
const TORSO_RECT: Rect2 = Rect2(5.5, 14.4, 9.0, 8.2)
const TORSO_RADIUS: float = 1.8
const BELT_RECT: Rect2 = Rect2(5.5, 20.4, 9.0, 0.9)
## Галстук: ромб с длинным хвостом, в клетках.
const TIE_POINTS: PackedVector2Array = [
	Vector2(10.0, 14.9), Vector2(10.9, 15.8), Vector2(10.45, 18.8), Vector2(10.0, 19.6),
	Vector2(9.55, 18.8), Vector2(9.1, 15.8),
]
const LIMB_RECTS: Dictionary[BodyPart.Part, Rect2] = {
	BodyPart.Part.LEFT_ARM: Rect2(1.5, 14.4, 3.2, 8.4),
	BodyPart.Part.RIGHT_ARM: Rect2(15.3, 14.4, 3.2, 8.4),
	BodyPart.Part.LEFT_LEG: Rect2(5.5, 23.4, 4.1, 6.6),
	BodyPart.Part.RIGHT_LEG: Rect2(10.4, 23.4, 4.1, 6.6),
}
const LIMB_RADIUS: float = 1.5
## Перчатка и ботинок: тёмный конец конечности, высота в клетках.
const CUFF_HEIGHT: float = 2.3
const CUFF_SHADE: float = 0.38
## Ботинок шире ноги на столько клеток с каждой стороны.
const BOOT_OUTSET: float = 0.4
## Обрубок потерянной конечности у плеча или бедра, высота в клетках.
const STUB_HEIGHT: float = 1.4
const FULL: float = 1.0

var _fractions: PackedFloat32Array = []
var _lost_mask: int = 0
var _box: StyleBoxFlat = StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## fractions — остаток здоровья каждой части по номерам BodyPart.Part (1.0 — цела),
## lost_mask — биты BodyPart.bit() потерянных конечностей.
func set_parts(fractions: PackedFloat32Array, lost_mask: int) -> void:
	_fractions = fractions
	_lost_mask = lost_mask
	queue_redraw()


func _draw() -> void:
	var cell: float = minf(size.x / GRID.x, size.y / GRID.y)
	if cell <= 0.0:
		return
	var origin: Vector2 = ((size - GRID * cell) / 2.0).round()
	HelmetAvatar.draw_helmet(self, _to_pixels(HEAD_RECT, origin, cell), _part_color(BodyPart.Part.HEAD),
			UiTokens.VISOR, UiTokens.EYES)
	_fill(_to_pixels(TORSO_RECT, origin, cell), _part_color(BodyPart.Part.TORSO), TORSO_RADIUS * cell)
	_fill(_to_pixels(BELT_RECT, origin, cell), UiTokens.VISOR, 0.0)
	var tie: PackedVector2Array = []
	for point: Vector2 in TIE_POINTS:
		tie.append(origin + point * cell)
	draw_colored_polygon(tie, UiTokens.VISOR)
	for part: BodyPart.Part in LIMB_RECTS:
		_draw_limb(part, origin, cell)


func _draw_limb(part: BodyPart.Part, origin: Vector2, cell: float) -> void:
	var grid_rect: Rect2 = LIMB_RECTS[part]
	var rect: Rect2 = _to_pixels(grid_rect, origin, cell)
	if BodyPart.is_lost(_lost_mask, part):
		_fill(rect, UiTokens.LIMB_GHOST, LIMB_RADIUS * cell)
		_fill(_to_pixels(Rect2(grid_rect.position, Vector2(grid_rect.size.x, STUB_HEIGHT)), origin, cell),
				UiTokens.DANGER, STUB_HEIGHT * cell / 2.0)
		return
	var color: Color = _part_color(part)
	_fill(rect, color, LIMB_RADIUS * cell)
	var cuff: Rect2 = Rect2(grid_rect.position.x, grid_rect.end.y - CUFF_HEIGHT, grid_rect.size.x, CUFF_HEIGHT)
	if part == BodyPart.Part.LEFT_LEG or part == BodyPart.Part.RIGHT_LEG:
		cuff = cuff.grow_individual(BOOT_OUTSET, 0.0, BOOT_OUTSET, 0.0)
	_fill(_to_pixels(cuff, origin, cell), color.darkened(CUFF_SHADE), LIMB_RADIUS * cell)


func _part_color(part: BodyPart.Part) -> Color:
	return UiTokens.damage_color(_fractions[part] if part < _fractions.size() else FULL)


func _fill(rect: Rect2, color: Color, radius: float) -> void:
	_box.bg_color = color
	_box.set_corner_radius_all(roundi(radius))
	draw_style_box(_box, rect)


static func _to_pixels(grid_rect: Rect2, origin: Vector2, cell: float) -> Rect2:
	var from: Vector2 = (origin + grid_rect.position * cell).round()
	var to: Vector2 = (origin + grid_rect.end * cell).round()
	return Rect2(from, to - from)
