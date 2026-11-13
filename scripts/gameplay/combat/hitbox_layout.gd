class_name HitboxLayout
extends Resource
## Хитбоксы игрока как данные: коробки частей тела для двух поз. Значения лежат в
## resources/player/hitboxes.tres и правятся там под модель персонажа. Чистая математика
## без узлов и физики: сервер пересекает с коробками луч выстрела или удара, а стены
## отдельно проверяет один физический луч (PlayerWeapons).
## Игрок поворачивается только вокруг вертикали, поэтому его положение — точка и угол yaw.

## Коробки стоящего игрока.
@export var standing: Array[Hitbox] = []
## Коробки ползущего игрока (без обеих ног): тело лежит у пола головой вперёд.
@export var crawling: Array[Hitbox] = []


## Ползёт ли игрок с такими потерями: то же правило, что у PlayerBody.is_crawling().
static func is_crawling(limbs_lost: int) -> bool:
	return BodyPart.lost_legs(limbs_lost) >= BodyPart.LEG_COUNT


## Коробки игрока в его позе; у потерянных конечностей хитбокса нет.
func get_boxes(limbs_lost: int) -> Array[Hitbox]:
	var result: Array[Hitbox] = []
	for box: Hitbox in (crawling if is_crawling(limbs_lost) else standing):
		if box != null and not BodyPart.is_lost(limbs_lost, box.part):
			result.append(box)
	return result


## Ближайшее попадание луча в игрока; null — мимо или дальше max_distance.
## origin и direction — в координатах игрока, direction — единичный вектор.
## inflate — толщина удара в ближнем бою: если сам луч прошёл мимо, коробки раздуваются
## на эту величину и луч проверяется ещё раз. Точный прицел важнее толщины: удар, который
## смотрит прямо в торс, попадает в торс, даже если раздутая голова оказалась бы ближе.
func intersect_ray(origin: Vector3, direction: Vector3, max_distance: float, limbs_lost: int,
		inflate: float = 0.0) -> BodyHit:
	var boxes: Array[Hitbox] = get_boxes(limbs_lost)
	var hit: BodyHit = _find_nearest(boxes, origin, direction, max_distance, 0.0)
	if hit == null and inflate > 0.0:
		hit = _find_nearest(boxes, origin, direction, max_distance, inflate)
	return hit


## То же для луча в мировых координатах: игрок стоит ногами в body_position и повёрнут
## вокруг вертикали на body_yaw (Player.rotation.y).
func intersect_ray_world(origin: Vector3, direction: Vector3, max_distance: float,
		body_position: Vector3, body_yaw: float, limbs_lost: int, inflate: float = 0.0) -> BodyHit:
	var to_body: Basis = Basis(Vector3.UP, -body_yaw)
	return intersect_ray(to_body * (origin - body_position), to_body * direction, max_distance,
			limbs_lost, inflate)


func _find_nearest(boxes: Array[Hitbox], origin: Vector3, direction: Vector3, max_distance: float,
		inflate: float) -> BodyHit:
	var best: BodyHit = null
	for box: Hitbox in boxes:
		var distance: float = box.intersect_ray(origin, direction, inflate)
		if distance == Hitbox.MISS or distance > max_distance:
			continue
		if best == null or distance < best.distance:
			best = BodyHit.new(box.part, distance)
	return best
