extends "res://tests/scenarios/combat_base.gd"
## Сценарий combat_sight: кто узнаёт, что у игрока в руках и что он атаковал.
## Карта arena_combat_sight: длинная стена; все появляются по одну её сторону.
## Bot1 — предатель: уходит за стену, там достаёт нож и бьёт Bot3 по ноге (не насмерть).
## Bot2 — экипаж по другую сторону стены: не видит ни ножа, ни удара; потом обходит стену
##   и только тогда узнаёт про нож (об ударе, который уже был, — нет).
## Bot3 — экипаж за стеной рядом с предателем: видит и нож, и удар.
## Bot4 — убит сервером в начале (combat_sight_director.gd): призраком видит и нож, и удар
##   сквозь стену; потом выходит и заходит зрителем — сервер сразу говорит ему, что у кого
##   в руках.
## Матч заканчивает сервер по знаку Bot2 (combat_finish_director.gd).

const TRAITOR_NAME: String = "Bot1"
const BLIND_NAME: String = "Bot2"
const TARGET_NAME: String = "Bot3"
const GHOST_NAME: String = "Bot4"
const MARK_STOP_DISTANCE: float = 0.4
const MARK_RADIUS: float = 0.8
## Откуда предатель бьёт ножом: на таком расстоянии за целью, пройдя сквозь неё (разгон
## уносит его дальше, а не ближе).
const KNIFE_DISTANCE: float = 0.7
const KNIFE_STOP_DISTANCE: float = 0.2
## С какого расстояния удар сверху вниз попадает точно в ногу: ближе — на пути торс,
## дальше — не хватает длины ножа.
const MIN_LEG_STAB_DISTANCE: float = 0.45
const MAX_LEG_STAB_DISTANCE: float = 1.4
const APPROACH_TRIES: int = 3
## Удар ножом в ногу: 100 * 0.6 из общего здоровья.
const HEALTH_AFTER_STAB: int = 40
## Сколько ждём событие, которое прийти не должно.
const SILENCE_SEC: float = 1.5

## Что бот видел в руках предателя в тот миг, когда пришло событие его атаки.
var _held_at_attack: int = -1


func _run() -> void:
	track_avatars()
	var traitor: Player = avatar_named(TRAITOR_NAME)
	traitor.event_received.connect(func(_kind: Player.Event, _data: Array) -> void:
		_held_at_attack = traitor.held_item)
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	for peer_id: int in Net.players:
		if not check(avatar(peer_id).held_item == FISTS, "на старте у игрока %s не пустые руки" % Net.get_player_name(peer_id)):
			return
	var played: bool = false
	match bot_name:
		TRAITOR_NAME:
			played = await _play_traitor()
		BLIND_NAME:
			played = await _play_blind()
		TARGET_NAME:
			played = await _play_target()
		GHOST_NAME:
			played = await _play_ghost()
	if not played:
		return
	await expect_lobby(90.0)


func _mark(mark_name: String) -> Vector3:
	return (map().get_node("Marks/" + mark_name) as Node3D).global_position


func _is_at(player: Player, mark_name: String) -> bool:
	return player != null and flat_distance(player.position, _mark(mark_name)) <= MARK_RADIUS


# --- Bot1: предатель ---


func _play_traitor() -> bool:
	var target: Player = avatar_named(TARGET_NAME)
	var blind: Player = avatar_named(BLIND_NAME)
	var ghost: Player = avatar_named(GHOST_NAME)
	if not check(await walk_to(_mark("Corner"), MARK_STOP_DISTANCE, 15.0), "предатель не дошёл до угла стены"):
		return false
	if not check(await walk_to(_mark("HideTraitor"), MARK_STOP_DISTANCE, 15.0), "предатель не дошёл до укрытия"):
		return false
	if not await expect(func() -> bool:
		return _is_at(target, "HideTarget") and _is_at(blind, "BlindSpot") and ghost.life == Player.Life.CORPSE,
		40.0, "остальные не заняли места"):
		return false
	await wait_seconds(SETTLE_SEC)
	if not await draw_weapon(SLOT_KNIFE, KNIFE):
		return false
	# Бьём в ногу: цель должна выжить, иначе матч кончится. Встаём по ту сторону цели,
	# пройдя сквозь неё; если разгон унёс слишком далеко или не донёс — заходим ещё раз.
	var is_in_place: bool = false
	for attempt: int in APPROACH_TRIES:
		var side: Vector3 = Vector3.FORWARD if attempt % 2 == 0 else Vector3.BACK
		if not check(await walk_to(target.position + side * KNIFE_DISTANCE, KNIFE_STOP_DISTANCE, 10.0), "предатель не дошёл до цели"):
			return false
		await wait_seconds(SETTLE_SEC)
		var distance: float = flat_distance(me().position, target.position)
		step("до цели %.2f м" % distance)
		if distance >= MIN_LEG_STAB_DISTANCE and distance <= MAX_LEG_STAB_DISTANCE:
			is_in_place = true
			break
	if not check(is_in_place, "предатель не встал на расстояние удара по ноге"):
		return false
	aim_at_part(target, BodyPart.Part.LEFT_LEG)
	await click(&"fire")
	if not await expect(func() -> bool: return count_all_attacks(Net.local_id()) >= 1, REPLY_SEC * 3.0,
			"удар ножом не состоялся"):
		return false
	if not check(count_attacks(Net.local_id(), KNIFE, AttackEvent.Impact.PLAYER) == 1 and count_all_attacks(Net.local_id()) == 1,
			"удар ножом по ноге не попал: атак %d" % count_all_attacks(Net.local_id())):
		return false
	if not await expect(func() -> bool: return BodyPart.is_lost(target.limbs_lost, BodyPart.Part.LEFT_LEG), REPLY_SEC,
			"нож не отнял ногу цели"):
		return false
	if not check(target.life == Player.Life.ALIVE, "цель погибла от удара в ногу"):
		return false
	# Нож остаётся в руке до конца сценария: его должны увидеть зритель и обошедший стену.
	return check(me().held_item == KNIFE, "нож пропал из рук предателя")


# --- Bot3: рядом с предателем ---


func _play_target() -> bool:
	var traitor: Player = avatar_named(TRAITOR_NAME)
	var traitor_id: int = traitor.peer_id
	if not check(await walk_to(_mark("Corner"), MARK_STOP_DISTANCE, 15.0), "цель не дошла до угла стены"):
		return false
	if not check(await walk_to(_mark("HideTarget"), MARK_STOP_DISTANCE, 15.0), "цель не дошла до места"):
		return false
	# На прямой видимости нож в руке виден сразу.
	if not await expect(func() -> bool: return traitor.held_item == KNIFE, 60.0, "сосед за стеной не увидел нож в руке предателя"):
		return false
	if not check(held_history(traitor_id) == PackedInt32Array([KNIFE]), "руки предателя глазами соседа: %s" % var_to_str(held_history(traitor_id))):
		return false
	if not await expect(func() -> bool: return BodyPart.is_lost(me().limbs_lost, BodyPart.Part.LEFT_LEG), 30.0, "цель не получила удар по ноге"):
		return false
	if not await expect(func() -> bool: return count_attacks(traitor_id, KNIFE, AttackEvent.Impact.PLAYER) == 1, REPLY_SEC,
			"цель не получила событие удара"):
		return false
	if not check(_held_at_attack == KNIFE, "событие удара пришло раньше ножа в руке: в руках было %d" % _held_at_attack):
		return false
	if not await expect(func() -> bool: return me().body.health == HEALTH_AFTER_STAB, REPLY_SEC,
			"здоровье цели после удара в ногу: %d" % me().body.health):
		return false
	return check(me().life == Player.Life.ALIVE and bad_event_count() == 0, "цель должна остаться жива")


# --- Bot4: призрак, потом зритель ---


func _play_ghost() -> bool:
	var traitor: Player = avatar_named(TRAITOR_NAME)
	var traitor_id: int = traitor.peer_id
	var old_id: int = Net.local_id()
	if not await expect(func() -> bool: return me().life == Player.Life.CORPSE, 15.0, "сервер не убил Bot4"):
		return false
	# Мёртвый вне игры и видит сквозь стены: и нож, и удар.
	if not await expect(func() -> bool: return traitor.held_item == KNIFE, 90.0, "призрак не увидел нож в руке предателя"):
		return false
	if not check(_is_at(traitor, "HideTraitor") or traitor.position.x > 1.0, "предатель достал нож не за стеной"):
		return false
	if not await expect(func() -> bool: return count_attacks(traitor_id, KNIFE, AttackEvent.Impact.PLAYER) == 1, 30.0,
			"призрак не получил событие удара"):
		return false
	if not check(_held_at_attack == KNIFE and count_all_attacks(traitor_id) == 1, "призрак увидел удар не так: в руках %d, атак %d" % [
			_held_at_attack, count_all_attacks(traitor_id)]):
		return false
	# Выходим и заходим зрителем: новый пир, аватара нет, чужие руки сервер сообщает сразу.
	if not await leave_and_rejoin():
		return false
	if not check(Net.local_id() != old_id and me() == null and not Game.is_participant(Net.local_id()),
			"вернувшийся должен быть зрителем без аватара"):
		return false
	if not await expect(func() -> bool:
		var seen: Player = avatar_named(TRAITOR_NAME)
		return seen != null and seen.held_item == KNIFE, 5.0, "зрителю не сообщили, что у предателя в руках нож"):
		return false
	for other_name: String in [BLIND_NAME, TARGET_NAME]:
		if not check(avatar_named(other_name) != null and avatar_named(other_name).held_item == FISTS,
				"зритель видит не пустые руки у игрока %s" % other_name):
			return false
	return true


# --- Bot2: по другую сторону стены ---


func _play_blind() -> bool:
	var traitor: Player = avatar_named(TRAITOR_NAME)
	var target: Player = avatar_named(TARGET_NAME)
	var traitor_id: int = traitor.peer_id
	var ghost_id: int = peer_named(GHOST_NAME)
	if not check(await walk_to(_mark("BlindSpot"), MARK_STOP_DISTANCE, 15.0), "экипаж не дошёл до своего места"):
		return false
	# Потеря ноги видна всем (это видно в мире) — по ней узнаём, что удар уже был.
	if not await expect(func() -> bool: return BodyPart.is_lost(target.limbs_lost, BodyPart.Part.LEFT_LEG), 90.0,
			"цель за стеной так и не потеряла ногу"):
		return false
	await wait_seconds(SILENCE_SEC)
	if not check(traitor.held_item == FISTS and held_history(traitor_id).is_empty(),
			"экипаж за стеной узнал, что у предателя в руках: %s" % var_to_str(held_history(traitor_id))):
		return false
	if not check(count_all_attacks(traitor_id) == 0 and bad_event_count() == 0,
			"экипаж за стеной получил событие удара: %d" % count_all_attacks(traitor_id)):
		return false
	if not check_no_private_leaks():
		return false
	# Ждём, пока призрак перезайдёт зрителем и проверит своё: потом матч закончится.
	if not await expect(func() -> bool: return Net.players.size() == expected_players and not Net.players.has(ghost_id),
			40.0, "Bot4 не вернулся зрителем"):
		return false
	await wait_seconds(2.0)
	if not check(traitor.held_item == FISTS and count_all_attacks(traitor_id) == 0, "экипаж за стеной узнал лишнее, пока ждал"):
		return false
	# Обходим стену: предатель попадается на глаза — и только теперь виден нож.
	if not check(await walk_to(_mark("Around"), MARK_STOP_DISTANCE, 20.0), "экипаж не дошёл до края стены"):
		return false
	if not check(await walk_to(_mark("Corner"), MARK_STOP_DISTANCE, 15.0), "экипаж не обошёл стену"):
		return false
	if not await expect(func() -> bool: return traitor.held_item == KNIFE, 5.0, "обойдя стену, экипаж не увидел нож"):
		return false
	if not check(held_history(traitor_id) == PackedInt32Array([KNIFE]), "руки предателя глазами обошедшего стену: %s" % var_to_str(held_history(traitor_id))):
		return false
	# Удар, который был раньше, задним числом не приходит.
	if not check(count_all_attacks(traitor_id) == 0, "старое событие удара пришло позже"):
		return false
	signal_finish()
	return true
