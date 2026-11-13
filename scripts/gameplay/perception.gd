class_name Perception
extends RefCounted
## Кто что замечает: правило, по которому сервер решает, кому рассказать о предмете в руках
## игрока и о его атаке. Чистые функции без узлов; вызывает World на сервере.
## Наблюдатель узнаёт о другом игроке (или о точке, где закончилась атака), если:
## - это он сам: всегда и сразу;
## - у наблюдателя нет живого аватара (зритель, вошедший посреди матча, мёртвый игрок-призрак):
##   всегда — они вне игры и по задумке видят сквозь стены;
## - иначе хотя бы одна из точек цели ближе near_radius от глаз наблюдателя (вплотную слышно
##   и через стену) либо не дальше sight_range и от глаз до неё нет стен. Куда наблюдатель
##   при этом смотрит, неважно.
## Стены проверяет вызывающий: is_line_clear(from: Vector3, to: Vector3) -> bool.


## Узнаёт ли наблюдатель о цели. is_self — наблюдатель и есть цель; has_living_avatar —
## у наблюдателя есть живой аватар; eye — его глаза; points — точки цели (голова, грудь,
## колено или точка удара), всё в мировых координатах.
static func can_observe(is_self: bool, has_living_avatar: bool, eye: Vector3, points: PackedVector3Array,
		near_radius: float, sight_range: float, is_line_clear: Callable) -> bool:
	if is_self or not has_living_avatar:
		return true
	return perceives_points(eye, points, near_radius, sight_range, is_line_clear)


## Замечает ли живой наблюдатель с глазами в eye хотя бы одну из точек.
static func perceives_points(eye: Vector3, points: PackedVector3Array, near_radius: float,
		sight_range: float, is_line_clear: Callable) -> bool:
	# Сначала дешёвое: расстояния. Лучи — только если вплотную никого нет.
	for point: Vector3 in points:
		if eye.distance_to(point) <= near_radius:
			return true
	for point: Vector3 in points:
		if eye.distance_to(point) > sight_range:
			continue
		var is_clear: bool = is_line_clear.call(eye, point)
		if is_clear:
			return true
	return false
