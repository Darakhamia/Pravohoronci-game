class_name Aim
extends RefCounted
## Направление выстрела: взгляд игрока и случайный разброс оружия. Чистые функции.


## Единичный вектор взгляда по углам yaw и pitch (как Player.get_look_direction()).
static func direction(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


## Разброс оружия в радианах (половина угла конуса) с учётом потерянных рук:
## без одной руки он больше в one_arm_factor раз.
static func spread_radians(spread_degrees: float, limbs_lost: int, one_arm_factor: float) -> float:
	var spread: float = deg_to_rad(maxf(spread_degrees, 0.0))
	if BodyPart.lost_arms(limbs_lost) > 0:
		spread *= maxf(one_arm_factor, 1.0)
	return spread


## Случайное направление внутри конуса вокруг взгляда: отклонение не больше spread радиан,
## точки равномерно заполняют круг. Случайные числа берёт из rng (на сервере — свой).
static func spread_direction(yaw: float, pitch: float, spread: float, rng: RandomNumberGenerator) -> Vector3:
	if spread <= 0.0:
		return direction(yaw, pitch)
	# Корень: иначе выстрелы скучивались бы у центра.
	var angle: float = spread * sqrt(rng.randf())
	var roll: float = rng.randf() * TAU
	var local: Vector3 = Vector3(sin(angle) * cos(roll), sin(angle) * sin(roll), -cos(angle))
	return (Basis.from_euler(Vector3(pitch, yaw, 0.0)) * local).normalized()
