extends TestCase
## Хитбоксы игрока: луч против коробок частей тела — спереди, сбоку, сзади, сверху, мимо,
## «ближайшее попадание побеждает», поворот игрока, поза ползком, потерянные конечности,
## толщина удара. Проверяется настоящий ресурс resources/player/hitboxes.tres.

const LAYOUT: HitboxLayout = preload("res://resources/player/hitboxes.tres")
## С какого расстояния стреляем в тестах, м.
const FAR: float = 5.0
const LONG_RANGE: float = 100.0
const NO_LIMBS_LOST: int = 0
## Центры частей тела стоящего персонажа (метрики модели).
const HEAD_CENTER: Vector3 = Vector3(0.0, 1.62, 0.0)
const TORSO_CENTER: Vector3 = Vector3(0.0, 1.175, 0.0)
const LEFT_ARM_CENTER: Vector3 = Vector3(-0.3, 1.12, 0.0)
const RIGHT_ARM_CENTER: Vector3 = Vector3(0.3, 1.12, 0.0)
const LEFT_LEG_CENTER: Vector3 = Vector3(-0.11, 0.46, 0.0)
const RIGHT_LEG_CENTER: Vector3 = Vector3(0.11, 0.46, 0.0)
const HEAD_HALF_DEPTH: float = 0.17
const TORSO_HALF_DEPTH: float = 0.14
const TORSO_HALF_WIDTH: float = 0.22
const ARM_HALF_THICKNESS: float = 0.065
const LEG_HALF_THICKNESS: float = 0.085
const BODY_TOP: float = 1.79
const SHOULDER_HEIGHT: float = 1.42
const BOTH_LEGS: int = (1 << BodyPart.Part.LEFT_LEG) | (1 << BodyPart.Part.RIGHT_LEG)
const BOTH_ARMS: int = (1 << BodyPart.Part.LEFT_ARM) | (1 << BodyPart.Part.RIGHT_ARM)


func test_layout_has_every_part_standing_and_no_legs_crawling() -> void:
	var standing: Dictionary[int, bool] = {}
	for box: Hitbox in LAYOUT.standing:
		standing[box.part] = true
	assert_eq(standing.size(), BodyPart.Part.size(), "стоя есть коробка у каждой части тела")
	for box: Hitbox in LAYOUT.crawling:
		assert_true(box.part != BodyPart.Part.LEFT_LEG and box.part != BodyPart.Part.RIGHT_LEG,
				"ползут без ног: у ног коробок нет")
	assert_true(not LAYOUT.crawling.is_empty(), "у позы ползком есть коробки")


func test_every_part_is_hit_from_the_front() -> void:
	# Игрок смотрит в -Z: спереди — это со стороны -Z.
	_expect_front_hit(HEAD_CENTER, BodyPart.Part.HEAD, HEAD_HALF_DEPTH)
	_expect_front_hit(TORSO_CENTER, BodyPart.Part.TORSO, TORSO_HALF_DEPTH)
	_expect_front_hit(LEFT_ARM_CENTER, BodyPart.Part.LEFT_ARM, ARM_HALF_THICKNESS)
	_expect_front_hit(RIGHT_ARM_CENTER, BodyPart.Part.RIGHT_ARM, ARM_HALF_THICKNESS)
	_expect_front_hit(LEFT_LEG_CENTER, BodyPart.Part.LEFT_LEG, LEG_HALF_THICKNESS)
	_expect_front_hit(RIGHT_LEG_CENTER, BodyPart.Part.RIGHT_LEG, LEG_HALF_THICKNESS)


func test_every_part_is_hit_from_behind() -> void:
	var centers: Dictionary[BodyPart.Part, Vector3] = {
		BodyPart.Part.HEAD: HEAD_CENTER, BodyPart.Part.TORSO: TORSO_CENTER,
		BodyPart.Part.LEFT_ARM: LEFT_ARM_CENTER, BodyPart.Part.RIGHT_ARM: RIGHT_ARM_CENTER,
		BodyPart.Part.LEFT_LEG: LEFT_LEG_CENTER, BodyPart.Part.RIGHT_LEG: RIGHT_LEG_CENTER,
	}
	for part: BodyPart.Part in centers:
		var hit: BodyHit = _cast(centers[part] + Vector3.BACK * FAR, Vector3.FORWARD)
		assert_true(hit != null and hit.part == part, "сзади попали в %s" % BodyPart.Part.find_key(part))


func test_side_shots_hit_the_near_arm_and_leg_first() -> void:
	# Правая сторона игрока — +X.
	var from_right: BodyHit = _cast(Vector3(FAR, RIGHT_ARM_CENTER.y, 0.0), Vector3.LEFT)
	assert_true(from_right != null and from_right.part == BodyPart.Part.RIGHT_ARM, "справа первой идёт правая рука")
	assert_near(from_right.distance, FAR - RIGHT_ARM_CENTER.x - ARM_HALF_THICKNESS, "расстояние до правой руки")
	var from_left: BodyHit = _cast(Vector3(-FAR, LEFT_ARM_CENTER.y, 0.0), Vector3.RIGHT)
	assert_true(from_left != null and from_left.part == BodyPart.Part.LEFT_ARM, "слева первой идёт левая рука")
	var leg: BodyHit = _cast(Vector3(FAR, RIGHT_LEG_CENTER.y, 0.0), Vector3.LEFT)
	assert_true(leg != null and leg.part == BodyPart.Part.RIGHT_LEG, "справа первой идёт правая нога")
	var other_leg: BodyHit = _cast(Vector3(-FAR, LEFT_LEG_CENTER.y, 0.0), Vector3.RIGHT)
	assert_true(other_leg != null and other_leg.part == BodyPart.Part.LEFT_LEG, "слева первой идёт левая нога")
	# Выше плеч рук уже нет: сбоку луч попадает прямо в торс.
	var above_arms: BodyHit = _cast(Vector3(FAR, SHOULDER_HEIGHT + 0.02, 0.0), Vector3.LEFT)
	assert_true(above_arms != null and above_arms.part == BodyPart.Part.TORSO, "над плечом сбоку — торс")
	assert_near(above_arms.distance, FAR - TORSO_HALF_WIDTH, "расстояние до бока торса")


func test_shots_from_above_and_below() -> void:
	var top: BodyHit = _cast(Vector3(0.0, FAR, 0.0), Vector3.DOWN)
	assert_true(top != null and top.part == BodyPart.Part.HEAD, "сверху по центру — голова")
	assert_near(top.distance, FAR - BODY_TOP, "расстояние до макушки")
	var shoulder: BodyHit = _cast(Vector3(RIGHT_ARM_CENTER.x, FAR, 0.0), Vector3.DOWN)
	assert_true(shoulder != null and shoulder.part == BodyPart.Part.RIGHT_ARM, "сверху над плечом — рука")
	assert_near(shoulder.distance, FAR - SHOULDER_HEIGHT, "расстояние до плеча")
	# Край ноги под торсом, но уже не под головой: сверху её закрывает торс, снизу она первая.
	var over_leg: BodyHit = _cast(Vector3(0.19, FAR, 0.0), Vector3.DOWN)
	assert_true(over_leg != null and over_leg.part == BodyPart.Part.TORSO, "сверху над ногой — торс")
	var under_leg: BodyHit = _cast(Vector3(RIGHT_LEG_CENTER.x, -1.0, 0.0), Vector3.UP)
	assert_true(under_leg != null and under_leg.part == BodyPart.Part.RIGHT_LEG, "снизу — нога")
	assert_near(under_leg.distance, 1.0, "расстояние до ступни")


func test_misses() -> void:
	assert_true(_cast(Vector3(0.0, BODY_TOP + 0.1, -FAR), Vector3.BACK) == null, "над головой — мимо")
	assert_true(_cast(Vector3(0.0, 0.4, -FAR), Vector3.BACK) == null, "между ног — мимо")
	assert_true(_cast(Vector3(0.5, 1.2, -FAR), Vector3.BACK) == null, "сбоку от руки — мимо")
	assert_true(_cast(Vector3(0.228, 1.2, -FAR), Vector3.BACK) == null, "в щель между рукой и торсом — мимо")
	assert_true(_cast(TORSO_CENTER + Vector3.FORWARD * FAR, Vector3.FORWARD) == null, "луч от игрока — мимо")
	assert_true(_cast(Vector3(0.0, -0.1, -FAR), Vector3.BACK) == null, "под ногами — мимо")


func test_max_distance_limits_the_hit() -> void:
	var origin: Vector3 = TORSO_CENTER + Vector3.FORWARD * FAR
	var reach: float = FAR - TORSO_HALF_DEPTH
	assert_true(LAYOUT.intersect_ray(origin, Vector3.BACK, reach - 0.01, NO_LIMBS_LOST) == null,
			"цель чуть дальше дальности — мимо")
	assert_true(LAYOUT.intersect_ray(origin, Vector3.BACK, reach + 0.01, NO_LIMBS_LOST) != null,
			"цель чуть ближе дальности — попадание")
	assert_true(LAYOUT.intersect_ray(origin, Vector3.BACK, 0.0, NO_LIMBS_LOST) == null, "нулевая дальность — мимо")


func test_nearest_hit_wins() -> void:
	# Сверху-спереди вниз: луч входит в лицо, выходит через шею в торс — первой идёт голова.
	var down: BodyHit = _cast_at(Vector3(0.0, 2.2, -0.5), Vector3(0.0, 1.2, 0.0))
	assert_true(down != null and down.part == BodyPart.Part.HEAD, "сверху вниз через голову и торс — голова")
	# Снизу-спереди вверх: луч входит в грудь и выходит через шею в голову — первым идёт торс.
	var up: BodyHit = _cast_at(Vector3(0.0, 0.7, -0.5), Vector3(0.0, 1.7, 0.1))
	assert_true(up != null and up.part == BodyPart.Part.TORSO, "снизу вверх через торс и голову — торс")
	# Оба луча действительно проходят через обе коробки: без торса второй попал бы в голову.
	var head_only: Array[Hitbox] = LAYOUT.standing.filter(func(box: Hitbox) -> bool: return box.part == BodyPart.Part.HEAD)
	var up_direction: Vector3 = (Vector3(0.0, 1.7, 0.1) - Vector3(0.0, 0.7, -0.5)).normalized()
	assert_true(head_only[0].intersect_ray(Vector3(0.0, 0.7, -0.5), up_direction) != Hitbox.MISS,
			"луч снизу вверх проходит и через голову")
	# Сбоку насквозь: правая рука, торс, левая рука — побеждает ближняя рука.
	var through: BodyHit = _cast(Vector3(FAR, 1.2, 0.0), Vector3.LEFT)
	assert_true(through != null and through.part == BodyPart.Part.RIGHT_ARM, "сбоку насквозь — ближняя рука")


func test_ray_starting_inside_a_box_hits_at_zero_distance() -> void:
	var hit: BodyHit = _cast(TORSO_CENTER, Vector3.BACK)
	assert_true(hit != null and hit.part == BodyPart.Part.TORSO, "луч изнутри торса попадает в торс")
	assert_near(hit.distance, 0.0, "расстояние изнутри коробки")


func test_world_ray_follows_player_position_and_yaw() -> void:
	var place: Vector3 = Vector3(10.0, 2.0, -7.0)
	# Поворот на 90° влево: игрок смотрит в -X, его правая рука оказывается со стороны -Z.
	var yaw: float = PI / 2.0
	var origin: Vector3 = place + Vector3(0.0, RIGHT_ARM_CENTER.y, -FAR)
	var turned: BodyHit = LAYOUT.intersect_ray_world(origin, Vector3.BACK, LONG_RANGE, place, yaw, NO_LIMBS_LOST)
	assert_true(turned != null and turned.part == BodyPart.Part.RIGHT_ARM, "у повёрнутого игрока луч встречает правую руку")
	assert_near(turned.distance, FAR - RIGHT_ARM_CENTER.x - ARM_HALF_THICKNESS, "расстояние до руки повёрнутого игрока")
	var straight: BodyHit = LAYOUT.intersect_ray_world(origin, Vector3.BACK, LONG_RANGE, place, 0.0, NO_LIMBS_LOST)
	assert_true(straight != null and straight.part == BodyPart.Part.TORSO, "без поворота тот же луч попадает в торс")
	# Игрок развернулся кругом: слева для стрелка теперь его правая нога.
	var around: BodyHit = LAYOUT.intersect_ray_world(place + Vector3(LEFT_LEG_CENTER.x, LEFT_LEG_CENTER.y, -FAR),
			Vector3.BACK, LONG_RANGE, place, PI, NO_LIMBS_LOST)
	assert_true(around != null and around.part == BodyPart.Part.RIGHT_LEG, "у развернувшегося игрока ноги меняются местами")
	var elsewhere: BodyHit = LAYOUT.intersect_ray_world(Vector3(0.0, TORSO_CENTER.y, -FAR), Vector3.BACK,
			LONG_RANGE, place, 0.0, NO_LIMBS_LOST)
	assert_true(elsewhere == null, "игрок стоит в другом месте — мимо")


func test_lost_limbs_have_no_hitbox() -> void:
	var no_left_arm: int = BodyPart.bit(BodyPart.Part.LEFT_ARM)
	assert_true(_cast(LEFT_ARM_CENTER + Vector3.FORWARD * FAR, Vector3.BACK, no_left_arm) == null,
			"в потерянную руку попасть нельзя")
	var right_arm: BodyHit = _cast(RIGHT_ARM_CENTER + Vector3.FORWARD * FAR, Vector3.BACK, no_left_arm)
	assert_true(right_arm != null and right_arm.part == BodyPart.Part.RIGHT_ARM, "вторая рука на месте")
	var from_left: BodyHit = _cast(Vector3(-FAR, LEFT_ARM_CENTER.y, 0.0), Vector3.RIGHT, no_left_arm)
	assert_true(from_left != null and from_left.part == BodyPart.Part.TORSO, "без левой руки слева открыт торс")
	var no_right_leg: int = BodyPart.bit(BodyPart.Part.RIGHT_LEG)
	assert_true(_cast(RIGHT_LEG_CENTER + Vector3.FORWARD * FAR, Vector3.BACK, no_right_leg) == null,
			"в потерянную ногу попасть нельзя")
	var left_leg: BodyHit = _cast(LEFT_LEG_CENTER + Vector3.FORWARD * FAR, Vector3.BACK, no_right_leg)
	assert_true(left_leg != null and left_leg.part == BodyPart.Part.LEFT_LEG, "без одной ноги игрок ещё стоит")
	assert_eq(LAYOUT.get_boxes(BOTH_ARMS).size(), LAYOUT.standing.size() - BodyPart.ARM_COUNT, "без рук коробок на две меньше")


func test_crawling_player_lies_low() -> void:
	assert_true(HitboxLayout.is_crawling(BOTH_LEGS), "без обеих ног игрок ползёт")
	assert_true(not HitboxLayout.is_crawling(BodyPart.bit(BodyPart.Part.LEFT_LEG)), "без одной ноги — стоит")
	assert_true(_cast(TORSO_CENTER + Vector3.FORWARD * FAR, Vector3.BACK, BOTH_LEGS) == null,
			"на высоте груди ползущего нет")
	assert_true(_cast(HEAD_CENTER + Vector3.FORWARD * FAR, Vector3.BACK, BOTH_LEGS) == null,
			"на высоте головы ползущего нет")
	assert_true(_cast(Vector3(FAR, 0.7, 0.0), Vector3.LEFT, BOTH_LEGS) == null, "выше 0.7 м сбоку — мимо")
	var head: BodyHit = _cast(Vector3(0.0, 0.45, -FAR), Vector3.BACK, BOTH_LEGS)
	assert_true(head != null and head.part == BodyPart.Part.HEAD, "спереди у пола — голова")
	var torso: BodyHit = _cast(Vector3(0.0, 0.25, FAR), Vector3.FORWARD, BOTH_LEGS)
	assert_true(torso != null and torso.part == BodyPart.Part.TORSO, "сзади у пола — торс")
	var arm: BodyHit = _cast(Vector3(FAR, 0.12, -0.2), Vector3.LEFT, BOTH_LEGS)
	assert_true(arm != null and arm.part == BodyPart.Part.RIGHT_ARM, "сбоку у самого пола — рука")
	var from_above: BodyHit = _cast(Vector3(0.0, FAR, 0.2), Vector3.DOWN, BOTH_LEGS)
	assert_true(from_above != null and from_above.part == BodyPart.Part.TORSO, "сверху по спине — торс")
	var armless: BodyHit = _cast(Vector3(FAR, 0.12, -0.45), Vector3.LEFT, BOTH_LEGS | BOTH_ARMS)
	assert_true(armless == null, "у ползущего без рук коробок рук нет")


func test_inflation_gives_melee_thickness() -> void:
	# Луч идёт в 10 см от головы.
	var origin: Vector3 = Vector3(0.28, HEAD_CENTER.y, -FAR)
	assert_true(LAYOUT.intersect_ray(origin, Vector3.BACK, LONG_RANGE, NO_LIMBS_LOST) == null, "пуля проходит мимо головы")
	var thick: BodyHit = LAYOUT.intersect_ray(origin, Vector3.BACK, LONG_RANGE, NO_LIMBS_LOST, 0.15)
	assert_true(thick != null and thick.part == BodyPart.Part.HEAD, "толстый удар голову задевает")
	assert_near(thick.distance, FAR - HEAD_HALF_DEPTH - 0.15, "раздутая коробка начинается ближе")
	# В щели между рукой и торсом толстый удар встречает торс: он выступает вперёд дальше руки.
	var gap: BodyHit = LAYOUT.intersect_ray(Vector3(0.228, 1.2, -FAR), Vector3.BACK, LONG_RANGE, NO_LIMBS_LOST, 0.05)
	assert_true(gap != null and gap.part == BodyPart.Part.TORSO, "в щели толстый удар попадает в торс")
	# Дальность считается до раздутой коробки: удар чуть короче неё цель не достаёт.
	assert_true(LAYOUT.intersect_ray(origin, Vector3.BACK, FAR - HEAD_HALF_DEPTH - 0.16, NO_LIMBS_LOST, 0.15) == null,
			"толстый удар короче расстояния до цели — мимо")
	var negative: BodyHit = LAYOUT.intersect_ray(origin, Vector3.BACK, LONG_RANGE, NO_LIMBS_LOST, -1.0)
	assert_true(negative == null, "отрицательная толщина коробки не сжимает и не раздувает")


func test_exact_aim_beats_melee_thickness() -> void:
	# Удар ножом в упор: глаза нападающего на высоте головы цели, прицел — в центр груди.
	# Раздутая голова оказалась бы на пути раньше торса, но удар смотрит точно в торс.
	var eye: Vector3 = Vector3(0.0, 1.6, -0.9)
	var direction: Vector3 = (TORSO_CENTER - eye).normalized()
	var stab: BodyHit = LAYOUT.intersect_ray(eye, direction, 1.9, NO_LIMBS_LOST, 0.15)
	assert_true(stab != null and stab.part == BodyPart.Part.TORSO, "удар, нацеленный в грудь, попадает в торс")
	var head_box: Hitbox = LAYOUT.standing.filter(func(box: Hitbox) -> bool: return box.part == BodyPart.Part.HEAD)[0]
	assert_true(head_box.intersect_ray(eye, direction, 0.15) != Hitbox.MISS, "раздутая голова при этом стоит на пути удара")
	assert_near(stab.distance, LAYOUT.intersect_ray(eye, direction, 1.9, NO_LIMBS_LOST).distance,
			"расстояние точного попадания считается без толщины")
	# Прицел в голову остаётся попаданием в голову.
	var head: BodyHit = LAYOUT.intersect_ray(eye, (HEAD_CENTER - eye).normalized(), 1.9, NO_LIMBS_LOST, 0.15)
	assert_true(head != null and head.part == BodyPart.Part.HEAD, "удар, нацеленный в голову, попадает в голову")


func test_rotated_box() -> void:
	var box: Hitbox = Hitbox.new()
	box.size = Vector3(0.2, 0.2, 2.0)
	box.center = Vector3(0.0, 1.0, 0.0)
	assert_eq(box.intersect_ray(Vector3(0.8, 1.0, -FAR), Vector3.BACK), Hitbox.MISS, "без поворота длинная коробка в стороне")
	box.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	assert_near(box.intersect_ray(Vector3(0.8, 1.0, -FAR), Vector3.BACK), FAR - 0.1, "повёрнутая коробка легла поперёк луча")
	var cube: Hitbox = Hitbox.new()
	cube.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	assert_near(cube.intersect_ray(Vector3(0.0, 0.0, -FAR), Vector3.BACK), FAR - sqrt(2.0) / 2.0,
			"куб, повёрнутый на 45°, встречает луч ребром")
	# Наклон вперёд, как у торса ползущего: передний край выше заднего.
	var plank: Hitbox = Hitbox.new()
	plank.size = Vector3(1.0, 0.1, 2.0)
	plank.rotation_degrees = Vector3(30.0, 0.0, 0.0)
	var upper: float = plank.intersect_ray(Vector3(0.0, 0.4, -FAR), Vector3.BACK)
	var lower: float = plank.intersect_ray(Vector3(0.0, -0.4, -FAR), Vector3.BACK)
	assert_true(upper != Hitbox.MISS and upper < FAR, "верхний луч встречает поднятый передний край перед центром")
	assert_true(lower > FAR, "нижний луч встречает опущенный задний край за центром")


func test_ray_parallel_to_box_faces() -> void:
	var box: Hitbox = Hitbox.new()
	assert_near(box.intersect_ray(Vector3(0.49, 0.49, -FAR), Vector3.BACK), FAR - 0.5, "вдоль граней внутри — попадание")
	assert_eq(box.intersect_ray(Vector3(0.51, 0.0, -FAR), Vector3.BACK), Hitbox.MISS, "вдоль граней снаружи — мимо")
	assert_eq(box.intersect_ray(Vector3(0.0, 0.0, FAR), Vector3.BACK), Hitbox.MISS, "коробка позади луча — мимо")


func _expect_front_hit(center: Vector3, part: BodyPart.Part, half_depth: float) -> void:
	var hit: BodyHit = _cast(center + Vector3.FORWARD * FAR, Vector3.BACK)
	var part_name: String = BodyPart.Part.find_key(part)
	if hit == null:
		assert_true(false, "спереди в %s не попали" % part_name)
		return
	assert_eq(hit.part, part, "спереди попали в %s" % part_name)
	assert_near(hit.distance, FAR - half_depth, "расстояние до %s" % part_name)


func _cast(origin: Vector3, direction: Vector3, limbs_lost: int = NO_LIMBS_LOST) -> BodyHit:
	return LAYOUT.intersect_ray(origin, direction, LONG_RANGE, limbs_lost)


func _cast_at(origin: Vector3, target: Vector3) -> BodyHit:
	return _cast(origin, (target - origin).normalized())
