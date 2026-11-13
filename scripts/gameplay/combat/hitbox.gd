class_name Hitbox
extends Resource
## Одна коробка хитбокса: часть тела игрока в его собственных координатах (ноги стоят
## в начале координат, вперёд смотрит -Z, правая сторона игрока — +X). Физики у коробки
## нет: луч выстрела пересекается с ней формулой. Набор коробок — HitboxLayout.

## Результат intersect_ray(), когда луч прошёл мимо.
const MISS: float = -1.0

## Какая это часть тела.
@export var part: BodyPart.Part = BodyPart.Part.TORSO
## Центр коробки, м.
@export var center: Vector3 = Vector3.ZERO
## Полный размер по осям самой коробки, м.
@export var size: Vector3 = Vector3.ONE
## Поворот коробки вокруг её центра (углы Эйлера, как у Node3D).
@export var rotation_degrees: Vector3 = Vector3.ZERO


## Оси коробки в координатах игрока.
func get_basis() -> Basis:
	return Basis.from_euler(Vector3(
			deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y), deg_to_rad(rotation_degrees.z)))


## Расстояние вдоль луча до входа в коробку; MISS — луч идёт мимо. Начало луча внутри
## коробки — это попадание на расстоянии 0. origin и direction — в координатах игрока,
## direction — единичный вектор. inflate раздувает коробку во все стороны (толщина удара).
func intersect_ray(origin: Vector3, direction: Vector3, inflate: float = 0.0) -> float:
	# Для поворота обратная матрица — транспонированная.
	var to_box: Basis = get_basis().transposed()
	var local_origin: Vector3 = to_box * (origin - center)
	var local_direction: Vector3 = to_box * direction
	var half: Vector3 = size * 0.5 + Vector3.ONE * maxf(inflate, 0.0)
	var enter: float = 0.0
	var exit: float = INF
	for axis: int in 3:
		var start: float = local_origin[axis]
		var step: float = local_direction[axis]
		if is_zero_approx(step):
			# Луч идёт вдоль этой пары граней: либо между ними, либо мимо.
			if absf(start) > half[axis]:
				return MISS
			continue
		var near: float = (-half[axis] - start) / step
		var far: float = (half[axis] - start) / step
		if near > far:
			var swap: float = near
			near = far
			far = swap
		enter = maxf(enter, near)
		exit = minf(exit, far)
		if enter > exit:
			return MISS
	return enter
