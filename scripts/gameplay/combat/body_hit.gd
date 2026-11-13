class_name BodyHit
extends RefCounted
## Куда луч попал в игрока: результат HitboxLayout.intersect_ray().

## Часть тела, в которую луч вошёл первой.
var part: BodyPart.Part = BodyPart.Part.TORSO
## Расстояние от начала луча до точки входа, м.
var distance: float = 0.0


func _init(hit_part: BodyPart.Part, hit_distance: float) -> void:
	part = hit_part
	distance = hit_distance
