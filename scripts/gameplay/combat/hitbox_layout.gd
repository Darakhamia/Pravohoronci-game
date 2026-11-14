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


## Точки игрока в его координатах, по которым другие решают, виден ли он (Perception):
## центр головы, центр торса и колено — середина между ногами на высоте их центров. У позы
## без ног (ползком) колена нет. Потерянные конечности точек не убирают: смотрят на место,
## где игрок находится, а не на его руку.
func get_sight_points(limbs_lost: int) -> PackedVector3Array:
	var points: PackedVector3Array = []
	var knee: Vector3 = Vector3.ZERO
	var leg_count: int = 0
	for box: Hitbox in (crawling if is_crawling(limbs_lost) else standing):
		if box == null:
			continue
		match box.part:
			BodyPart.Part.HEAD, BodyPart.Part.TORSO:
				points.append(box.center)
			BodyPart.Part.LEFT_LEG, BodyPart.Part.RIGHT_LEG:
				knee += box.center
				leg_count += 1
	if leg_count > 0:
		points.append(knee / leg_count)
	return points


## Ближайшее попадание луча в игрока; null — мимо или дальше max_distance.
## origin и direction — в координатах игрока, direction — единичный вектор.
## inflate — толщина удара в ближнем бою: если сам луч прошёл мимо, коробки раздуваются
## на эту величину и луч проверяется ещё раз. Точный прицел важнее толщины: удар, который
## смотрит прямо в торс, попадает в торс, даже если раздутая голова оказалась бы ближе.
## Коробка, внутри которой начинается луч, не считается (см. Hitbox.intersect_ray()).
## Когда целей несколько, пользуйся intersect_ray_many(): там точный проход идёт по всем.
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


## Ближайшее попадание луча (мировые координаты) в одного из нескольких игроков; null —
## мимо всех. Игрок i стоит ногами в positions[i], повёрнут на yaws[i] и лишился limbs[i];
## в кого попали — BodyHit.body_index. Сначала точный луч проверяется по ВСЕМ игрокам, и
## только если он не попал ни в кого — по всем же коробкам, раздутым на inflate: иначе
## почти-попадание по тому, кто стоит ближе, перебивало бы точное попадание по тому,
## в кого целились.
func intersect_ray_many(origin: Vector3, direction: Vector3, max_distance: float,
		positions: PackedVector3Array, yaws: PackedFloat32Array, limbs: PackedInt32Array,
		inflate: float = 0.0) -> BodyHit:
	var count: int = mini(positions.size(), mini(yaws.size(), limbs.size()))
	var passes: PackedFloat32Array = [0.0, inflate] if inflate > 0.0 else [0.0]
	for pass_inflate: float in passes:
		var best: BodyHit = null
		for index: int in count:
			var to_body: Basis = Basis(Vector3.UP, -yaws[index])
			var hit: BodyHit = _find_nearest(get_boxes(limbs[index]), to_body * (origin - positions[index]),
					to_body * direction, max_distance, pass_inflate)
			if hit != null and (best == null or hit.distance < best.distance):
				best = hit
				best.body_index = index
		if best != null:
			return best
	return null


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
