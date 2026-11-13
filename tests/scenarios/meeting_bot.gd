class_name MeetingBot
extends ScenarioBot
## Общая часть ботов сценариев собрания (meeting, meeting_button, meeting_leave): считает
## сигналы Game.meeting, запоминает, что было видно в момент каждого сигнала, и умеет
## нажимать предметы карты. Сам сценарием не является (файла .cfg у него нет).

const SEAT_TOLERANCE: float = 0.6
const YAW_TOLERANCE: float = 0.2
const MAX_FROZEN_MOVE: float = 0.1
## Запас к времени удержания предмета: сервер начинает отсчёт позже клиента.
const HOLD_MARGIN_SEC: float = 0.6
## Взгляд круто вверх — условный знак другим ботам и серверному помощнику: «я закончил».
const SIGNAL_PITCH: float = 1.3
const SIGNAL_PITCH_THRESHOLD: float = 1.0
## Сколько ждать, что запрос, который сервер должен отклонить, всё-таки сработает.
const REJECT_WAIT_SEC: float = 0.6
const PRESS_ATTEMPTS: int = 5
const PRESS_ATTEMPT_SEC: float = 2.5

## Имя бота -> peer_id на старте матча (у вышедшего игрока имя уже не спросить).
var ids: Dictionary[String, int] = {}
var started_count: int = 0
var closed_count: int = 0
var verdict_count: int = 0
## Сколько раз пришёл vote_cast про каждого игрока (за все собрания).
var vote_cast_counts: Dictionary[int, int] = {}
## Кто выбывал посреди собраний, по порядку.
var dropped_seen: Array[int] = []
## Стадии текущего собрания по порядку сигналов stage_changed.
var stages_seen: Array[Meeting.Stage] = []
## Стадия в момент последнего сигнала started.
var stage_at_started: Meeting.Stage = Meeting.Stage.NONE
## Сколько игроков числились проголосовавшими, когда началось голосование.
var voted_at_voting_start: int = -1
## Был ли хоть один vote_cast не в стадии VOTING или с уже раскрытыми голосами.
var is_vote_leak_seen: bool = false
## Был ли хоть один verdict_ready не в стадии VERDICT.
var is_verdict_out_of_stage: bool = false


func _init() -> void:
	var meeting: Meeting = Game.meeting
	meeting.started.connect(_on_meeting_started)
	meeting.stage_changed.connect(_on_meeting_stage_changed)
	meeting.vote_cast.connect(_on_meeting_vote_cast)
	meeting.verdict_ready.connect(_on_meeting_verdict_ready)
	meeting.closed.connect(_on_meeting_closed)
	meeting.attendee_dropped.connect(_on_meeting_attendee_dropped)


# --- Крючки для сценариев: вызываются прямо из сигналов собрания ---


func _meeting_started() -> void:
	pass


func _meeting_verdict_ready() -> void:
	pass


# --- Что умеет бот собрания ---


## Запомнить id всех игроков по именам. Вызывать в начале _run().
func remember_ids() -> void:
	for peer_id: int in Net.players:
		ids[Net.players[peer_id]] = peer_id


## id игрока, каким он был на старте матча.
func id_of(player_name: String) -> int:
	return ids[player_name] if ids.has(player_name) else 0


## Все игроки на старте матча в порядке лобби.
func all_ids() -> PackedInt32Array:
	return PackedInt32Array(ids.values())


func button() -> EmergencyButton:
	for interactable: Interactable in map().get_interactables():
		if interactable is EmergencyButton:
			return interactable as EmergencyButton
	return null


## Место собрания, на котором стоит бот; null — он не на месте.
func find_own_seat() -> Marker3D:
	if me() == null:
		return null
	for candidate: Node in map().get_node(^"MeetingSeats").get_children():
		var marker: Marker3D = candidate as Marker3D
		if marker != null and me().position.distance_to(marker.global_position) <= SEAT_TOLERANCE:
			return marker
	return null


## Живого бота сервер посадил на место собрания и повернул к столу.
func expect_seated() -> bool:
	if not await expect(func() -> bool: return find_own_seat() != null, 10.0,
			"сервер не посадил бота на место собрания"):
		return false
	# Лямбда захватывает локальные переменные по значению: место ищем заново.
	var seat: Marker3D = find_own_seat()
	return await expect(func() -> bool:
		return absf(angle_difference(me().input.yaw, seat.global_rotation.y)) <= YAW_TOLERANCE,
		3.0, "сервер не повернул бота лицом к столу")


## Во время собрания аватар не двигается, даже если жать «вперёд».
func check_frozen() -> bool:
	var start: Vector3 = me().position
	await hold(&"move_forward", 0.5)
	if not check(Game.phase == Game.Phase.MEETING, "собрание кончилось раньше, чем бот отпустил клавишу"):
		return false
	# По горизонтали: место собрания чуть выше пола, и аватар ещё может на него опускаться.
	var offset: Vector3 = me().position - start
	var moved: float = Vector2(offset.x, offset.z).length()
	return check(moved <= MAX_FROZEN_MOVE, "во время собрания аватар сдвинулся на %.2f м" % moved)


## Навести взгляд на предмет и дождаться, что он попал под прицел (то есть есть подсказка).
func focus_on(target: Interactable, what: String) -> bool:
	look_at_point(target.get_focus_position())
	return await expect(func() -> bool:
		look_at_point(target.get_focus_position())
		return me().interactor.focus == target, 3.0, "%s: предмет не попал под прицел" % what)


## Честно нажимать предмет клавишей E, пока не выполнится условие. Несколько попыток:
## первая могла прийти на сервер чуть раньше, чем он разрешил нажатие.
func press_until(target: Interactable, condition: Callable, what: String) -> bool:
	for attempt: int in PRESS_ATTEMPTS:
		if not await focus_on(target, what):
			return false
		press(&"interact")
		var is_done: bool = await wait_until(condition, PRESS_ATTEMPT_SEC)
		release(&"interact")
		if is_done:
			return true
		await wait_seconds(0.2)
	return check(false, "%s: не сработало за %d попыток" % [what, PRESS_ATTEMPTS])


## Запрос нажатия мимо подсказки, как от изменённого клиента: клавиша «зажата» дольше,
## чем нужно предмету. Сервер должен сам решить, что нажимать нельзя.
func force_press(target: Interactable) -> void:
	me().interactor.press_requested.emit(target.interact_id, true)
	await wait_seconds(target.hold_seconds + HOLD_MARGIN_SEC)
	me().interactor.press_requested.emit(target.interact_id, false)
	await wait_seconds(REJECT_WAIT_SEC)


## Подсказки на предмете нет, сколько на него ни смотри.
func check_no_prompt(target: Interactable, what: String) -> bool:
	look_at_point(target.get_focus_position())
	await wait_seconds(0.4)
	return check(me().interactor.focus != target, "%s: подсказка есть, а быть не должна" % what)


## Выйти с сервера и зайти снова под тем же именем — уже зрителем идущего матча, с новым
## peer_id. База считает обрыв сессии провалом, поэтому на время выхода говорим ей, что
## бот уходит сам (_is_leaving — поле ScenarioBot).
func rejoin() -> bool:
	_release_all()
	_is_leaving = true
	Net.leave()
	# Сервер должен успеть заметить выход, иначе имя ещё занято.
	await wait_seconds(0.5)
	var port: int = CmdArgs.get_int("--port", Net.DEFAULT_PORT, CmdArgs.MIN_PORT, CmdArgs.MAX_PORT)
	var error: Error = Net.join_server(SERVER_ADDRESS, port, bot_name)
	if not check(error == OK, "повторный вход: Net.join_server вернул %s" % error_string(error)):
		return false
	if not await expect(Net.is_joined, CONNECT_DEADLINE_SEC, "сервер не пустил обратно"):
		return false
	_is_leaving = false
	step("вернулся зрителем")
	return true


## Посмотреть круто вверх и подержать взгляд: знак остальным, что бот закончил свою часть.
func send_look_signal() -> void:
	me().input.pitch = SIGNAL_PITCH
	await wait_seconds(0.6)


## Подал ли этот игрок знак взглядом (виден всем: наклон взгляда реплицируется).
func has_look_signal(player_name: String) -> bool:
	var player: Player = avatar(id_of(player_name))
	return player != null and player.sync_pitch > SIGNAL_PITCH_THRESHOLD


func vote_cast_count(player_name: String) -> int:
	var peer_id: int = id_of(player_name)
	return vote_cast_counts[peer_id] if vote_cast_counts.has(peer_id) else 0


## Заголовок идущего собрания у этого бота такой, как ожидалось.
func check_meeting_header(reason: Meeting.Reason, caller_name: String, victim_name: String,
		attendee_ids: PackedInt32Array) -> bool:
	var meeting: Meeting = Game.meeting
	if not check(meeting.is_active() and Game.phase == Game.Phase.MEETING,
			"собрание не идёт или фаза не MEETING: стадия %s, фаза %s" % [
			Meeting.Stage.find_key(meeting.stage), Game.Phase.find_key(Game.phase)]):
		return false
	if not check(meeting.reason == reason, "причина собрания %s" % Meeting.Reason.find_key(meeting.reason)):
		return false
	if not check(meeting.caller_id == id_of(caller_name), "собрание созвал %d, а не %s" % [meeting.caller_id, caller_name]):
		return false
	var victim_id: int = id_of(victim_name) if not victim_name.is_empty() else 0
	if not check(meeting.victim_id == victim_id, "жертва %d, а ожидалась %d" % [meeting.victim_id, victim_id]):
		return false
	return check(meeting.attendees == attendee_ids, "участники собрания %s, а ожидались %s" % [meeting.attendees, attendee_ids])


## Вердикт у этого бота такой, как ожидалось: голоса, кто голосовал, кого изгнали и кем он был.
func check_verdict(expected_votes: Dictionary[int, int], expected_voted: PackedInt32Array,
		ejected_name: String, ejected_role: Game.Role) -> bool:
	var meeting: Meeting = Game.meeting
	# Поля вердикта остаются и после закрытия собрания: стадию сверяем по моменту сигнала.
	if not check(not is_verdict_out_of_stage, "verdict_ready пришёл не в стадии VERDICT"):
		return false
	if not check(meeting.votes == expected_votes, "голоса %s, а ожидались %s" % [meeting.votes, expected_votes]):
		return false
	var voted_ids: PackedInt32Array = PackedInt32Array(meeting.voted.keys())
	voted_ids.sort()
	var expected_ids: PackedInt32Array = expected_voted.duplicate()
	expected_ids.sort()
	if not check(voted_ids == expected_ids, "проголосовали %s, а ожидались %s" % [voted_ids, expected_ids]):
		return false
	var ejected_id: int = id_of(ejected_name) if not ejected_name.is_empty() else MatchRules.SKIP_VOTE
	if not check(meeting.ejected_id == ejected_id, "изгнан %d, а ожидался %d" % [meeting.ejected_id, ejected_id]):
		return false
	if not check(meeting.ejected_role == ejected_role, "роль изгнанного %s" % Game.Role.find_key(meeting.ejected_role)):
		return false
	return check(not is_vote_leak_seen, "голос пришёл вне голосования или голоса раскрылись до вердикта")


## После конца матча от собрания и кнопки ничего не осталось.
func check_meeting_reset() -> bool:
	var meeting: Meeting = Game.meeting
	if not check(not meeting.is_active() and meeting.attendees.is_empty() and meeting.voted.is_empty()
			and meeting.votes.is_empty() and meeting.dropped.is_empty() and meeting.caller_id == 0
			and meeting.local_vote == Meeting.NO_VOTE and meeting.ejected_id == MatchRules.SKIP_VOTE,
			"после матча осталось состояние собрания"):
		return false
	return check(meeting.button_uses_left == 0 and meeting.button_cooldown_left <= 0.0
			and not meeting.can_press_button(Net.local_id()), "после матча осталось состояние тревожной кнопки")


# --- Сигналы собрания ---


func _on_meeting_started() -> void:
	started_count += 1
	stages_seen.clear()
	stage_at_started = Game.meeting.stage
	voted_at_voting_start = -1
	step("собрание %d началось" % started_count)
	_meeting_started()


func _on_meeting_stage_changed(new_stage: Meeting.Stage) -> void:
	stages_seen.append(new_stage)
	if new_stage == Meeting.Stage.VOTING:
		voted_at_voting_start = Game.meeting.voted.size()


func _on_meeting_vote_cast(voter_id: int) -> void:
	vote_cast_counts[voter_id] = (vote_cast_counts[voter_id] if vote_cast_counts.has(voter_id) else 0) + 1
	if Game.meeting.stage != Meeting.Stage.VOTING or not Game.meeting.votes.is_empty():
		is_vote_leak_seen = true


func _on_meeting_verdict_ready() -> void:
	verdict_count += 1
	if Game.meeting.stage != Meeting.Stage.VERDICT:
		is_verdict_out_of_stage = true
	_meeting_verdict_ready()


func _on_meeting_closed() -> void:
	closed_count += 1
	step("собрание закрыто (%d)" % closed_count)


func _on_meeting_attendee_dropped(peer_id: int) -> void:
	dropped_seen.append(peer_id)
