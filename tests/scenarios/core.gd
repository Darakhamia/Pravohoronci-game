extends ScenarioBot
## Сценарий core: проверяет ядро матча без оружия и модулей заданий/собраний.
## Bot1 — предатель (флаг сервера), Bot2 — жертва серверного помощника (core_director.gd),
## Bot3 пользуется предметом карты. Каждый бот проверяет то, что должен видеть именно он.

const VICTIM_NAME: String = "Bot2"
const TRAITOR_NAME: String = "Bot1"
const WALK_SEC: float = 1.0
const SETTLE_SEC: float = 0.4
const MIN_WALK_DISTANCE: float = 3.0
## Без одной ноги игрок должен идти примерно вдвое медленнее.
const MIN_LIMP_RATIO: float = 0.3
const MAX_LIMP_RATIO: float = 0.7
const MAX_FROZEN_MOVE: float = 0.1
const SWITCH_STOP_DISTANCE: float = 1.5
const SEAT_TOLERANCE: float = 0.6
const YAW_TOLERANCE: float = 0.2
## 40 урона по ноге: нога потеряна, из общего здоровья уходит 40 * 0.6.
const HEALTH_AFTER_LIMB: int = 76

var _max_hold_fraction: float = 0.0


func _run() -> void:
	if not await _check_roles():
		return
	if bot_number == 2 and not await _check_frozen_during_reveal():
		return
	if not await expect(Game.is_playing, 5.0, "игра не началась после показа ролей"):
		return
	match bot_number:
		2:
			if not await _play_victim():
				return
		3:
			if not await _use_switch():
				return
	if not await _check_shared_state():
		return
	if not await _check_seating():
		return
	if not await _check_death_and_result():
		return
	await expect(func() -> bool: return Game.state == Game.State.LOBBY and world.current_map == null,
			8.0, "после итогов сервер не вернул игроков в лобби")


func _check_roles() -> bool:
	if not await expect(func() -> bool: return Game.local_role != Game.Role.NONE, 3.0, "сервер не прислал роль"):
		return false
	var expected: Game.Role = Game.Role.TRAITOR if bot_name == TRAITOR_NAME else Game.Role.CREW
	if not check(Game.local_role == expected, "роль %s, а ожидалась %s" % [
			Game.Role.find_key(Game.local_role), Game.Role.find_key(expected)]):
		return false
	if not check(Game.get_fellow_traitors().is_empty(), "у единственного предателя не должно быть напарников"):
		return false
	for peer_id: int in Net.players:
		if peer_id != Net.local_id() and not check(Game.get_role(peer_id) == Game.Role.NONE,
				"до конца матча известна чужая роль игрока %s" % Net.get_player_name(peer_id)):
			return false
	return check(Game.participants.size() == expected_players, "участников %d" % Game.participants.size())


func _check_frozen_during_reveal() -> bool:
	if Game.phase != Game.Phase.ROLE_REVEAL:
		return check(false, "показ ролей уже закончился: проверить заморозку не успели")
	var start: Vector3 = me().position
	await hold(&"move_forward", 0.6)
	if Game.phase != Game.Phase.ROLE_REVEAL:
		return check(false, "показ ролей закончился раньше, чем бот отпустил клавишу")
	return check(me().position.distance_to(start) <= MAX_FROZEN_MOVE,
			"во время показа ролей аватар сдвинулся на %.2f м" % me().position.distance_to(start))


## Bot2: идёт, теряет ногу, идёт снова — уже хромая.
func _play_victim() -> bool:
	var full_distance: float = await _walk_and_measure()
	if not check(full_distance >= MIN_WALK_DISTANCE, "за %.1f с бот прошёл только %.2f м" % [WALK_SEC, full_distance]):
		return false
	if not await expect(func() -> bool: return BodyPart.is_lost(me().limbs_lost, BodyPart.Part.LEFT_LEG),
			6.0, "сервер не сообщил о потере ноги"):
		return false
	if not await expect(func() -> bool: return me().body.health == HEALTH_AFTER_LIMB, 2.0,
			"хозяин не получил своё здоровье: %d" % me().body.health):
		return false
	if not check(me().body.part_health[BodyPart.Part.LEFT_LEG] == 0, "здоровье потерянной ноги не ноль"):
		return false
	var limp_distance: float = await _walk_and_measure()
	var ratio: float = limp_distance / full_distance
	return check(ratio >= MIN_LIMP_RATIO and ratio <= MAX_LIMP_RATIO,
			"без ноги бот прошёл %.2f м против %.2f м с ногами" % [limp_distance, full_distance])


func _walk_and_measure() -> float:
	var start: Vector3 = me().position
	# Вдоль ряда точек спавна, чтобы не уйти к предмету и местам собрания.
	look_at_point(me().get_eye_position() + Vector3.LEFT)
	await hold(&"move_forward", WALK_SEC)
	await wait_seconds(SETTLE_SEC)
	return me().position.distance_to(start)


## Bot3: подходит к переключателю и удерживает E.
func _use_switch() -> bool:
	var switch: Interactable = map().get_interactables()[0]
	me().interactor.hold_changed.connect(func(fraction: float) -> void:
		_max_hold_fraction = maxf(_max_hold_fraction, fraction))
	if not check(await walk_to(switch.global_position, SWITCH_STOP_DISTANCE, 6.0), "бот не дошёл до переключателя"):
		return false
	look_at_point(switch.get_focus_position())
	if not await expect(func() -> bool: return me().interactor.focus == switch, 1.0, "переключатель не попал под прицел"):
		return false
	press(&"interact")
	var switched: bool = await expect(func() -> bool: return switch.state == 1, 2.0,
			"переключатель не сработал после удержания")
	release(&"interact")
	return switched and check(_max_hold_fraction > 0.5, "полоска удержания дошла только до %.2f" % _max_hold_fraction)


## Все: состояние предмета и потерянная нога видны каждому, а чужое здоровье — нет.
func _check_shared_state() -> bool:
	var switch: Interactable = map().get_interactables()[0]
	if not await expect(func() -> bool: return switch.state == 1, 8.0, "состояние переключателя не дошло"):
		return false
	var victim: Player = avatar_named(VICTIM_NAME)
	if not await expect(func() -> bool: return BodyPart.is_lost(victim.limbs_lost, BodyPart.Part.LEFT_LEG),
			6.0, "потерянная нога игрока %s не видна" % VICTIM_NAME):
		return false
	if bot_name != VICTIM_NAME:
		return check(victim.body.health == PlayerBody.CONFIG.max_health, "чужое здоровье пришло не хозяину")
	return true


## Все: по сигналу собрания сервер рассаживает живых по местам и поворачивает их.
func _check_seating() -> bool:
	if not await expect(func() -> bool: return _find_own_seat() != null, 10.0,
			"сервер не посадил бота на место собрания"):
		return false
	# Лямбда захватывает локальные переменные по значению: место ищем заново.
	var seat: Marker3D = _find_own_seat()
	return await expect(func() -> bool:
		return absf(angle_difference(me().input.yaw, seat.global_rotation.y)) <= YAW_TOLERANCE,
		2.0, "сервер не повернул бота лицом к столу")


## Место собрания, на котором стоит бот; null — он не на месте.
func _find_own_seat() -> Marker3D:
	for candidate: Node in map().get_node(^"MeetingSeats").get_children():
		var marker: Marker3D = candidate as Marker3D
		if marker != null and me().position.distance_to(marker.global_position) <= SEAT_TOLERANCE:
			return marker
	return null


## Все: жертва становится телом, матч заканчивается победой предателя, роли открываются.
func _check_death_and_result() -> bool:
	var victim: Player = avatar_named(VICTIM_NAME)
	if not await expect(func() -> bool: return victim.life == Player.Life.CORPSE, 8.0, "жертва не стала телом"):
		return false
	if bot_name == VICTIM_NAME and not await expect(
			func() -> bool: return get_viewport().get_camera_3d() is GhostCamera,
			2.0, "мёртвый игрок не получил камеру призрака"):
		return false
	if not await expect(func() -> bool: return Game.last_result != null, 3.0, "итоги матча не пришли"):
		return false
	var result: MatchResult = Game.last_result
	if not check(result.winner == Game.Winner.TRAITORS and result.reason == Game.EndReason.CREW_OUTNUMBERED,
			"итог %s / %s" % [Game.Winner.find_key(result.winner), Game.EndReason.find_key(result.reason)]):
		return false
	if not check(result.entries.size() == expected_players, "в итогах %d строк" % result.entries.size()):
		return false
	if not check(Game.get_role(peer_named(TRAITOR_NAME)) == Game.Role.TRAITOR, "после итогов роль предателя не открыта"):
		return false
	if not check(result.did_win(Net.local_id()) == (bot_name == TRAITOR_NAME), "победа посчитана не тому"):
		return false
	var victim_entry: MatchResult.Entry = result.get_entry(peer_named(VICTIM_NAME))
	return check(victim_entry != null and not victim_entry.alive and Game.phase == Game.Phase.ENDED,
			"в итогах жертва жива или фаза не ENDED")
