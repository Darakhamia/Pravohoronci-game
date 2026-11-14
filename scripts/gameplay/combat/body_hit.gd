class_name BodyHit
extends RefCounted
## Куда луч попал в игрока: результат HitboxLayout.intersect_ray() и intersect_ray_many().

## body_index, когда луч проверяли по одному игроку.
const SINGLE_BODY: int = 0

## Часть тела, в которую луч вошёл первой.
var part: BodyPart.Part = BodyPart.Part.TORSO
## Расстояние от начала луча до точки входа, м.
var distance: float = 0.0
## В кого попали: номер игрока в списках, переданных HitboxLayout.intersect_ray_many().
var body_index: int = SINGLE_BODY


func _init(hit_part: BodyPart.Part, hit_distance: float) -> void:
	part = hit_part
	distance = hit_distance
