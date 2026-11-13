extends TestCase
## Perception: кому сервер рассказывает о предмете в чужих руках и о чужой атаке.
## Стены в тестах — плоскость x = 0: луч «чист», если обе точки по одну сторону от неё.

const NEAR_RADIUS: float = 2.5
const SIGHT_RANGE: float = 45.0
const LAYOUT: HitboxLayout = preload("res://resources/player/hitboxes.tres")
const EYE_HEIGHT: float = 1.6

## Сколько раз правило спрашивало про стены.
var _ray_count: int = 0
## Точки, до которых «стена» не мешает смотреть, что бы ни было (щель, окно).
var _open_points: PackedVector3Array = []


func test_player_always_knows_about_himself() -> void:
	var points: PackedVector3Array = _points_at(Vector3(100.0, 0.0, 0.0))
	assert_true(Perception.can_observe(true, true, Vector3(-100.0, EYE_HEIGHT, 0.0), points,
			NEAR_RADIUS, SIGHT_RANGE, _is_clear), "себя игрок знает всегда")
	assert_eq(_ray_count, 0, "про себя лучи не нужны")


func test_spectators_and_ghosts_see_through_walls() -> void:
	var points: PackedVector3Array = _points_at(Vector3(300.0, 0.0, 0.0))
	assert_true(Perception.can_observe(false, false, Vector3(-300.0, EYE_HEIGHT, 0.0), points,
			NEAR_RADIUS, SIGHT_RANGE, _is_clear), "без живого аватара видно всё: и далеко, и за стеной")
	assert_eq(_ray_count, 0, "зрителю лучи не нужны")


func test_wall_hides_a_player() -> void:
	var eye: Vector3 = Vector3(-6.0, EYE_HEIGHT, 0.0)
	assert_true(not _observes(eye, Vector3(5.0, 0.0, 0.0)), "игрок за стеной не виден")
	assert_true(_observes(eye, Vector3(-12.0, 0.0, 3.0)), "игрок по эту сторону стены виден")
	assert_true(_observes(Vector3(4.0, EYE_HEIGHT, -8.0), Vector3(5.0, 0.0, 0.0)), "с той стороны стены его видно")


func test_one_visible_point_is_enough() -> void:
	var eye: Vector3 = Vector3(-6.0, EYE_HEIGHT, 0.0)
	var position: Vector3 = Vector3(5.0, 0.0, 0.0)
	for point: Vector3 in _points_at(position):
		_open_points = PackedVector3Array([point])
		assert_true(_observes(eye, position), "видна одна точка (%s) — игрок замечен" % point)
	_open_points = PackedVector3Array()
	assert_true(not _observes(eye, position), "ни одной точки не видно — не замечен")


func test_facing_does_not_matter() -> void:
	# В правило не входит, куда смотрит наблюдатель: игрок за спиной замечен так же.
	var position: Vector3 = Vector3(-10.0, 0.0, 0.0)
	assert_true(_observes(Vector3(-6.0, EYE_HEIGHT, 0.0), position), "игрок с одной стороны")
	assert_true(_observes(Vector3(-14.0, EYE_HEIGHT, 0.0), position), "и с другой")


func test_close_player_is_noticed_through_a_wall() -> void:
	var eye: Vector3 = Vector3(-0.5, EYE_HEIGHT, 0.0)
	assert_true(_observes(eye, Vector3(0.5, 0.0, 0.0)), "в метре за стеной — замечен")
	assert_eq(_ray_count, 0, "вплотную лучи не нужны")
	assert_true(_observes(eye, Vector3(-0.5 + NEAR_RADIUS - 0.05, 0.0, 0.0)), "на границе ближнего радиуса — замечен")
	assert_true(not _observes(eye, Vector3(-0.5 + NEAR_RADIUS + 0.4, 0.0, 0.0)), "чуть дальше радиуса за стеной — нет")


func test_sight_range_limits_clear_lines() -> void:
	var eye: Vector3 = Vector3(-1.0, EYE_HEIGHT, 0.0)
	assert_true(_observes(eye, Vector3(-1.0, 0.0, SIGHT_RANGE - 1.0)), "в пределах дальности по прямой — виден")
	assert_true(not _observes(eye, Vector3(-1.0, 0.0, SIGHT_RANGE + 1.0)), "дальше дальности — не виден и без стен")
	assert_eq(_ray_count, 0, "за пределами дальности лучи не пускаются")


func test_crawling_player_is_seen_low() -> void:
	var legs: int = (1 << BodyPart.Part.LEFT_LEG) | (1 << BodyPart.Part.RIGHT_LEG)
	var points: PackedVector3Array = LAYOUT.get_sight_points(legs)
	assert_true(Perception.can_observe(false, true, Vector3(-6.0, EYE_HEIGHT, 0.0), _shift(points, Vector3(-3.0, 0.0, 0.0)),
			NEAR_RADIUS, SIGHT_RANGE, _is_clear), "ползущий по эту сторону стены виден")
	assert_true(not Perception.can_observe(false, true, Vector3(-6.0, EYE_HEIGHT, 0.0), _shift(points, Vector3(3.0, 0.0, 0.0)),
			NEAR_RADIUS, SIGHT_RANGE, _is_clear), "ползущий за стеной не виден")


## То же правило для точки, где закончилась атака.
func test_attack_end_point_follows_the_same_rule() -> void:
	var eye: Vector3 = Vector3(-6.0, EYE_HEIGHT, 0.0)
	assert_true(_sees_point(eye, Vector3(-9.0, 1.2, 4.0)), "попадание на виду замечено")
	assert_true(not _sees_point(eye, Vector3(4.0, 1.2, 0.0)), "попадание за стеной не замечено")
	assert_true(_sees_point(eye, Vector3(-6.0, 0.4, 1.0)), "попадание у самых ног замечено")
	assert_true(_sees_point(Vector3(-1.0, EYE_HEIGHT, 0.0), Vector3(0.6, 1.4, 0.0)), "попадание вплотную за стеной замечено")
	assert_true(not _sees_point(eye, Vector3(-6.0, 1.2, SIGHT_RANGE + 5.0)), "слишком далёкое попадание не замечено")
	assert_true(not Perception.perceives_points(eye, PackedVector3Array(), NEAR_RADIUS, SIGHT_RANGE, _is_clear),
			"без точек замечать нечего")
	assert_true(Perception.can_observe(false, false, eye, PackedVector3Array([Vector3(4.0, 1.2, 0.0)]),
			NEAR_RADIUS, SIGHT_RANGE, _is_clear), "призрак замечает попадание и за стеной")


func _observes(eye: Vector3, subject_position: Vector3) -> bool:
	_ray_count = 0
	return Perception.can_observe(false, true, eye, _points_at(subject_position), NEAR_RADIUS, SIGHT_RANGE, _is_clear)


func _sees_point(eye: Vector3, point: Vector3) -> bool:
	return Perception.can_observe(false, true, eye, PackedVector3Array([point]), NEAR_RADIUS, SIGHT_RANGE, _is_clear)


## Точки стоящего игрока (голова, грудь, колено) в мире.
func _points_at(position: Vector3) -> PackedVector3Array:
	return _shift(LAYOUT.get_sight_points(0), position)


func _shift(points: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = []
	for point: Vector3 in points:
		result.append(point + offset)
	return result


## «Стена» — плоскость x = 0.
func _is_clear(from: Vector3, to: Vector3) -> bool:
	_ray_count += 1
	return _open_points.has(to) or signf(from.x) == signf(to.x)
