extends "res://tests/scenarios/combat_base.gd"
## Сценарий combat_meeting: бой вокруг собрания. Карта arena_combat_meeting: тревожная
## кнопка стоит на столе, места собрания — в двух с половиной метрах друг от друга.
## Все: в начале игры атаки заперты (GameConfig.attack_lock_seconds, настоящее значение);
##   клиент-владелец знает, сколько осталось; после запрета атака проходит.
## Bot1 — предатель: достаёт нож и держит его в руке к началу собрания. После собрания
##   сразу достаёт нож снова и бьёт — удар не проходит, пока идёт запрет, а потом проходит.
## Bot2 — экипаж с грузом: бьёт кулаком после запрета, получает от сервера канистру
##   (combat_meeting_director.gd) и несёт её к началу собрания.
## Bot3 — экипаж без ног (ноги отнимает сервер): ползёт к столу и нажимает кнопку, которую
##   стол закрывает от его глаз у пола, — дотягивается.
## Собрание: у всех живых руки пустеют на глазах у остальных; все пропускают голосование.
## Матч заканчивает сервер по знаку предателя (combat_finish_director.gd).

const TRAITOR_NAME: String = "Bot1"
const CARRIER_NAME: String = "Bot2"
const CRAWLER_NAME: String = "Bot3"
const BOTH_LEGS: int = (1 << BodyPart.Part.LEFT_LEG) | (1 << BodyPart.Part.RIGHT_LEG)
## Ползущий останавливается на таком расстоянии от кнопки (край стола — в 0.8 м от неё).
const BUTTON_STOP_DISTANCE: float = 2.0
const PRESS_ATTEMPTS: int = 5
const PRESS_ATTEMPT_SEC: float = 2.5
## Бот жмёт атаку «под запретом», только пока по его часам запрета осталось больше этого:
## его часы отстают от серверных на задержку сети, и запас её покрывает.
const LOCK_SAFE_LEFT_SEC: float = 2.0
## Сколько ждём событие, которого быть не должно.
const SILENCE_SEC: float = 0.8
const SIGHT_MASK: int = 1


func _run() -> void:
	track_avatars()
	if not await expect(func() -> bool: return Game.local_role != Game.Role.NONE, 3.0, "сервер не прислал роль"):
		return
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	if not await _check_attack_lock("в начале игры", FISTS):
		return
	var is_ready: bool = false
	match bot_name:
		TRAITOR_NAME:
			is_ready = await _prepare_traitor()
		CARRIER_NAME:
			is_ready = await _prepare_carrier()
		CRAWLER_NAME:
			is_ready = await _call_meeting_crawling()
	if not is_ready:
		return
	if not await _sit_through_meeting():
		return
	if not await _play_after_meeting():
		return
	await expect_lobby(40.0)


## Все: пока идёт запрет, атака не проходит; хозяин аватара знает, сколько осталось.
## Вызывается сразу после начала игры или её продолжения. item_index — что должно быть в руках.
func _check_attack_lock(what: String, item_index: int) -> bool:
	var weapons: PlayerWeapons = me().weapons
	var lock_seconds: float = Game.config.attack_lock_seconds
	if not await expect(func() -> bool: return weapons.get_attack_lock_left() > 0.0, REPLY_SEC,
			"%s: хозяин не узнал о запрете атак" % what):
		return false
	if not check(weapons.get_attack_lock_left() <= lock_seconds, "%s: запрет длиннее настройки: %.2f" % [what, weapons.get_attack_lock_left()]):
		return false
	if not check(me().held_item == item_index, "%s: в руках %d" % [what, me().held_item]):
		return false
	var before: int = count_all_attacks(Net.local_id())
	look_at_point(me().get_eye_position() + Vector3.BACK * 10.0)
	if weapons.get_attack_lock_left() > LOCK_SAFE_LEFT_SEC:
		await click(&"fire")
		await click(&"fire")
		step("%s: атака под запретом отправлена, по часам бота осталось %.2f с" % [what, weapons.get_attack_lock_left()])
	else:
		step("%s: бот не успел ударить под запретом, сроки проверит сервер" % what)
	var left_before: float = weapons.get_attack_lock_left()
	await wait_seconds(SILENCE_SEC)
	if not check(count_all_attacks(Net.local_id()) == before, "%s: атака прошла во время запрета" % what):
		return false
	if not check(weapons.get_attack_lock_left() < left_before, "%s: запрет на клиенте не убывает" % what):
		return false
	if not await expect(func() -> bool: return weapons.get_attack_lock_left() <= 0.0, lock_seconds + REPLY_SEC,
			"%s: запрет на клиенте не кончился" % what):
		return false
	return check(count_all_attacks(Net.local_id()) == before, "%s: атака прошла во время запрета" % what)


# --- До собрания ---


## Bot2: удар кулаком после запрета проходит; сервер в ответ даёт груз.
func _prepare_carrier() -> bool:
	if not check(await attack_until_seen(), "после запрета удар кулаком не прошёл"):
		return false
	return await expect(func() -> bool: return me().held_item == CANISTER, 10.0, "бот не получил груз")


## Bot1: достаёт нож, когда запрет уже кончился (Bot2 ударил), и держит его в руке.
func _prepare_traitor() -> bool:
	var carrier_id: int = peer_named(CARRIER_NAME)
	if not await expect(func() -> bool: return count_all_attacks(carrier_id) >= 1, 30.0, "предатель не увидел удар Bot2"):
		return false
	return await draw_weapon(SLOT_KNIFE, KNIFE)


## Bot3: без ног доползает до стола и нажимает кнопку, которую стол закрывает от глаз у пола.
func _call_meeting_crawling() -> bool:
	var button: EmergencyButton = map().get_interactables()[0] as EmergencyButton
	var traitor: Player = avatar_named(TRAITOR_NAME)
	var carrier: Player = avatar_named(CARRIER_NAME)
	if not check(button != null, "на карте нет тревожной кнопки"):
		return false
	if not await expect(func() -> bool: return me().limbs_lost & BOTH_LEGS == BOTH_LEGS, 40.0, "сервер не отнял у бота ноги"):
		return false
	if not check(me().body.is_crawling() and me().life == Player.Life.ALIVE, "без ног бот должен ползти живым"):
		return false
	# Собрание созываем, когда у остальных руки заняты: нож и груз.
	if not await expect(func() -> bool: return traitor.held_item == KNIFE and carrier.held_item == CANISTER, 40.0,
			"ползущий не увидел нож и груз в руках остальных: %d и %d" % [traitor.held_item, carrier.held_item]):
		return false
	if not check(await walk_to(button.global_position, BUTTON_STOP_DISTANCE, 20.0), "ползущий не дополз до стола"):
		return false
	await wait_seconds(SETTLE_SEC)
	look_at_point(button.get_focus_position())
	# Условие теста: от глаз у пола кнопку закрывает стол.
	await get_tree().physics_frame
	var eye: Vector3 = me().get_eye_position()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, button.get_focus_position(), SIGHT_MASK)
	var hit: Dictionary = me().get_world_3d().direct_space_state.intersect_ray(query)
	if not check(not hit.is_empty() and eye.y < 0.6, "стол не закрывает кнопку от ползущего: тест ничего не проверяет"):
		return false
	if not await expect(func() -> bool: return Game.meeting.can_press_button(Net.local_id()), 10.0, "кнопка не стала доступной"):
		return false
	if not await expect(func() -> bool: return me().interactor.focus == button, 3.0,
			"ползущему не показана подсказка кнопки: стол закрыл её от глаз у пола"):
		return false
	for attempt: int in PRESS_ATTEMPTS:
		look_at_point(button.get_focus_position())
		press(&"interact")
		var is_called: bool = await wait_until(Game.meeting.is_active, PRESS_ATTEMPT_SEC)
		release(&"interact")
		if is_called:
			return check(Game.meeting.caller_id == Net.local_id(), "собрание созвал не ползущий")
		await wait_seconds(0.2)
	return check(false, "сервер не дал ползущему нажать кнопку за %d попыток" % PRESS_ATTEMPTS)


# --- Собрание ---


## Все: на собрании у каждого живого пустые руки — и это видят остальные.
func _sit_through_meeting() -> bool:
	var meeting: Meeting = Game.meeting
	if not await expect(meeting.is_active, 90.0, "собрание не началось"):
		return false
	for player_name: String in [TRAITOR_NAME, CARRIER_NAME, CRAWLER_NAME]:
		var player: Player = avatar_named(player_name)
		if not await expect(func() -> bool: return player.held_item == FISTS, REPLY_SEC,
				"на собрании у игрока %s в руках предмет %d" % [player_name, player.held_item]):
			return false
	if not check(not me().weapons.is_carrying(ITEMS.get_item(CANISTER)), "груз остался в руках на собрании"):
		return false
	# Оружие на собрании не достать и не пустить в ход.
	await tap_slot(SLOT_KNIFE)
	await click(&"fire")
	if not await expect(func() -> bool: return meeting.stage == Meeting.Stage.VOTING and meeting.can_local_vote(), 10.0,
			"голосование не началось"):
		return false
	if not check(me().held_item == FISTS, "на собрании бот достал оружие: %d" % me().held_item):
		return false
	meeting.request_vote(MatchRules.SKIP_VOTE)
	if not await expect(func() -> bool: return not meeting.is_active() and Game.is_playing(), 40.0,
			"после собрания игра не продолжилась"):
		return false
	for player_name: String in [TRAITOR_NAME, CARRIER_NAME, CRAWLER_NAME]:
		var player: Player = avatar_named(player_name)
		if not check(player.life == Player.Life.ALIVE and player.held_item == FISTS,
				"после собрания игрок %s не жив или держит предмет %d" % [player_name, player.held_item]):
			return false
	return true


# --- После собрания ---


func _play_after_meeting() -> bool:
	var traitor_id: int = peer_named(TRAITOR_NAME)
	if bot_name != TRAITOR_NAME:
		# Нож достают заново у всех на глазах, удар проходит только после запрета.
		var seen_before: int = count_all_attacks(traitor_id)
		var traitor: Player = avatar(traitor_id)
		if not await expect(func() -> bool: return is_instance_valid(traitor) and traitor.held_item == KNIFE, 20.0,
				"после собрания нож в руке предателя не виден"):
			return false
		if not await expect(func() -> bool: return count_attacks(traitor_id, KNIFE) == 1, 30.0, "удар ножом после запрета не виден"):
			return false
		return check(count_all_attacks(traitor_id) == seen_before + 1 and bad_event_count() == 0, "лишние атаки предателя")
	# Bot1: нож достаём сразу, как игра продолжилась, — до конца запрета ещё далеко.
	if not await expect(func() -> bool: return me().weapons.get_attack_lock_left() > 0.0, REPLY_SEC,
			"после собрания хозяин не узнал о запрете атак"):
		return false
	if not await draw_weapon(SLOT_KNIFE, KNIFE):
		return false
	if not await _check_attack_lock("после собрания", KNIFE):
		return false
	if not check(await attack_until_seen(), "после запрета удар ножом не прошёл"):
		return false
	if not check(count_attacks(Net.local_id(), KNIFE) == 1, "ударов ножом после собрания: %d" % count_attacks(Net.local_id(), KNIFE)):
		return false
	for player_name: String in [CARRIER_NAME, CRAWLER_NAME]:
		if not check(avatar_named(player_name).life == Player.Life.ALIVE, "удар в пустоту задел игрока %s" % player_name):
			return false
	signal_finish()
	return true
