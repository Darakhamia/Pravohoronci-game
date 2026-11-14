extends "res://tests/scenarios/combat_base.gd"
## Сценарий combat_limbs: что делают с оружием потерянные руки и смерть.
## Оба бота — экипаж (матч без предателей, поэтому смерть его не заканчивает).
## Bot1 — стрелок: берёт пистолет, пробует взять нож со стойки, отстреливает цели обе руки,
## получает от неё пинок, убивает выстрелом в голову, подбирает второй пистолет ради патронов.
## Bot2 — цель: берёт пистолет, теряет руки (пистолет пропадает из рук, Q и стойки больше
## не работают), пинает стрелка, погибает и уже мёртвой жмёт атаку и Q — впустую.
## Серверные правила дополнительно сторожит combat_director.gd.

const SHOOTER_NAME: String = "Bot1"
const TARGET_NAME: String = "Bot2"
## Патроны на стойках карты arena_combat_limbs.
const STAND_AMMO: int = 12
const SPARE_AMMO: int = 7
const STAND_STOP_DISTANCE: float = 1.6
const MARK_STOP_DISTANCE: float = 0.4
## С такого расстояния разброс пистолета меньше половины толщины руки.
const ARM_SHOT_DISTANCE: float = 3.5
const KICK_STOP_DISTANCE: float = 1.0
## С такого расстояния стрелок добивает цель в голову.
const HEAD_SHOT_DISTANCE: float = 3.0
const SHOTS_PER_ARM: int = 2
const MAX_SHOTS_PER_ARM: int = 4
const MAX_TRIES: int = 3
## Четыре попадания из пистолета в руки: 4 * 25 * 0.6 из общего здоровья.
const HEALTH_AFTER_ARMS: int = 40
## Пинок в торс.
const HEALTH_AFTER_KICK: int = 92
const BOTH_ARMS: int = (1 << BodyPart.Part.LEFT_ARM) | (1 << BodyPart.Part.RIGHT_ARM)

## Сколько выстрелов сделал стрелок.
var _shots: int = 0
## Запоминаем сразу: к концу сценария стрелок мог выйти, и по имени его уже не найти.
var _shooter_id: int = 0


func _run() -> void:
	track_avatars()
	_shooter_id = peer_named(SHOOTER_NAME)
	if not await expect(func() -> bool: return Game.local_role == Game.Role.CREW, 3.0, "в матче без предателей бот не экипаж"):
		return
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	if bot_name == SHOOTER_NAME:
		await _play_shooter()
	else:
		await _play_target()


# --- Bot1: стрелок ---


func _play_shooter() -> bool:
	var target: Player = avatar_named(TARGET_NAME)
	var target_id: int = peer_named(TARGET_NAME)
	if not await _take_nearest_pistol():
		return false
	if not await _try_knife_stand():
		return false
	if not await expect(func() -> bool: return target.held_item == PISTOL, 15.0, "цель не взяла пистолет"):
		return false
	var centre: Vector3 = (map().get_node(^"Marks/Centre") as Node3D).global_position
	if not await expect(func() -> bool: return flat_distance(target.position, centre) <= 1.0, 15.0, "цель не вышла в центр"):
		return false
	if not check(await walk_to(target.position, ARM_SHOT_DISTANCE, 10.0), "стрелок не подошёл к цели"):
		return false
	if not await expect(func() -> bool: return is_facing(target, me().position), 10.0, "цель не повернулась к стрелку"):
		return false
	await wait_seconds(SETTLE_SEC)
	# Левая рука: пистолет одноручный, цель держит его дальше.
	if not await _shoot_off(target, BodyPart.Part.LEFT_ARM):
		return false
	await wait_seconds(0.5)
	if not check(target.held_item == PISTOL, "без одной руки цель выронила одноручный пистолет"):
		return false
	# Правая рука: рук больше нет — пистолет пропадает из рук у всех на глазах.
	if not await _shoot_off(target, BodyPart.Part.RIGHT_ARM):
		return false
	if not await expect(func() -> bool: return target.held_item == FISTS, 3.0, "без рук цель всё ещё держит пистолет"):
		return false
	# Безрукая цель подходит и пинает: урон приходит хозяину, событие — всем.
	if not await expect(func() -> bool: return me().body.health == HEALTH_AFTER_KICK, 40.0,
			"стрелок не получил пинок: здоровье %d" % me().body.health):
		return false
	if not check(count_attacks(target_id, FISTS, AttackEvent.Impact.PLAYER) == 1, "стрелок не видел события пинка"):
		return false
	# Цель подошла вплотную, а игроки проходят друг сквозь друга: глаза стрелка могут
	# оказаться в чужой голове, и тогда в голову не попасть. Отходим на пару шагов.
	var away: Vector3 = me().position - target.position
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.RIGHT
	if not check(await walk_to(target.position + away.normalized() * HEAD_SHOT_DISTANCE, MARK_STOP_DISTANCE, 10.0),
			"стрелок не отошёл от цели"):
		return false
	# Выстрел в голову: у цели 40 здоровья, голова — 25 * 2.
	await wait_seconds(SETTLE_SEC)
	for attempt: int in MAX_TRIES:
		aim_at_part(target, BodyPart.Part.HEAD)
		await click(&"fire")
		if await wait_until(func() -> bool: return target.life == Player.Life.CORPSE, 4.0):
			break
	if not check(target.life == Player.Life.CORPSE, "выстрел в голову не убил цель"):
		return false
	# Считаем по патронам: сервер тратит патрон только на состоявшийся выстрел.
	_shots = STAND_AMMO - me().weapons.get_ammo()
	if not check(_shots == SHOTS_PER_ARM * BodyPart.ARM_COUNT + 1, "выстрелов %d: по два на руку и один в голову" % _shots):
		return false
	# Даём мёртвой цели время понажимать атаку и Q: ничего не должно случиться.
	await wait_seconds(2.5)
	if not check(Game.is_playing(), "матч без предателей закончился от одной смерти"):
		return false
	if not check(count_all_attacks(target_id) == 1 and target.held_item == FISTS, "мёртвый игрок атаковал или сменил оружие"):
		return false
	# Последнее действие сценария — запасная стойка: увидев её пустой, цель может выйти из
	# игры, поэтому всё, что касается аватара цели, проверяем до этого.
	if not _check_fight_seen():
		return false
	if not await _take_spare_ammo():
		return false
	return _check_stands_at_end()


## Берём пистолет с ближайшей стойки.
func _take_nearest_pistol() -> bool:
	var stand: WeaponPickup = _nearest_pistol_stand()
	if not check(await walk_to(stand.global_position, STAND_STOP_DISTANCE, 10.0), "бот не дошёл до стойки"):
		return false
	look_at_point(stand.get_focus_position())
	if not await expect(func() -> bool: return me().interactor.focus == stand, 2.0, "стойка не попала под прицел"):
		return false
	await tap(&"interact")
	return await expect(func() -> bool: return me().held_item == PISTOL and me().weapons.get_ammo() == STAND_AMMO,
			3.0, "бот не получил пистолет с патронами")


## Нож на стойке — оружие предателя: экипажу подсказки нет, а запрос в обход клиента
## сервер отклоняет.
func _try_knife_stand() -> bool:
	var stand: WeaponPickup = map().get_node(^"StandKnife") as WeaponPickup
	if not check(await walk_to(stand.global_position, STAND_STOP_DISTANCE, 10.0), "стрелок не дошёл до стойки с ножом"):
		return false
	look_at_point(stand.get_focus_position())
	await wait_seconds(0.5)
	if not check(me().interactor.focus == null, "экипажу показана подсказка «взять нож»"):
		return false
	me().interactor.press_requested.emit(stand.interact_id, true)
	await wait_seconds(0.8)
	if not check(stand.is_available(), "сервер отдал нож со стойки экипажу"):
		return false
	return check(me().held_item == PISTOL and not me().weapons.owns(ITEMS.get_item(KNIFE) as WeaponConfig),
			"у экипажа появился нож")


## Стреляем цели в руку, пока она не отлетит.
func _shoot_off(target: Player, arm: BodyPart.Part) -> bool:
	var shots: int = 0
	while shots < MAX_SHOTS_PER_ARM and not BodyPart.is_lost(target.limbs_lost, arm):
		aim_at_part(target, arm)
		await click(&"fire")
		shots += 1
		_shots += 1
		if not await expect(func() -> bool: return me().weapons.get_ammo() == STAND_AMMO - _shots, 3.0,
				"выстрел %d не потратил патрон" % _shots):
			return false
		await wait_seconds(0.6)
	var arm_name: String = BodyPart.Part.find_key(arm)
	if not check(BodyPart.is_lost(target.limbs_lost, arm), "%s не отлетела за %d выстрелов" % [arm_name, shots]):
		return false
	return check(shots == SHOTS_PER_ARM, "на %s ушло %d выстрелов вместо %d" % [arm_name, shots, SHOTS_PER_ARM])


## Второй пистолет со стойки — это патроны к своему.
func _take_spare_ammo() -> bool:
	var stand: WeaponPickup = map().get_node(^"StandSpare") as WeaponPickup
	if not check(stand.is_available(), "безрукая цель забрала пистолет со стойки"):
		return false
	if not check(await walk_to(stand.global_position, STAND_STOP_DISTANCE, 12.0), "стрелок не дошёл до запасной стойки"):
		return false
	look_at_point(stand.get_focus_position())
	if not await expect(func() -> bool: return me().interactor.focus == stand, 2.0, "запасная стойка не попала под прицел"):
		return false
	if not check(stand.get_prompt(me()) == "Взять патроны", "подсказка запасной стойки: %s" % stand.get_prompt(me())):
		return false
	await tap(&"interact")
	if not await expect(func() -> bool: return me().weapons.get_ammo() == STAND_AMMO - _shots + SPARE_AMMO, 3.0,
			"патроны со второй стойки не добавились: %d" % me().weapons.get_ammo()):
		return false
	return check(me().held_item == PISTOL and me().weapons.get_owned_weapons().size() == 2,
			"второй пистолет не должен менять набор оружия")


# --- Bot2: цель ---


func _play_target() -> bool:
	var shooter: Player = avatar_named(SHOOTER_NAME)
	var pistol: WeaponConfig = ITEMS.get_item(PISTOL) as WeaponConfig
	if not await _take_nearest_pistol():
		return false
	var centre: Vector3 = (map().get_node(^"Marks/Centre") as Node3D).global_position
	if not check(await walk_to(centre, MARK_STOP_DISTANCE, 10.0), "цель не дошла до центра"):
		return false
	# Стоим лицом к стрелку, пока он не отстрелит обе руки.
	if not await expect(func() -> bool:
		look_at_point(shooter.get_eye_position())
		return me().limbs_lost & BOTH_ARMS == BOTH_ARMS, 60.0, "цель не потеряла обе руки"):
		return false
	if not await expect(func() -> bool: return me().body.health == HEALTH_AFTER_ARMS and me().held_item == FISTS, 3.0,
			"после потери рук: здоровье %d, в руках %d" % [me().body.health, me().held_item]):
		return false
	# Пистолет остался у игрока, но держать его нечем: Q ничего не делает.
	if not check(me().weapons.owns(pistol) and me().weapons.get_weapon_ammo(pistol) == STAND_AMMO and not me().weapons.can_switch(),
			"без рук хозяин должен видеть свой пистолет, но не возможность его взять"):
		return false
	await tap(&"switch_weapon")
	await wait_seconds(0.6)
	if not check(me().held_item == FISTS, "без рук Q вернул оружие в руки"):
		return false
	if not await _try_stand_without_arms():
		return false
	# Пинок: «кулаки» без рук.
	if not check(await walk_to(shooter.position, KICK_STOP_DISTANCE, 12.0), "цель не дошла до стрелка"):
		return false
	await wait_seconds(SETTLE_SEC)
	for attempt: int in MAX_TRIES:
		aim_at_part(shooter, BodyPart.Part.TORSO)
		await click(&"fire")
		if await wait_until(func() -> bool: return count_all_attacks(Net.local_id()) >= 1, 4.0):
			break
	if not check(count_attacks(Net.local_id(), FISTS, AttackEvent.Impact.PLAYER) == 1 and count_all_attacks(Net.local_id()) == 1,
			"пинок не попал с первого раза: атак %d" % count_all_attacks(Net.local_id())):
		return false
	if not await expect(func() -> bool: return me().life == Player.Life.CORPSE, 20.0, "цель не убили выстрелом в голову"):
		return false
	if not check(me().body.health == 0, "у убитого осталось здоровье: %d" % me().body.health):
		return false
	# Мёртвый жмёт атаку и Q: матч идёт, но сервер ничего не делает.
	if not check(Game.is_playing(), "матч без предателей закончился от одной смерти"):
		return false
	for attempt: int in MAX_TRIES:
		await click(&"fire")
	await tap(&"switch_weapon")
	await wait_seconds(1.0)
	if not check(count_all_attacks(Net.local_id()) == 1 and me().held_item == FISTS and Game.is_playing(),
			"мёртвый игрок атаковал или сменил оружие"):
		return false
	# Стрелок ещё здесь: он уходит только после запасной стойки.
	if not _check_fight_seen():
		return false
	var spare: WeaponPickup = map().get_node(^"StandSpare") as WeaponPickup
	if not await expect(func() -> bool: return not spare.is_available(), 30.0, "запасная стойка не опустела"):
		return false
	return _check_stands_at_end()


## Без рук оружие со стойки не взять: подсказки нет, запрос в обход клиента отклонён.
func _try_stand_without_arms() -> bool:
	var stand: WeaponPickup = map().get_node(^"StandSpare") as WeaponPickup
	if not check(await walk_to(stand.global_position, STAND_STOP_DISTANCE, 12.0), "цель не дошла до запасной стойки"):
		return false
	look_at_point(stand.get_focus_position())
	await wait_seconds(0.5)
	if not check(me().interactor.focus == null, "безрукому показана подсказка «взять оружие»"):
		return false
	me().interactor.press_requested.emit(stand.interact_id, true)
	await wait_seconds(0.8)
	return check(stand.is_available() and me().weapons.get_weapon_ammo(ITEMS.get_item(PISTOL) as WeaponConfig) == STAND_AMMO,
			"сервер отдал оружие со стойки безрукому")


# --- Оба ---


func _nearest_pistol_stand() -> WeaponPickup:
	var left: WeaponPickup = map().get_node(^"StandLeft") as WeaponPickup
	var right: WeaponPickup = map().get_node(^"StandRight") as WeaponPickup
	var is_left_nearer: bool = me().position.distance_to(left.global_position) < me().position.distance_to(right.global_position)
	return left if is_left_nearer else right


## Бой, как его должны были увидеть оба игрока. Нужны оба аватара: вызывается, пока
## никто не вышел.
func _check_fight_seen() -> bool:
	var shooter_id: int = peer_named(SHOOTER_NAME)
	var target_id: int = peer_named(TARGET_NAME)
	var target: Player = avatar(target_id)
	if not check(target.life == Player.Life.CORPSE and target.limbs_lost == BOTH_ARMS,
			"цель должна лежать телом без обеих рук: маска %d" % target.limbs_lost):
		return false
	if not check(avatar(shooter_id).limbs_lost == 0 and avatar(shooter_id).life == Player.Life.ALIVE, "стрелок должен быть цел"):
		return false
	if not check(held_history(shooter_id) == PackedInt32Array([PISTOL]), "руки стрелка: %s" % var_to_str(held_history(shooter_id))):
		return false
	if not check(held_history(target_id) == PackedInt32Array([PISTOL, FISTS]), "руки цели: %s" % var_to_str(held_history(target_id))):
		return false
	if not check(bad_event_count() == 0, "пришли события атаки, не прошедшие проверку: %d" % bad_event_count()):
		return false
	var hits: int = count_attacks(shooter_id, PISTOL, AttackEvent.Impact.PLAYER)
	if not check(hits == SHOTS_PER_ARM * BodyPart.ARM_COUNT + 1 and count_all_attacks(shooter_id) == hits,
			"выстрелы стрелка: попаданий %d, всего %d" % [hits, count_all_attacks(shooter_id)]):
		return false
	if not check(count_attacks(target_id, FISTS, AttackEvent.Impact.PLAYER) == 1 and count_all_attacks(target_id) == 1,
			"атаки цели: %d" % count_all_attacks(target_id)):
		return false
	if not check(Game.is_playing() and Game.last_result == null, "матч должен продолжаться"):
		return false
	return check_no_private_leaks()


## Стойки в конце сценария. Чужие аватары здесь не нужны: сосед мог уже выйти.
func _check_stands_at_end() -> bool:
	for stand_name: String in ["StandLeft", "StandRight", "StandSpare"]:
		var stand: WeaponPickup = map().get_node(stand_name) as WeaponPickup
		if not check(not stand.is_available() and not (stand.get_node(^"WeaponSlot") as Node3D).visible,
				"стойка %s не опустела" % stand_name):
			return false
	if not check((map().get_node(^"StandKnife") as WeaponPickup).is_available(), "нож со стойки пропал"):
		return false
	return check(held_history(_shooter_id) == PackedInt32Array([PISTOL]),
			"второй пистолет сменил оружие в руках стрелка")
