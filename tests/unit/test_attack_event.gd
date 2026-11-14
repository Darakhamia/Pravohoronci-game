extends TestCase
## Событие атаки: раскладка массива и проверка того, что пришло клиенту по сети.

const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
const FISTS: int = 0
const PISTOL: int = 1
const CANISTER: int = 3
const FROM: Vector3 = Vector3(1.0, 1.6, 2.0)


func test_round_trip() -> void:
	var to: Vector3 = FROM + Vector3(0.0, -0.5, -20.0)
	var data: Array = AttackEvent.encode(PISTOL, FROM, to, AttackEvent.Impact.PLAYER)
	assert_eq(data.size(), AttackEvent.FIELD_COUNT, "в массиве четыре поля")
	var event: AttackEvent = AttackEvent.decode(data, ITEMS)
	if event == null:
		assert_true(false, "годное событие не разобралось")
		return
	assert_eq(event.item_index, PISTOL, "номер оружия")
	assert_true(event.weapon == ITEMS.get_item(PISTOL), "само оружие")
	assert_true(event.from == FROM and event.to == to, "точки начала и конца")
	assert_eq(event.impact, AttackEvent.Impact.PLAYER, "во что попали")
	for impact: AttackEvent.Impact in [AttackEvent.Impact.NONE, AttackEvent.Impact.WORLD]:
		var miss: AttackEvent = AttackEvent.decode(AttackEvent.encode(FISTS, FROM, FROM + Vector3.FORWARD, impact), ITEMS)
		assert_true(miss != null and miss.impact == impact, "исход %s разобран" % AttackEvent.Impact.find_key(impact))


func test_bad_data_is_rejected() -> void:
	var near: Vector3 = FROM + Vector3.FORWARD
	var bad: Array[Array] = [
		[],
		[PISTOL, FROM, near],
		[PISTOL, FROM, near, AttackEvent.Impact.NONE, 0],
		[1.0, FROM, near, AttackEvent.Impact.NONE],
		["1", FROM, near, AttackEvent.Impact.NONE],
		[PISTOL, Vector2(1.0, 2.0), near, AttackEvent.Impact.NONE],
		[PISTOL, FROM, null, AttackEvent.Impact.NONE],
		[PISTOL, FROM, near, 1.0],
		[CANISTER, FROM, near, AttackEvent.Impact.NONE],
		[-1, FROM, near, AttackEvent.Impact.NONE],
		[99, FROM, near, AttackEvent.Impact.NONE],
		[PISTOL, FROM, near, -1],
		[PISTOL, FROM, near, AttackEvent.Impact.size()],
		[PISTOL, Vector3(NAN, 0.0, 0.0), near, AttackEvent.Impact.NONE],
		[PISTOL, FROM, Vector3(0.0, INF, 0.0), AttackEvent.Impact.WORLD],
	]
	for data: Array in bad:
		assert_true(AttackEvent.decode(data, ITEMS) == null, "негодное событие отклонено: %s" % var_to_str(data))
	assert_true(AttackEvent.decode([PISTOL, FROM, near, AttackEvent.Impact.NONE], null) == null, "без набора предметов события нет")


func test_segment_cannot_be_longer_than_weapon_range() -> void:
	var fists: WeaponConfig = ITEMS.get_item(FISTS) as WeaponConfig
	var pistol: WeaponConfig = ITEMS.get_item(PISTOL) as WeaponConfig
	var punch_end: Vector3 = FROM + Vector3.FORWARD * fists.attack_range
	assert_true(AttackEvent.decode([FISTS, FROM, punch_end, AttackEvent.Impact.NONE], ITEMS) != null,
			"удар на полную дальность годится")
	var long_punch: Vector3 = FROM + Vector3.FORWARD * (fists.attack_range + AttackEvent.LENGTH_TOLERANCE + 0.1)
	assert_true(AttackEvent.decode([FISTS, FROM, long_punch, AttackEvent.Impact.PLAYER], ITEMS) == null,
			"удар кулаком дальше дальности кулака не годится")
	var shot_end: Vector3 = FROM + Vector3.FORWARD * pistol.attack_range
	assert_true(AttackEvent.decode([PISTOL, FROM, shot_end, AttackEvent.Impact.NONE], ITEMS) != null,
			"выстрел на полную дальность годится")
	var long_shot: Vector3 = FROM + Vector3.FORWARD * (pistol.attack_range * 2.0)
	assert_true(AttackEvent.decode([PISTOL, FROM, long_shot, AttackEvent.Impact.NONE], ITEMS) == null,
			"выстрел вдвое дальше дальности не годится")
