extends TestCase
## Правила оружия игрока: что выдаётся по роли, смена по Q и цифрами, подбор, патроны,
## потерянные руки, двуручное оружие и проверка личных сообщений на клиенте.

const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
const FISTS: int = 0
const PISTOL: int = 1
const KNIFE: int = 2
const CANISTER: int = 3
## Номера во временном наборе с двуручной винтовкой.
const RIFLE: int = 1
const TEST_PISTOL: int = 2
const NO_LIMBS_LOST: int = 0
const ONE_ARM_LOST: int = 1 << BodyPart.Part.LEFT_ARM
const BOTH_ARMS_LOST: int = (1 << BodyPart.Part.LEFT_ARM) | (1 << BodyPart.Part.RIGHT_ARM)
const ONE_LEG_LOST: int = 1 << BodyPart.Part.RIGHT_LEG


func test_item_set_order_is_fixed() -> void:
	assert_eq(ITEMS.items.size(), 4, "в наборе четыре предмета")
	assert_eq(ITEMS.get_item(FISTS).title, "Кулаки", "первые — кулаки")
	assert_eq(ITEMS.get_item(PISTOL).title, "Пистолет", "второй — пистолет")
	assert_eq(ITEMS.get_item(KNIFE).title, "Нож", "третий — нож")
	assert_true(not ITEMS.get_item(CANISTER) is WeaponConfig, "четвёртый — груз, а не оружие")


func test_reset_gives_fists_to_everyone_and_knife_to_traitor() -> void:
	var crew: WeaponLoadout = _make(Game.Role.CREW)
	assert_true(crew.owns(FISTS) and not crew.owns(PISTOL) and not crew.owns(KNIFE), "у экипажа только кулаки")
	assert_eq(crew.get_owned_weapons().size(), 1, "у экипажа одно оружие")
	var traitor: WeaponLoadout = _make(Game.Role.TRAITOR)
	assert_true(traitor.owns(FISTS) and traitor.owns(KNIFE) and not traitor.owns(PISTOL), "у предателя кулаки и нож")
	assert_true(not traitor.owns(CANISTER) and not traitor.owns(-1) and not traitor.owns(99), "груз и чужие номера — не оружие")
	# Новый раунд забирает всё подобранное.
	traitor.give(PISTOL, 5)
	traitor.reset(Game.Role.CREW)
	assert_true(not traitor.owns(PISTOL) and not traitor.owns(KNIFE), "новый раунд — снова только кулаки")
	assert_eq(traitor.to_data()[1], PackedInt32Array([0, 0, 0, 0]), "патроны нового раунда обнулены")


func test_switch_cycles_owned_weapons_in_set_order() -> void:
	var crew: WeaponLoadout = _make(Game.Role.CREW)
	assert_eq(crew.next_index(FISTS, NO_LIMBS_LOST), FISTS, "с одними кулаками переключаться не на что")
	crew.give(PISTOL, 3)
	assert_eq(crew.next_index(FISTS, NO_LIMBS_LOST), PISTOL, "кулаки -> пистолет")
	assert_eq(crew.next_index(PISTOL, NO_LIMBS_LOST), FISTS, "пистолет -> кулаки: ножа у экипажа нет")
	assert_eq(crew.next_index(CANISTER, NO_LIMBS_LOST), FISTS, "с груза — на первое оружие по кругу")


## Нож в круг Q не входит: иначе предатель с пистолетом не мог бы убрать пистолет,
## не показав всем нож (кулаки -> пистолет -> нож -> кулаки).
func test_switch_never_shows_the_traitor_weapon() -> void:
	var traitor: WeaponLoadout = _make(Game.Role.TRAITOR)
	assert_eq(traitor.next_index(FISTS, NO_LIMBS_LOST), FISTS, "с одними кулаками и ножом Q ничего не делает")
	assert_eq(traitor.next_index(KNIFE, NO_LIMBS_LOST), FISTS, "нож -> кулаки: Q убирает нож")
	traitor.give(PISTOL, 1)
	assert_eq(traitor.next_index(FISTS, NO_LIMBS_LOST), PISTOL, "кулаки -> пистолет")
	assert_eq(traitor.next_index(PISTOL, NO_LIMBS_LOST), FISTS, "пистолет -> кулаки, а не нож")
	assert_eq(traitor.next_index(KNIFE, NO_LIMBS_LOST), FISTS, "нож -> кулаки и с пистолетом")
	assert_eq(traitor.next_index(CANISTER, NO_LIMBS_LOST), FISTS, "с груза — на кулаки, не на нож")
	var held: int = FISTS
	for press: int in 6:
		held = traitor.next_index(held, NO_LIMBS_LOST)
		assert_true(held != KNIFE, "нажатие Q номер %d показало нож" % (press + 1))


func test_number_keys_select_owned_weapons_directly() -> void:
	var crew: WeaponLoadout = _make(Game.Role.CREW)
	assert_eq(crew.slot_index(1, NO_LIMBS_LOST), FISTS, "1 — кулаки")
	assert_eq(crew.slot_index(2, NO_LIMBS_LOST), WeaponLoadout.NO_SLOT, "2 — пистолета ещё нет")
	assert_eq(crew.slot_index(3, NO_LIMBS_LOST), WeaponLoadout.NO_SLOT, "3 — ножа у экипажа нет")
	crew.give(PISTOL, 3)
	assert_eq(crew.slot_index(2, NO_LIMBS_LOST), PISTOL, "2 — пистолет")
	assert_eq(crew.slot_index(2, ONE_ARM_LOST), PISTOL, "пистолет берут и одной рукой")
	assert_eq(crew.slot_index(2, BOTH_ARMS_LOST), WeaponLoadout.NO_SLOT, "без рук пистолет не взять")
	assert_eq(crew.slot_index(1, BOTH_ARMS_LOST), FISTS, "без рук остаются «кулаки»")
	var traitor: WeaponLoadout = _make(Game.Role.TRAITOR)
	assert_eq(traitor.slot_index(3, NO_LIMBS_LOST), KNIFE, "3 — нож предателя")
	assert_eq(traitor.slot_index(3, BOTH_ARMS_LOST), WeaponLoadout.NO_SLOT, "без рук нож не взять")
	for slot: int in [0, -1, 4, 5, 99]:
		assert_eq(traitor.slot_index(slot, NO_LIMBS_LOST), WeaponLoadout.NO_SLOT, "клавиша %d — не оружие" % slot)
	var items: ItemSet = _make_rifle_set()
	var rifleman: WeaponLoadout = WeaponLoadout.new(items)
	rifleman.reset(Game.Role.CREW)
	rifleman.give(RIFLE, 10)
	assert_eq(rifleman.slot_index(2, NO_LIMBS_LOST), RIFLE, "двуручное берут двумя руками")
	assert_eq(rifleman.slot_index(2, ONE_ARM_LOST), WeaponLoadout.NO_SLOT, "двуручное одной рукой не взять")


func test_give_adds_weapon_then_ammo() -> void:
	var loadout: WeaponLoadout = _make(Game.Role.CREW)
	assert_eq(loadout.get_ammo(PISTOL), WeaponLoadout.NO_AMMO_COUNTER, "нет пистолета — нет счётчика")
	assert_true(loadout.give(PISTOL, 7), "пистолет выдан")
	assert_true(loadout.owns(PISTOL), "пистолет появился")
	assert_eq(loadout.get_ammo(PISTOL), 7, "патроны первого пистолета")
	assert_true(loadout.give(PISTOL, 5), "второй пистолет даёт патроны")
	assert_eq(loadout.get_ammo(PISTOL), 12, "патроны складываются")
	loadout.give(PISTOL, -4)
	assert_eq(loadout.get_ammo(PISTOL), 12, "отрицательные патроны ничего не отнимают")
	loadout.give(PISTOL, WeaponLoadout.MAX_AMMO * 2)
	assert_eq(loadout.get_ammo(PISTOL), WeaponLoadout.MAX_AMMO, "патронов не больше предела")
	assert_true(not loadout.give(CANISTER, 1) and not loadout.give(-1, 1) and not loadout.give(99, 1),
			"груз и чужие номера выдать нельзя")
	assert_eq(loadout.get_ammo(FISTS), WeaponLoadout.NO_AMMO_COUNTER, "у кулаков счётчика нет")
	assert_true(loadout.give(KNIFE, 9), "новый нож выдан")
	assert_eq(loadout.get_ammo(KNIFE), WeaponLoadout.NO_AMMO_COUNTER, "у ножа счётчика нет")
	assert_true(not loadout.give(KNIFE, 9), "второй нож брать незачем")
	assert_true(not loadout.give(FISTS, 1), "кулаки выдать нельзя: они и так есть")


func test_ammo_is_finite() -> void:
	var loadout: WeaponLoadout = _make(Game.Role.CREW)
	assert_true(not loadout.spend_ammo(PISTOL), "стрелять из пистолета, которого нет, нельзя")
	loadout.give(PISTOL, 2)
	assert_true(loadout.spend_ammo(PISTOL), "первый патрон")
	assert_true(loadout.spend_ammo(PISTOL), "второй патрон")
	assert_eq(loadout.get_ammo(PISTOL), 0, "патроны кончились")
	assert_true(not loadout.spend_ammo(PISTOL), "без патронов выстрела нет")
	assert_eq(loadout.get_ammo(PISTOL), 0, "ниже нуля патроны не уходят")
	for attempt: int in 5:
		assert_true(loadout.spend_ammo(FISTS), "кулакам патроны не нужны")
	assert_true(not loadout.spend_ammo(CANISTER), "грузом не атакуют")


func test_can_take_rules() -> void:
	var pistol: WeaponConfig = ITEMS.get_item(PISTOL) as WeaponConfig
	var knife: WeaponConfig = ITEMS.get_item(KNIFE) as WeaponConfig
	assert_true(WeaponLoadout.can_take(pistol, Game.Role.CREW, NO_LIMBS_LOST), "экипаж берёт пистолет")
	assert_true(WeaponLoadout.can_take(pistol, Game.Role.CREW, ONE_ARM_LOST), "пистолет можно взять одной рукой")
	assert_true(WeaponLoadout.can_take(pistol, Game.Role.CREW, ONE_LEG_LOST), "ноги подбору не мешают")
	assert_true(not WeaponLoadout.can_take(pistol, Game.Role.CREW, BOTH_ARMS_LOST), "без рук оружие не взять")
	assert_true(not WeaponLoadout.can_take(knife, Game.Role.CREW, NO_LIMBS_LOST), "нож экипажу не положен")
	assert_true(not WeaponLoadout.can_take(knife, Game.Role.NONE, NO_LIMBS_LOST), "нож зрителю не положен")
	assert_true(WeaponLoadout.can_take(knife, Game.Role.TRAITOR, NO_LIMBS_LOST), "предатель берёт нож")
	assert_true(not WeaponLoadout.can_take(null, Game.Role.TRAITOR, NO_LIMBS_LOST), "пустоту взять нельзя")
	var rifle: WeaponConfig = _make_rifle()
	assert_true(WeaponLoadout.can_take(rifle, Game.Role.CREW, NO_LIMBS_LOST), "двуручное берут двумя руками")
	assert_true(not WeaponLoadout.can_take(rifle, Game.Role.CREW, ONE_ARM_LOST), "двуручное одной рукой не взять")


func test_both_arms_lost_leaves_only_fists() -> void:
	var loadout: WeaponLoadout = _make(Game.Role.TRAITOR)
	loadout.give(PISTOL, 4)
	assert_true(loadout.can_hold(PISTOL, ONE_ARM_LOST) and loadout.can_hold(KNIFE, ONE_ARM_LOST),
			"одной рукой держат и пистолет, и нож")
	assert_true(loadout.can_hold(FISTS, BOTH_ARMS_LOST), "без рук остаётся пинок")
	assert_true(not loadout.can_hold(PISTOL, BOTH_ARMS_LOST) and not loadout.can_hold(KNIFE, BOTH_ARMS_LOST),
			"без рук оружие не удержать")
	assert_eq(loadout.next_index(FISTS, BOTH_ARMS_LOST), FISTS, "без рук переключаться не на что")
	assert_eq(loadout.next_index(PISTOL, BOTH_ARMS_LOST), FISTS, "без рук пистолет сменяется пустыми руками")
	assert_true(loadout.owns(PISTOL), "само оружие у игрока остаётся")
	assert_true(not loadout.can_hold(CANISTER, NO_LIMBS_LOST) and not loadout.can_hold(99, NO_LIMBS_LOST),
			"груз и чужие номера — не оружие в руках")
	var crew: WeaponLoadout = _make(Game.Role.CREW)
	assert_true(not crew.can_hold(PISTOL, NO_LIMBS_LOST), "чего нет, того не удержать")


func test_two_handed_weapon_needs_both_arms() -> void:
	var items: ItemSet = _make_rifle_set()
	var loadout: WeaponLoadout = WeaponLoadout.new(items)
	loadout.reset(Game.Role.CREW)
	loadout.give(RIFLE, 10)
	loadout.give(TEST_PISTOL, 3)
	assert_true(loadout.can_hold(RIFLE, NO_LIMBS_LOST), "двумя руками винтовку держат")
	assert_true(loadout.can_hold(RIFLE, ONE_LEG_LOST), "ноги винтовке не мешают")
	assert_true(not loadout.can_hold(RIFLE, ONE_ARM_LOST), "одной рукой винтовку не удержать")
	assert_true(loadout.can_hold(TEST_PISTOL, ONE_ARM_LOST), "а пистолет — можно")
	assert_eq(loadout.next_index(FISTS, NO_LIMBS_LOST), RIFLE, "с двумя руками винтовка в круге")
	assert_eq(loadout.next_index(FISTS, ONE_ARM_LOST), TEST_PISTOL, "с одной рукой круг пропускает винтовку")
	assert_eq(loadout.next_index(TEST_PISTOL, ONE_ARM_LOST), FISTS, "пистолет -> кулаки")
	# Игрок держал винтовку и потерял руку: держать её больше нельзя, остаётся сменить.
	assert_eq(loadout.next_index(RIFLE, ONE_ARM_LOST), TEST_PISTOL, "с винтовки без руки — на пистолет")
	loadout.reset(Game.Role.CREW)
	loadout.give(RIFLE, 10)
	assert_eq(loadout.next_index(RIFLE, ONE_ARM_LOST), FISTS, "с винтовки без руки и без другого оружия — на кулаки")


func test_loadout_data_round_trip() -> void:
	var server: WeaponLoadout = _make(Game.Role.TRAITOR)
	server.give(PISTOL, 9)
	server.spend_ammo(PISTOL)
	var client: WeaponLoadout = _make(Game.Role.CREW)
	assert_true(client.apply_data(server.to_data()), "данные сервера приняты")
	assert_true(client.owns(KNIFE) and client.owns(PISTOL), "клиент знает своё оружие")
	assert_eq(client.get_ammo(PISTOL), 8, "клиент знает свои патроны")
	assert_eq(client.get_owned_weapons().size(), 3, "кулаки, пистолет, нож")
	# Данные скопированы, а не разделены с отправителем.
	var data: Array = server.to_data()
	var ammo: PackedInt32Array = data[1]
	ammo[PISTOL] = 500
	assert_eq(server.get_ammo(PISTOL), 8, "чужой массив не меняет патроны сервера")


func test_apply_data_rejects_bad_messages() -> void:
	var owned_fists_pistol: int = (1 << FISTS) | (1 << PISTOL)
	var bad: Array[Array] = [
		[],
		[owned_fists_pistol],
		[owned_fists_pistol, PackedInt32Array([0, 5, 0, 0]), 1],
		[float(owned_fists_pistol), PackedInt32Array([0, 5, 0, 0])],
		[owned_fists_pistol, [0, 5, 0, 0]],
		["3", PackedInt32Array([0, 5, 0, 0])],
		[owned_fists_pistol, PackedInt32Array([0, 5, 0])],
		[owned_fists_pistol, PackedInt32Array([0, 5, 0, 0, 0])],
		[1 << PISTOL, PackedInt32Array([0, 5, 0, 0])],
		[owned_fists_pistol | (1 << CANISTER), PackedInt32Array([0, 5, 0, 0])],
		[owned_fists_pistol | (1 << 4), PackedInt32Array([0, 5, 0, 0])],
		[-1, PackedInt32Array([0, 5, 0, 0])],
		[owned_fists_pistol, PackedInt32Array([0, -1, 0, 0])],
		[owned_fists_pistol, PackedInt32Array([0, WeaponLoadout.MAX_AMMO + 1, 0, 0])],
		[1 << FISTS, PackedInt32Array([0, 5, 0, 0])],
		[owned_fists_pistol, PackedInt32Array([3, 5, 0, 0])],
		[owned_fists_pistol, PackedInt32Array([0, 5, 0, 2])],
	]
	for data: Array in bad:
		var loadout: WeaponLoadout = _make(Game.Role.CREW)
		loadout.give(PISTOL, 2)
		assert_true(not loadout.apply_data(data), "негодное сообщение отклонено: %s" % var_to_str(data))
		assert_eq(loadout.get_ammo(PISTOL), 2, "после негодного сообщения патроны прежние: %s" % var_to_str(data))
		assert_true(not loadout.owns(KNIFE), "после негодного сообщения оружие прежнее: %s" % var_to_str(data))
	var good: WeaponLoadout = _make(Game.Role.CREW)
	assert_true(good.apply_data([owned_fists_pistol, PackedInt32Array([0, 5, 0, 0])]), "годное сообщение принято")
	assert_eq(good.get_ammo(PISTOL), 5, "патроны из годного сообщения")
	assert_true(good.apply_data([1 << FISTS, PackedInt32Array([0, 0, 0, 0])]), "сообщение начала раунда принято")
	assert_true(not good.owns(PISTOL), "после начала раунда пистолета нет")


func test_player_weapons_apply_loadout_validates_and_signals() -> void:
	var weapons: PlayerWeapons = PlayerWeapons.new()
	var signals: Array[int] = []
	weapons.loadout_changed.connect(func() -> void: signals.append(1))
	var pistol: WeaponConfig = ITEMS.get_item(PISTOL) as WeaponConfig
	var knife: WeaponConfig = ITEMS.get_item(KNIFE) as WeaponConfig
	assert_eq(weapons.get_owned_weapons().size(), 1, "до сообщений сервера известны только кулаки")
	weapons.apply_loadout([(1 << FISTS) | (1 << PISTOL), PackedInt32Array([0, 6, 0, 0])])
	assert_eq(signals.size(), 1, "годное сообщение — один сигнал loadout_changed")
	assert_true(weapons.owns(pistol) and not weapons.owns(knife), "хозяин узнал о пистолете")
	assert_eq(weapons.get_weapon_ammo(pistol), 6, "хозяин узнал патроны")
	assert_eq(weapons.get_weapon_ammo(knife), -1, "у ножа счётчика нет")
	weapons.apply_loadout([(1 << FISTS) | (1 << PISTOL), PackedInt32Array([0, -6, 0, 0])])
	weapons.apply_loadout(["мусор"])
	weapons.apply_loadout([])
	assert_eq(signals.size(), 1, "негодные сообщения сигнала не дают")
	assert_eq(weapons.get_weapon_ammo(pistol), 6, "негодные сообщения ничего не меняют")
	assert_true(not weapons.owns(null), "пустого оружия ни у кого нет")
	weapons.free()


func test_player_weapons_attack_lock_ticks_down_on_the_owner() -> void:
	var weapons: PlayerWeapons = PlayerWeapons.new()
	var signals: Array[int] = []
	weapons.attack_lock_changed.connect(func() -> void: signals.append(1))
	assert_near(weapons.get_attack_lock_left(), 0.0, "до сообщения сервера запрета нет")
	weapons.apply_attack_lock(5.0)
	assert_near(weapons.get_attack_lock_left(), 5.0, "сервер сообщил длину запрета")
	assert_eq(signals.size(), 1, "начало запрета — сигнал")
	weapons._process(1.5)
	assert_near(weapons.get_attack_lock_left(), 3.5, "запрет идёт на клиенте сам")
	assert_eq(signals.size(), 1, "пока запрет идёт, сигналов нет")
	weapons._process(10.0)
	assert_near(weapons.get_attack_lock_left(), 0.0, "ниже нуля запрет не уходит")
	assert_eq(signals.size(), 2, "конец запрета — сигнал")
	for bad: float in [NAN, INF, -1.0, PlayerWeapons.MAX_ATTACK_LOCK_SEC + 1.0]:
		weapons.apply_attack_lock(bad)
		assert_near(weapons.get_attack_lock_left(), 0.0, "негодная длина запрета отброшена: %s" % bad)
	assert_eq(signals.size(), 2, "негодные сообщения сигнала не дают")
	weapons.apply_attack_lock(2.0)
	weapons.apply_attack_lock(0.0)
	assert_near(weapons.get_attack_lock_left(), 0.0, "сервер может снять запрет")
	weapons.free()


func _make(role: Game.Role) -> WeaponLoadout:
	var loadout: WeaponLoadout = WeaponLoadout.new(ITEMS)
	loadout.reset(role)
	return loadout


func _make_rifle() -> WeaponConfig:
	var rifle: WeaponConfig = WeaponConfig.new()
	rifle.title = "Винтовка"
	rifle.kind = WeaponConfig.Kind.HITSCAN
	rifle.two_handed = true
	rifle.uses_ammo = true
	return rifle


## Временный набор: кулаки, двуручная винтовка, пистолет.
func _make_rifle_set() -> ItemSet:
	var items: ItemSet = ItemSet.new()
	items.items = [ITEMS.get_item(FISTS), _make_rifle(), ITEMS.get_item(PISTOL)]
	return items
