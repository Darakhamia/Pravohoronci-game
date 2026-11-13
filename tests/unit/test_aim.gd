extends TestCase
## Направление выстрела: взгляд по углам и случайный разброс внутри конуса оружия.

const SEED: int = 20261113
const SAMPLES: int = 2000
## Погрешность угла между единичными векторами в числах одинарной точности.
const ANGLE_EPSILON: float = 0.0005
const ONE_ARM_LOST: int = 1 << BodyPart.Part.RIGHT_ARM
const BOTH_ARMS_LOST: int = (1 << BodyPart.Part.LEFT_ARM) | (1 << BodyPart.Part.RIGHT_ARM)
const ONE_LEG_LOST: int = 1 << BodyPart.Part.LEFT_LEG


func test_direction_matches_player_look() -> void:
	assert_true(Aim.direction(0.0, 0.0).is_equal_approx(Vector3.FORWARD), "без поворота взгляд идёт в -Z")
	assert_true(Aim.direction(PI / 2.0, 0.0).is_equal_approx(Vector3.LEFT), "yaw +90° — взгляд в -X")
	assert_true(Aim.direction(0.0, PI / 2.0).is_equal_approx(Vector3.UP), "pitch +90° — взгляд вверх")
	var diagonal: Vector3 = Aim.direction(-PI / 4.0, -PI / 6.0)
	assert_near(diagonal.length(), 1.0, "направление — единичный вектор")
	assert_true(diagonal.x > 0.0 and diagonal.y < 0.0 and diagonal.z < 0.0, "вправо, вниз и вперёд")


func test_zero_spread_is_exact() -> void:
	var rng: RandomNumberGenerator = _make_rng()
	for attempt: int in 20:
		assert_true(Aim.spread_direction(0.7, -0.3, 0.0, rng).is_equal_approx(Aim.direction(0.7, -0.3)),
				"без разброса выстрел идёт точно по взгляду")
	assert_true(Aim.spread_direction(0.7, -0.3, -1.0, rng).is_equal_approx(Aim.direction(0.7, -0.3)),
			"отрицательный разброс считается нулём")


func test_spread_stays_inside_the_cone() -> void:
	var rng: RandomNumberGenerator = _make_rng()
	var looks: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(2.5, 0.4), Vector2(-1.2, -1.3), Vector2(PI, 1.5)]
	for spread_degrees: float in [0.6, 1.2, 5.0, 30.0]:
		var spread: float = deg_to_rad(spread_degrees)
		for look: Vector2 in looks:
			var base: Vector3 = Aim.direction(look.x, look.y)
			var widest: float = 0.0
			for sample: int in SAMPLES:
				var shot: Vector3 = Aim.spread_direction(look.x, look.y, spread, rng)
				widest = maxf(widest, base.angle_to(shot))
				if not is_equal_approx(shot.length(), 1.0):
					assert_true(false, "выстрел — не единичный вектор")
					return
			assert_true(widest <= spread + ANGLE_EPSILON,
					"разброс %.1f° не выходит из конуса: самый широкий выстрел %.3f°" % [spread_degrees, rad_to_deg(widest)])
			assert_true(widest >= spread * 0.9,
					"разброс %.1f° заполняет конус до края: самый широкий выстрел %.3f°" % [spread_degrees, rad_to_deg(widest)])


func test_spread_fills_the_cone_evenly() -> void:
	var rng: RandomNumberGenerator = _make_rng()
	var spread: float = deg_to_rad(10.0)
	var base: Vector3 = Aim.direction(0.0, 0.0)
	var sum: Vector3 = Vector3.ZERO
	var inner_half: int = 0
	var right_side: int = 0
	var upper_side: int = 0
	for sample: int in SAMPLES:
		var shot: Vector3 = Aim.spread_direction(0.0, 0.0, spread, rng)
		sum += shot
		inner_half += int(base.angle_to(shot) < spread * 0.5)
		right_side += int(shot.x > 0.0)
		upper_side += int(shot.y > 0.0)
	assert_true((sum / SAMPLES).normalized().angle_to(base) < deg_to_rad(0.5), "в среднем выстрелы идут по взгляду")
	# В круге половинного радиуса — четверть площади: туда попадает около четверти выстрелов.
	assert_true(inner_half > SAMPLES * 0.18 and inner_half < SAMPLES * 0.32,
			"выстрелы не скучены у центра: во внутреннем круге %d из %d" % [inner_half, SAMPLES])
	assert_true(right_side > SAMPLES * 0.42 and right_side < SAMPLES * 0.58, "вправо и влево поровну")
	assert_true(upper_side > SAMPLES * 0.42 and upper_side < SAMPLES * 0.58, "вверх и вниз поровну")


func test_one_lost_arm_widens_the_spread() -> void:
	assert_near(Aim.spread_radians(0.6, 0, 2.0), deg_to_rad(0.6), "с двумя руками разброс обычный")
	assert_near(Aim.spread_radians(0.6, ONE_ARM_LOST, 2.0), deg_to_rad(1.2), "без руки разброс вдвое больше")
	assert_near(Aim.spread_radians(0.6, BOTH_ARMS_LOST, 2.0), deg_to_rad(1.2), "без обеих рук множитель тот же")
	assert_near(Aim.spread_radians(0.6, ONE_LEG_LOST, 2.0), deg_to_rad(0.6), "ноги на разброс не влияют")
	assert_near(Aim.spread_radians(0.6, ONE_ARM_LOST, 0.5), deg_to_rad(0.6), "множитель меньше единицы разброс не сужает")
	assert_near(Aim.spread_radians(-3.0, ONE_ARM_LOST, 2.0), 0.0, "отрицательный разброс считается нулём")
	assert_near(Aim.spread_radians(0.6, ONE_ARM_LOST, PlayerBody.CONFIG.one_arm_spread_factor),
			deg_to_rad(0.6) * PlayerBody.CONFIG.one_arm_spread_factor, "множитель берётся из BodyConfig")


func _make_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng
