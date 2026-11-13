extends TestCase
## Ресурсы и сцены боя: баланс оружия в .tres, стойка с оружием, геометрия эффектов.

const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
const FISTS: WeaponConfig = preload("res://resources/items/fists.tres")
const PISTOL: WeaponConfig = preload("res://resources/items/pistol.tres")
const KNIFE: WeaponConfig = preload("res://resources/items/knife.tres")
const PICKUP_SCENE: PackedScene = preload("res://scenes/items/weapon_pickup.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player.tscn")
## Верхняя грань стойки, м.
const STAND_TOP: float = 0.9
const WORLD_LAYER: int = 1
const BOTH_ARMS_LOST: int = (1 << BodyPart.Part.LEFT_ARM) | (1 << BodyPart.Part.RIGHT_ARM)


func test_weapon_balance_values() -> void:
	assert_eq(FISTS.kind, WeaponConfig.Kind.MELEE, "кулаки — ближний бой")
	assert_eq(FISTS.damage, 8, "урон кулаков")
	assert_near(FISTS.attack_range, 1.6, "дальность кулаков")
	assert_near(FISTS.attack_interval, 0.6, "пауза кулаков")
	assert_near(FISTS.draw_seconds, 0.15, "кулаки заносят")
	assert_true(not FISTS.uses_ammo and not FISTS.traitor_only and not FISTS.two_handed, "кулаки есть у всех и без патронов")
	assert_eq(PISTOL.kind, WeaponConfig.Kind.HITSCAN, "пистолет стреляет лучом")
	assert_eq(PISTOL.damage, 25, "урон пистолета")
	assert_near(PISTOL.attack_range, 60.0, "дальность пистолета")
	assert_near(PISTOL.attack_interval, 0.35, "пауза пистолета")
	assert_near(PISTOL.draw_seconds, 0.35, "пистолет достают")
	assert_near(PISTOL.spread_degrees, 0.6, "разброс пистолета")
	assert_true(PISTOL.uses_ammo and not PISTOL.traitor_only and not PISTOL.two_handed, "пистолет тратит патроны и доступен всем")
	assert_near(PISTOL.hit_radius, 0.0, "у пули толщины нет")
	assert_eq(KNIFE.kind, WeaponConfig.Kind.MELEE, "нож — ближний бой")
	assert_eq(KNIFE.damage, 100, "урон ножа")
	assert_near(KNIFE.attack_range, 1.9, "дальность ножа")
	assert_near(KNIFE.attack_interval, 1.0, "пауза ножа")
	assert_near(KNIFE.draw_seconds, 0.5, "нож достают дольше всего")
	assert_true(KNIFE.draw_seconds + KNIFE.attack_interval >= 1.0, "нож виден в руке не меньше секунды вокруг удара")
	assert_true(KNIFE.traitor_only and not KNIFE.uses_ammo, "нож только у предателя и без патронов")
	assert_true(FISTS.hit_radius > 0.0 and KNIFE.hit_radius > 0.0, "у ударов есть толщина")
	assert_true(KNIFE.damage >= PlayerBody.CONFIG.max_health, "нож убивает с одного удара в торс")
	assert_true(roundi(KNIFE.damage * PlayerBody.CONFIG.limb_multiplier) < PlayerBody.CONFIG.max_health,
			"удар ножом в конечность здорового игрока не убивает")


func test_weapons_in_hand_have_models() -> void:
	assert_true(FISTS.model == null, "пустые руки — без модели")
	assert_true(PISTOL.model != null and KNIFE.model != null, "у пистолета и ножа есть модели")
	for weapon: WeaponConfig in [PISTOL, KNIFE]:
		var model: Node3D = weapon.model.instantiate() as Node3D
		assert_true(model != null, "модель «%s» — 3D-сцена" % weapon.title)
		if model != null:
			model.free()
	assert_true(ITEMS.index_of(FISTS) == 0 and ITEMS.index_of(PISTOL) == 1 and ITEMS.index_of(KNIFE) == 2,
			"порядок оружия в наборе: кулаки, пистолет, нож")


func test_weapon_pickup_scene() -> void:
	# Корень дерева в это время ещё собирает детей: узлы добавляем к сцене запуска тестов.
	var host: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if host == null:
		assert_true(false, "у запуска тестов нет текущей сцены")
		return
	var pickup: WeaponPickup = PICKUP_SCENE.instantiate() as WeaponPickup
	if pickup == null:
		assert_true(false, "корень weapon_pickup.tscn — не WeaponPickup")
		return
	pickup.weapon = PISTOL
	pickup.ammo = 12
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.name = "77"
	host.add_child(pickup)
	host.add_child(player)
	assert_true(pickup.is_available() and pickup.state == WeaponPickup.STATE_AVAILABLE, "на новой стойке оружие лежит")
	assert_true(pickup.get_focus_position().y > STAND_TOP, "игрок смотрит на оружие поверх стойки")
	var bodies: Array[Node] = pickup.find_children("*", "StaticBody3D", true, false)
	assert_eq(bodies.size(), 1, "у стойки одно твёрдое тело")
	if bodies.size() == 1:
		var body: StaticBody3D = bodies[0] as StaticBody3D
		assert_eq(body.collision_layer, WORLD_LAYER, "стойка стоит в слое world: её не пройти и не прострелить")
		assert_true(body.find_children("*", "CollisionShape3D", true, false).size() == 1, "у стойки есть форма столкновения")
	var slot: Node3D = pickup.get_node(^"WeaponSlot") as Node3D
	assert_eq(slot.get_child_count(), 1, "клиент видит модель оружия на стойке")
	assert_true(slot.position.y > STAND_TOP + 0.02 and slot.position.y < STAND_TOP + 0.1, "оружие лежит на стойке, а не в ней и не над ней: %.3f" % slot.position.y)
	assert_eq(pickup.get_prompt(player), "Взять пистолет", "подсказка для нового оружия")
	assert_true(pickup.can_interact(player), "живой игрок с руками может взять пистолет")
	player.weapons.apply_loadout([(1 << 0) | (1 << 1), PackedInt32Array([0, 3, 0, 0])])
	assert_eq(pickup.get_prompt(player), "Взять патроны", "подсказка тому, у кого пистолет уже есть")
	player.limbs_lost = BOTH_ARMS_LOST
	assert_true(not pickup.can_interact(player), "без рук оружие не взять")
	player.limbs_lost = BodyPart.bit(BodyPart.Part.LEFT_ARM)
	assert_true(pickup.can_interact(player), "одной рукой пистолет взять можно")
	player.life = Player.Life.CORPSE
	assert_true(not pickup.can_interact(player), "мёртвый оружие не берёт")
	player.life = Player.Life.ALIVE
	player.limbs_lost = 0
	pickup.weapon = KNIFE
	assert_true(not pickup.can_interact(player), "нож со стойки не предателю не достаётся")
	assert_eq(pickup.get_prompt(player), "Взять нож", "подсказка для ножа")
	pickup.weapon = PISTOL
	# Сервер сообщил, что оружие забрали: модель исчезает, взять больше нечего.
	pickup.apply_state(WeaponPickup.STATE_TAKEN)
	assert_true(not pickup.is_available() and not slot.visible, "пустая стойка: модели не видно")
	assert_true(not pickup.can_interact(player), "с пустой стойки взять нечего")
	pickup.apply_state(WeaponPickup.STATE_AVAILABLE)
	assert_true(slot.visible, "оружие снова на стойке")
	pickup.prompt = "Схватить"
	assert_eq(pickup.get_prompt(player), "Схватить", "подсказку можно задать на карте")
	player.free()
	pickup.free()


func test_tracer_segment_transform() -> void:
	var from: Vector3 = Vector3(1.0, 1.5, 2.0)
	var to: Vector3 = Vector3(4.0, 1.5, -2.0)
	var frame: Transform3D = Tracer.get_segment_transform(from, to)
	assert_true(frame.origin.is_equal_approx((from + to) * 0.5), "след стоит в середине отрезка")
	assert_near(frame.basis.z.length(), from.distance_to(to), "длина следа — длина отрезка")
	assert_near(absf(frame.basis.z.normalized().dot((to - from).normalized())), 1.0, "след вытянут вдоль выстрела")
	assert_near(frame.basis.x.length(), 1.0, "толщина следа не меняется")
	var vertical: Transform3D = Tracer.get_segment_transform(Vector3.ZERO, Vector3.UP * 3.0)
	assert_true(vertical.is_finite() and not is_zero_approx(vertical.basis.determinant()), "вертикальный выстрел не вырождает след")
	assert_near(vertical.basis.z.length(), 3.0, "длина вертикального следа")
	var point: Transform3D = Tracer.get_segment_transform(from, from)
	assert_true(point.is_finite() and point.origin == from, "отрезок нулевой длины не ломает расчёт")


func test_tracer_starts_near_the_weapon() -> void:
	var from: Vector3 = Vector3(0.0, 1.6, 0.0)
	var to: Vector3 = Vector3(0.0, 1.6, -10.0)
	var muzzle: Vector3 = AttackEffects.get_muzzle_position(from, to)
	assert_true(muzzle.x > 0.0 and muzzle.y < from.y and muzzle.z < 0.0, "ствол — справа, ниже глаз и впереди")
	assert_true(muzzle.distance_to(from) < 1.0, "ствол рядом со стрелком")
	assert_true(AttackEffects.get_muzzle_position(from, from + Vector3.FORWARD * 0.2) == from, "в упор след идёт из точки выстрела")
	var up: Vector3 = AttackEffects.get_muzzle_position(from, from + Vector3.UP * 10.0)
	assert_true(up.is_finite() and up.y > from.y, "выстрел вертикально вверх не ломает расчёт")


## Предмет в руках — подсказка, кто предатель: в синхронизаторе аватара (он уходит каждому
## подключившемуся пиру, даже незарегистрированному) его быть не должно.
func test_held_item_is_not_replicated_to_everyone() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	var sync: MultiplayerSynchronizer = player.get_node(^"StateSync") as MultiplayerSynchronizer
	var paths: Array[String] = []
	for path: NodePath in sync.replication_config.get_properties():
		paths.append(str(path))
	assert_true(not paths.has(".:held_item"), "held_item не лежит в синхронизаторе: %s" % [paths])
	assert_true(paths.has(".:life") and paths.has(".:limbs_lost") and paths.has(".:sync_position"),
			"то, что видно в мире, реплицируется по-прежнему: %s" % [paths])
	player.free()


func test_client_accepts_held_item_only_from_the_item_set() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	var seen: Array[int] = []
	player.held_item_changed.connect(func(item_id: int) -> void: seen.append(item_id))
	player.receive_held_item(ITEMS.index_of(KNIFE))
	assert_eq(player.held_item, ITEMS.index_of(KNIFE), "клиент принял предмет из набора")
	for bad: int in [-1, ITEMS.items.size(), 99]:
		player.receive_held_item(bad)
		assert_eq(player.held_item, ITEMS.index_of(KNIFE), "номер %d вне набора отброшен" % bad)
	player.receive_held_item(ITEMS.index_of(KNIFE))
	assert_eq(seen, [ITEMS.index_of(KNIFE)] as Array[int], "сигнал — только когда предмет сменился")
	player.free()
