extends "res://tests/scenarios/combat_base.gd"
## Сценарий combat: бой от начала до конца на настоящем сервере.
## Bot1 — предатель (флаг сервера): прячется за стеной, там достаёт нож (цифрой 3), выходит
## с ним на глаза и убивает. Из-за стены он не видит ни выстрелов, ни чужих рук.
## Bot2 — стрелок: берёт пистолет со стойки, стреляет сквозь стену, по ноге, меняет оружие.
## Bot3 — жертва: пробует достать нож и ударить издалека, теряет ногу и погибает.
## Каждый бот проверяет то, что должен видеть именно он; серверные правила (темп атак,
## дальность, время доставания) дополнительно сторожит combat_director.gd.

const TRAITOR_NAME: String = "Bot1"
const SHOOTER_NAME: String = "Bot2"
const VICTIM_NAME: String = "Bot3"
## Патроны на стойке карты arena_combat.
const STAND_AMMO: int = 30
const STAND_STOP_DISTANCE: float = 1.6
const MARK_STOP_DISTANCE: float = 0.4
const HIDE_SPOT_RADIUS: float = 0.8
## Откуда предатель бьёт ножом: на таком расстоянии перед жертвой.
const KNIFE_DISTANCE: float = 1.0
const KNIFE_STOP_DISTANCE: float = 0.25
const RAPID_CLICKS: int = 12
## Запас времени на путь пакетов при подсчёте, сколько выстрелов сервер мог пропустить.
const RAPID_SLACK_SEC: float = 0.5
const LEG_SHOTS_NEEDED: int = 2
const MAX_LEG_SHOTS: int = 5
const MAX_STABS: int = 3
## Два попадания из пистолета в ногу: 2 * 25 * 0.6 из общего здоровья.
const HEALTH_AFTER_LEG: int = 70


func _run() -> void:
	track_avatars()
	if not await _check_start():
		return
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	var played: bool = false
	match bot_name:
		TRAITOR_NAME:
			played = await _play_traitor()
		SHOOTER_NAME:
			played = await _play_shooter()
		VICTIM_NAME:
			played = await _play_victim()
	if not played:
		return
	if not await _check_what_everyone_saw():
		return
	await expect(func() -> bool: return Game.state == Game.State.LOBBY and world.current_map == null,
			10.0, "после итогов сервер не вернул игроков в лобби")


## Все: на старте у каждого пустые руки, своё оружие по роли знает только хозяин.
func _check_start() -> bool:
	if not await expect(func() -> bool: return Game.local_role != Game.Role.NONE, 3.0, "сервер не прислал роль"):
		return false
	var is_traitor: bool = bot_name == TRAITOR_NAME
	if not check((Game.local_role == Game.Role.TRAITOR) == is_traitor, "роль бота не та, что задана серверу"):
		return false
	var weapons: PlayerWeapons = me().weapons
	if not await expect(func() -> bool: return weapons.get_owned_weapons().size() == (2 if is_traitor else 1),
			3.0, "хозяин не получил свой набор оружия: %d" % weapons.get_owned_weapons().size()):
		return false
	if not check(weapons.owns(ITEMS.get_item(KNIFE) as WeaponConfig) == is_traitor, "нож должен быть только у предателя"):
		return false
	# Нож в круг Q не входит: с одними кулаками (и ножом) Q ничего не делает.
	if not check(not weapons.can_switch(), "на старте Q никому не должен быть доступен"):
		return false
	if not check(weapons.get_held_item().title == "Кулаки" and weapons.get_ammo() == WeaponLoadout.NO_AMMO_COUNTER,
			"на старте в руках должны быть кулаки без счётчика патронов"):
		return false
	for peer_id: int in Net.players:
		if not check(avatar(peer_id).held_item == FISTS, "на старте у игрока %s не пустые руки" % Net.get_player_name(peer_id)):
			return false
	return check_no_private_leaks()


# --- Bot3: жертва ---


func _play_victim() -> bool:
	var shooter: Player = avatar_named(SHOOTER_NAME)
	# Экипажу нож не достаётся: ни Q, ни цифра 3 ничего не меняют.
	await tap(&"switch_weapon")
	await tap_slot(SLOT_KNIFE)
	await wait_seconds(0.6)
	if not check(me().held_item == FISTS and held_history(Net.local_id()).is_empty(), "экипаж сменил оружие клавишей Q или 3"):
		return false
	if not await expect(func() -> bool: return shooter.held_item == PISTOL, 15.0, "стрелок не взял пистолет"):
		return false
	# Удар кулаком издалека: атака состоялась, но ни в кого не попала. Ждём, пока предатель
	# уйдёт в укрытие: по дороге он проходит сквозь соседей и попал бы под кулак.
	var traitor: Player = avatar_named(TRAITOR_NAME)
	var fists: WeaponConfig = ITEMS.get_item(FISTS) as WeaponConfig
	var hide_spot: Vector3 = (map().get_node(^"Marks/HideSpot") as Node3D).global_position
	if not await expect(func() -> bool: return flat_distance(traitor.position, hide_spot) <= HIDE_SPOT_RADIUS,
			20.0, "предатель не дошёл до укрытия"):
		return false
	if not check(flat_distance(me().position, shooter.position) > fists.attack_range + 1.0, "стрелок слишком близко для проверки"):
		return false
	aim_at_part(shooter, BodyPart.Part.TORSO)
	await click(&"fire")
	if not await expect(func() -> bool: return count_attacks(Net.local_id(), FISTS, AttackEvent.Impact.NONE) == 1,
			3.0, "событие удара кулаком мимо не пришло"):
		return false
	# Стоим лицом к стрелку, пока он не отстрелит ногу.
	if not await expect(func() -> bool:
		look_at_point(shooter.get_eye_position())
		return BodyPart.is_lost(me().limbs_lost, BodyPart.Part.LEFT_LEG), 40.0, "жертва не потеряла ногу"):
		return false
	if not await expect(func() -> bool: return me().body.health == HEALTH_AFTER_LEG, 2.0,
			"хозяин не получил своё здоровье после двух попаданий в ногу: %d" % me().body.health):
		return false
	if not check(me().body.part_health[BodyPart.Part.LEFT_LEG] == 0, "здоровье потерянной ноги не ноль"):
		return false
	if not await expect(func() -> bool: return me().life == Player.Life.CORPSE, 40.0, "жертву не убили ножом"):
		return false
	if not check(me().body.health == 0, "у убитого осталось здоровье: %d" % me().body.health):
		return false
	return await expect(func() -> bool: return get_viewport().get_camera_3d() is GhostCamera, 2.0,
			"мёртвый игрок не получил камеру призрака")


# --- Bot2: стрелок ---


func _play_shooter() -> bool:
	var stand: WeaponPickup = map().get_interactables()[0] as WeaponPickup
	var pistol: WeaponConfig = ITEMS.get_item(PISTOL) as WeaponConfig
	if not check(await walk_to(stand.global_position, STAND_STOP_DISTANCE, 8.0), "стрелок не дошёл до стойки"):
		return false
	look_at_point(stand.get_focus_position())
	if not await expect(func() -> bool: return me().interactor.focus == stand, 2.0, "стойка не попала под прицел"):
		return false
	if not check(stand.get_prompt(me()) == "Взять пистолет", "подсказка стойки: %s" % stand.get_prompt(me())):
		return false
	await tap(&"interact")
	if not await expect(func() -> bool: return me().held_item == PISTOL and me().weapons.get_ammo() == STAND_AMMO,
			3.0, "стрелок не получил пистолет с патронами: в руках %d, патронов %d" % [me().held_item, me().weapons.get_ammo()]):
		return false
	if not check(me().weapons.owns(pistol) and me().weapons.get_owned_weapons().size() == 2 and me().weapons.can_switch(),
			"хозяин не знает, что у него теперь кулаки и пистолет"):
		return false
	if not await _shoot_through_wall():
		return false
	if not await _shoot_leg():
		return false
	# Ждём, пока предатель выйдет из-за стены с ножом: свой круг оружия показываем при нём.
	var traitor: Player = avatar_named(TRAITOR_NAME)
	if not await expect(func() -> bool: return traitor.held_item == KNIFE, 40.0, "стрелок не увидел нож вышедшего предателя"):
		return false
	# Q у экипажа ходит по кругу кулаки — пистолет; ножа в круге нет.
	await tap(&"switch_weapon")
	if not await expect(func() -> bool: return me().held_item == FISTS, 3.0, "Q не убрал пистолет"):
		return false
	if not check(me().weapons.get_ammo() == WeaponLoadout.NO_AMMO_COUNTER, "у кулаков появился счётчик патронов"):
		return false
	await wait_seconds(0.3)
	await tap(&"switch_weapon")
	if not await expect(func() -> bool: return me().held_item == PISTOL, 3.0, "Q не вернул пистолет"):
		return false
	if not check(count_attacks(peer_named(VICTIM_NAME), FISTS) == 1, "стрелок не видел удара кулаком издалека"):
		return false
	if not check(me().body.health == PlayerBody.CONFIG.max_health, "удар кулаком издалека нанёс урон: %d" % me().body.health):
		return false
	return await expect(func() -> bool: return avatar_named(VICTIM_NAME).life == Player.Life.CORPSE, 40.0,
			"предатель не убил жертву")


## Цель стоит за стеной: выстрелы упираются в стену. Заодно щёлкаем чаще, чем пистолет
## умеет стрелять: сервер пропускает только выстрелы с положенной паузой.
func _shoot_through_wall() -> bool:
	var traitor: Player = avatar_named(TRAITOR_NAME)
	var hide_spot: Vector3 = (map().get_node(^"Marks/HideSpot") as Node3D).global_position
	var pistol: WeaponConfig = ITEMS.get_item(PISTOL) as WeaponConfig
	if not await expect(func() -> bool: return flat_distance(traitor.position, hide_spot) <= HIDE_SPOT_RADIUS,
			20.0, "предатель не дошёл до укрытия"):
		return false
	await wait_seconds(SETTLE_SEC)
	var started_msec: int = Time.get_ticks_msec()
	for attempt: int in RAPID_CLICKS:
		aim_at_part(traitor, BodyPart.Part.TORSO)
		await click(&"fire")
	var elapsed_sec: float = (Time.get_ticks_msec() - started_msec) / MSEC_PER_SEC
	await wait_seconds(0.8)
	var shots: int = STAND_AMMO - me().weapons.get_ammo()
	var most_shots: int = 1 + int((elapsed_sec + RAPID_SLACK_SEC) / pistol.attack_interval)
	step("за %.2f с и %d щелчков сервер пропустил %d выстрелов (не больше %d)" % [elapsed_sec, RAPID_CLICKS, shots, most_shots])
	if not check(shots >= 1 and shots < RAPID_CLICKS and shots <= most_shots,
			"пистолет выстрелил %d раз за %.2f с и %d щелчков" % [shots, elapsed_sec, RAPID_CLICKS]):
		return false
	if not await expect(func() -> bool: return count_attacks(Net.local_id(), PISTOL) == shots, 3.0,
			"событий выстрела %d, а патронов ушло %d" % [count_attacks(Net.local_id(), PISTOL), shots]):
		return false
	return check(count_attacks(Net.local_id(), PISTOL, AttackEvent.Impact.WORLD) == shots,
			"не все выстрелы в цель за стеной упёрлись в стену")


## Стреляем жертве в левую ногу, пока она не отлетит.
func _shoot_leg() -> bool:
	var victim: Player = avatar_named(VICTIM_NAME)
	if not await expect(func() -> bool: return is_facing(victim, me().position), 10.0, "жертва не повернулась к стрелку"):
		return false
	await wait_seconds(SETTLE_SEC)
	var ammo_before: int = me().weapons.get_ammo()
	var leg_shots: int = 0
	while leg_shots < MAX_LEG_SHOTS and not BodyPart.is_lost(victim.limbs_lost, BodyPart.Part.LEFT_LEG):
		aim_at_part(victim, BodyPart.Part.LEFT_LEG)
		await click(&"fire")
		leg_shots += 1
		if not await expect(func() -> bool: return me().weapons.get_ammo() == ammo_before - leg_shots, 3.0,
				"выстрел %d по ноге не потратил патрон" % leg_shots):
			return false
		# Пауза пистолета и время, за которое потеря ноги дойдёт до бота.
		await wait_seconds(0.6)
	if not check(BodyPart.is_lost(victim.limbs_lost, BodyPart.Part.LEFT_LEG), "нога жертвы не отлетела за %d выстрелов" % leg_shots):
		return false
	return check(leg_shots == LEG_SHOTS_NEEDED, "на ногу ушло %d выстрелов вместо %d" % [leg_shots, LEG_SHOTS_NEEDED])


# --- Bot1: предатель ---


func _play_traitor() -> bool:
	var victim: Player = avatar_named(VICTIM_NAME)
	var shooter_id: int = peer_named(SHOOTER_NAME)
	var approach: Vector3 = (map().get_node(^"Marks/HideApproach") as Node3D).global_position
	var hide_spot: Vector3 = (map().get_node(^"Marks/HideSpot") as Node3D).global_position
	# В укрытие — в обход стены.
	if not check(await walk_to(approach, MARK_STOP_DISTANCE, 12.0), "предатель не дошёл до угла стены"):
		return false
	if not check(await walk_to(hide_spot, MARK_STOP_DISTANCE, 8.0), "предатель не дошёл до укрытия"):
		return false
	if not await expect(func() -> bool: return BodyPart.is_lost(victim.limbs_lost, BodyPart.Part.LEFT_LEG),
			50.0, "предатель не дождался, пока жертва потеряет ногу"):
		return false
	# За стеной не видно и не слышно: ни выстрелов в стену, ни попаданий по ноге, ни кулака.
	await wait_seconds(0.5)
	if not check(count_all_attacks(shooter_id) == 0 and count_all_attacks(victim.peer_id) == 0,
			"предатель за стеной узнал о чужих атаках: стрелка %d, жертвы %d" % [
			count_all_attacks(shooter_id), count_all_attacks(victim.peer_id)]):
		return false
	if not check(me().body.health == PlayerBody.CONFIG.max_health, "выстрелы сквозь стену нанесли урон: %d" % me().body.health):
		return false
	# Q нож не даёт: его достают цифрой. Достаём в укрытии — никто этого не видит.
	await tap(&"switch_weapon")
	await wait_seconds(0.5)
	if not check(me().held_item == FISTS, "Q дал предателю нож"):
		return false
	if not await draw_weapon(SLOT_KNIFE, KNIFE):
		return false
	if not check(me().weapons.get_held_item().title == "Нож" and me().weapons.get_ammo() == WeaponLoadout.NO_AMMO_COUNTER,
			"в руках предателя должен быть нож без счётчика патронов"):
		return false
	if not check(me().weapons.can_switch(), "с ножом в руке Q должен его убирать"):
		return false
	if not check(await walk_to(approach, MARK_STOP_DISTANCE, 8.0), "предатель не вышел из укрытия"):
		return false
	# На виду: стрелок замечает нож и показывает свой круг оружия — ждём, чтобы матч
	# не кончился раньше.
	if not await expect(func() -> bool: return held_history(shooter_id) == PackedInt32Array([PISTOL, FISTS, PISTOL]),
			30.0, "предатель не увидел, как стрелок дважды сменил оружие: %s" % var_to_str(held_history(shooter_id))):
		return false
	# Подходим спереди: сбоку на пути ножа оказалась бы рука, а удар в руку не убивает.
	var stab_point: Vector3 = victim.global_position - victim.global_basis.z * KNIFE_DISTANCE
	if not check(await walk_to(stab_point, KNIFE_STOP_DISTANCE, 15.0), "предатель не дошёл до жертвы"):
		return false
	await wait_seconds(SETTLE_SEC)
	for attempt: int in MAX_STABS:
		aim_at_part(victim, BodyPart.Part.TORSO)
		await click(&"fire")
		if await wait_until(func() -> bool: return victim.life == Player.Life.CORPSE, 4.0):
			break
	if not check(victim.life == Player.Life.CORPSE, "нож не убил жертву за %d ударов" % MAX_STABS):
		return false
	return check(count_attacks(Net.local_id(), KNIFE) == 1, "для убийства понадобился не один удар ножом: %d" % count_attacks(Net.local_id(), KNIFE))


# --- Все ---


## То, что должен был увидеть каждый игрок, кем бы он ни был.
func _check_what_everyone_saw() -> bool:
	var traitor_id: int = peer_named(TRAITOR_NAME)
	var shooter_id: int = peer_named(SHOOTER_NAME)
	var victim_id: int = peer_named(VICTIM_NAME)
	var victim: Player = avatar(victim_id)
	var stand: WeaponPickup = map().get_interactables()[0] as WeaponPickup
	if not await expect(func() -> bool: return Game.last_result != null, 5.0, "итоги матча не пришли"):
		return false
	var result: MatchResult = Game.last_result
	if not check(result.winner == Game.Winner.TRAITORS and result.reason == Game.EndReason.CREW_OUTNUMBERED,
			"итог %s / %s" % [Game.Winner.find_key(result.winner), Game.EndReason.find_key(result.reason)]):
		return false
	if not check(victim.life == Player.Life.CORPSE and BodyPart.is_lost(victim.limbs_lost, BodyPart.Part.LEFT_LEG),
			"жертва должна лежать телом без левой ноги"):
		return false
	if not check(victim.limbs_lost == BodyPart.bit(BodyPart.Part.LEFT_LEG), "у жертвы потеряно лишнее: маска %d" % victim.limbs_lost):
		return false
	if not check(not stand.is_available() and not (stand.get_node(^"WeaponSlot") as Node3D).visible,
			"стойка не опустела у всех"):
		return false
	# Что было видно в руках: стрелок взял пистолет и сменил его туда-обратно, предатель достал нож.
	if not check(held_history(shooter_id) == PackedInt32Array([PISTOL, FISTS, PISTOL]),
			"руки стрелка: %s" % var_to_str(held_history(shooter_id))):
		return false
	if not check(held_history(traitor_id) == PackedInt32Array([KNIFE]), "руки предателя: %s" % var_to_str(held_history(traitor_id))):
		return false
	if not check(held_history(victim_id).is_empty(), "руки жертвы: %s" % var_to_str(held_history(victim_id))):
		return false
	if not check(avatar(traitor_id).weapons.get_held_item().title == "Нож", "в руке предателя не виден нож"):
		return false
	if not check(bad_event_count() == 0, "пришли события атаки, не прошедшие проверку: %d" % bad_event_count()):
		return false
	# Атаки дошли до тех, кто их видел: и промахи, и попадания. Предатель всё это время
	# стоял за стеной и не узнал ни о выстрелах стрелка, ни об ударе жертвы.
	var wall_shots: int = count_attacks(shooter_id, PISTOL, AttackEvent.Impact.WORLD)
	var leg_hits: int = count_attacks(shooter_id, PISTOL, AttackEvent.Impact.PLAYER)
	if bot_name == TRAITOR_NAME:
		if not check(count_all_attacks(shooter_id) == 0 and count_all_attacks(victim_id) == 0,
				"предатель за стеной узнал о чужих атаках: стрелка %d, жертвы %d" % [
				count_all_attacks(shooter_id), count_all_attacks(victim_id)]):
			return false
	else:
		if not check(wall_shots >= 1 and leg_hits == LEG_SHOTS_NEEDED and count_all_attacks(shooter_id) == wall_shots + leg_hits,
				"выстрелы стрелка: в стену %d, в игрока %d, всего %d" % [wall_shots, leg_hits, count_all_attacks(shooter_id)]):
			return false
		if not check(count_attacks(victim_id, FISTS, AttackEvent.Impact.NONE) == 1 and count_all_attacks(victim_id) == 1,
				"атаки жертвы: %d" % count_all_attacks(victim_id)):
			return false
	if not check(count_attacks(traitor_id, KNIFE, AttackEvent.Impact.PLAYER) == 1 and count_all_attacks(traitor_id) == 1,
			"атаки предателя: %d" % count_all_attacks(traitor_id)):
		return false
	return check_no_private_leaks()
