class_name Meeting
extends Node
## Собрание и голосование (узел Game.meeting, есть на каждом пире).
## Сервер ведёт стадии и считает голоса; клиенты получают копию и показывают экран.
## О сценах Meeting не знает: карта слушает started/ejected/closed и сама рассаживает
## игроков, убирает тела и выбрасывает изгнанного.
##
## Ход собрания: server_call() -> DISCUSSION (если она не нулевая) -> VOTING (кончается
## раньше, когда проголосовали все, кого ещё стоит ждать) -> VERDICT -> закрытие.
## Пока идёт голосование, все знают, КТО проголосовал, но не за кого: голоса сервер держит
## у себя и раскрывает разом в вердикте. Проголосовавший узнаёт только свой голос.
## Мёртвые и зрители видят собрание, но не голосуют. Вошедший посреди собрания получает
## его текущее состояние. Если матч кончился или прерван, собрание молча закрывается.
##
## После closed поля прошедшего собрания (кто созвал, голоса, кого изгнали) остаются
## доступными до следующего собрания или конца матча.
##
## Тревожная кнопка: у каждого участника ограниченное число нажатий за матч и общая для
## всех пауза — с начала игры и после каждого собрания. Сколько нажатий осталось, сервер
## сообщает только самому игроку.

## Стадии собрания. NONE — собрания нет.
enum Stage { NONE, DISCUSSION, VOTING, VERDICT }
## Почему созвали собрание.
enum Reason { BUTTON, BODY }

## Все пиры: собрание началось (поля caller_id, reason, victim_id, attendees уже заполнены).
signal started
## Все пиры: сменилась стадия; сколько она продлится — в stage_seconds_left.
signal stage_changed(new_stage: Stage)
## Все пиры: участник проголосовал (за кого — до вердикта тайна).
signal vote_cast(voter_id: int)
## Все пиры: вердикт (поля votes, ejected_id, ejected_role заполнены).
signal verdict_ready
## Все пиры: собрание закончилось.
signal closed
## Сервер: этого участника изгнали — карта убирает его аватар.
signal ejected(peer_id: int)
## Все пиры: участник собрания выбыл посреди него (вышел из игры). Он уже в dropped:
## его голос и голоса за него пропали, голосовать за него больше нельзя.
signal attendee_dropped(peer_id: int)
## Клиент: изменились button_uses_left или button_cooldown_left (пришли с сервера либо
## пауза дотикала до нуля). can_press_button() зависит ещё от фазы матча и саботажа:
## за ними следи по Game.phase_changed и сигналам Game.sabotage.
signal button_changed

## Значение local_vote, пока свой голос не отдан.
const NO_VOTE: int = -1
## Клиент: больше нажатий кнопки, чем это число, сервер прислать не может.
const MAX_BUTTON_USES: int = 99

var stage: Stage = Stage.NONE
## Сколько секунд осталось до конца стадии. Идёт на всех пирах.
var stage_seconds_left: float = 0.0
## Кто созвал собрание.
var caller_id: int = 0
var reason: Reason = Reason.BUTTON
## Чьё тело нашли (для Reason.BODY), иначе 0.
var victim_id: int = 0
## Кто был жив в начале собрания: только они голосуют и только за них можно голосовать.
var attendees: PackedInt32Array = []
## Кто уже проголосовал. Тот, чей голос пропал вместе с выбывшим кандидатом, остаётся
## здесь (второго голоса у него нет), но в votes его не будет.
var voted: Dictionary[int, bool] = {}
## После вердикта: кто за кого голосовал (MatchRules.SKIP_VOTE — пропуск). До вердикта
## пусто на всех пирах, сервер тоже держит голоса отдельно.
var votes: Dictionary[int, int] = {}
## После вердикта: кого изгнали (MatchRules.SKIP_VOTE — никого) и кем он был
## (Game.Role.NONE, если роль изгнанного не показываем).
var ejected_id: int = MatchRules.SKIP_VOTE
var ejected_role: Game.Role = Game.Role.NONE
## Все пиры: кто из attendees выбыл уже во время собрания. Такой участник не голосует,
## и голосовать за него нельзя.
var dropped: Dictionary[int, bool] = {}
## Клиент: за кого проголосовал свой игрок в этом собрании (MatchRules.SKIP_VOTE —
## пропуск); NO_VOTE — голос ещё не отдан. Меняется перед vote_cast со своим id.
var local_vote: int = NO_VOTE
## Клиент-участник: сколько раз свой игрок ещё может нажать тревожную кнопку в этом матче.
var button_uses_left: int = 0
## Сколько секунд тревожная кнопка ещё заперта для всех. Идёт на сервере и у участников.
var button_cooldown_left: float = 0.0

## Сервер: кто за кого проголосовал. До вердикта клиентам не уходит.
var _ballots: Dictionary[int, int] = {}
## Сервер: голоса клиентов, ждут ближайшего кадра: кто -> за кого. От одного игрока за
## кадр берём только первый запрос, так что поток запросов чужие голоса не вытеснит.
var _vote_requests: Dictionary[int, int] = {}
## Сервер: кому уже отправлено идущее собрание целиком. Игрок, вошедший в том же кадре,
## в котором собрание началось, не должен получить его дважды.
var _snapshot_sent: Dictionary[int, bool] = {}
## Сервер: сколько нажатий тревожной кнопки осталось у каждого участника.
var _button_uses: Dictionary[int, int] = {}


func _ready() -> void:
	Game.phase_changed.connect(_on_phase_changed)
	Game.round_started.connect(_on_round_started)
	Game.participant_out.connect(_on_participant_out)
	# Отложенно: Game сначала сам расскажет вошедшему про матч и фазу, потом мы — про собрание.
	Net.player_joined.connect(_on_player_joined, CONNECT_DEFERRED)
	# Фаза клиента могла не успеть дойти до него: конец сессии сбрасывает всё в любом случае.
	Net.disconnected.connect(_on_session_ended)
	Net.connection_failed.connect(_on_session_ended)


func _process(delta: float) -> void:
	if button_cooldown_left > 0.0:
		button_cooldown_left = maxf(button_cooldown_left - delta, 0.0)
		if button_cooldown_left <= 0.0:
			button_changed.emit()
	if Net.is_server():
		_server_process_votes()
	if stage == Stage.NONE or stage_seconds_left <= 0.0:
		return
	stage_seconds_left = maxf(stage_seconds_left - delta, 0.0)
	if stage_seconds_left <= 0.0 and Net.is_server():
		_server_advance()


func is_active() -> bool:
	return stage != Stage.NONE


## Сервер: созвать собрание. false, если сейчас нельзя (не идёт игра, созывающий мёртв).
## Лимит и пауза тревожной кнопки проверяются в can_press_button().
## Для Reason.BODY new_victim_id — погибший участник, чьё тело нашли.
func server_call(new_caller_id: int, new_reason: Reason, new_victim_id: int = 0) -> bool:
	if not Net.is_server() or is_active() or not Game.is_playing():
		return false
	if not Game.server_is_alive(new_caller_id):
		return false
	var body_id: int = 0
	if new_reason == Reason.BODY:
		if not Game.is_participant(new_victim_id) or Game.server_is_alive(new_victim_id):
			return false
		body_id = new_victim_id
	if not Game.server_begin_meeting():
		return false
	_clear_meeting()
	caller_id = new_caller_id
	reason = new_reason
	victim_id = body_id
	attendees = PackedInt32Array(Game.server_get_alive())
	if reason == Reason.BUTTON:
		_server_spend_button_use(caller_id)
	var discussion_seconds: float = maxf(Game.config.meeting_discussion_seconds, 0.0)
	if discussion_seconds > 0.0:
		stage = Stage.DISCUSSION
		stage_seconds_left = discussion_seconds
	else:
		stage = Stage.VOTING
		stage_seconds_left = maxf(Game.config.meeting_voting_seconds, 0.0)
	for peer_id: int in Net.players:
		_server_send_snapshot(peer_id)
	started.emit()
	# Подписчик started мог закончить матч (а с ним и собрание): тогда стадии уже нет.
	if is_active():
		stage_changed.emit(stage)
		_server_settle_stage()
	return true


## Может ли игрок сейчас нажать тревожную кнопку. Сервер: про любого. Клиент: про себя
## (про других — всегда false). Клиент не знает, жив ли его игрок и идёт ли саботаж, о
## котором сервер ещё не сказал: окончательно решает сервер.
func can_press_button(peer_id: int) -> bool:
	if Net.is_server():
		return MeetingRules.can_press_button(Game.is_playing() and not is_active(),
				Game.server_is_alive(peer_id), _server_get_button_uses(peer_id),
				button_cooldown_left, Game.sabotage.active)
	if not Net.is_joined() or peer_id != Net.local_id():
		return false
	return MeetingRules.can_press_button(Game.is_playing(), Game.is_participant(peer_id),
			button_uses_left, button_cooldown_left, Game.sabotage.active)


## Клиент: проголосовать за участника (MatchRules.SKIP_VOTE — пропустить).
## Сервер примет голос, только если can_local_vote() и is_candidate(target_id).
func request_vote(target_id: int) -> void:
	if Net.is_joined():
		_request_vote.rpc_id(Net.SERVER_ID, target_id)


## Клиент: может ли свой игрок сейчас голосовать (идёт голосование, он участник
## собрания и ещё не голосовал).
func can_local_vote() -> bool:
	return (Net.is_joined() and stage == Stage.VOTING
			and MeetingRules.can_vote(Net.local_id(), attendees, dropped, voted))


## Все пиры: можно ли в этом собрании голосовать за target_id (пропуск или участник
## собрания, который не выбыл).
func is_candidate(target_id: int) -> bool:
	return is_active() and MeetingRules.is_candidate(target_id, attendees, dropped)


# --- Сервер: ход собрания ---


## Стадия без времени проходит сразу; голосование кончается, как только ждать некого.
func _server_settle_stage() -> void:
	if not is_active():
		return
	if stage_seconds_left <= 0.0:
		_server_advance()
	elif stage == Stage.VOTING and MeetingRules.has_everyone_voted(attendees, dropped, voted):
		_server_advance()


## Перейти к следующей стадии: время текущей вышло или ждать больше нечего.
func _server_advance() -> void:
	match stage:
		Stage.DISCUSSION:
			_server_set_stage(Stage.VOTING, Game.config.meeting_voting_seconds)
		Stage.VOTING:
			_server_begin_verdict()
		Stage.VERDICT:
			_server_finish()


func _server_set_stage(new_stage: Stage, seconds: float) -> void:
	stage = new_stage
	stage_seconds_left = maxf(seconds, 0.0)
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_receive_stage.rpc_id(peer_id, stage, stage_seconds_left)
	stage_changed.emit(stage)
	_server_settle_stage()


## Разобрать голоса, пришедшие с прошлого кадра.
func _server_process_votes() -> void:
	if _vote_requests.is_empty():
		return
	var requests: Dictionary[int, int] = _vote_requests
	_vote_requests = {}
	for voter_id: int in requests:
		_server_vote(voter_id, requests[voter_id])


func _server_vote(voter_id: int, target_id: int) -> void:
	if stage != Stage.VOTING or not Game.server_is_alive(voter_id):
		return
	if not MeetingRules.is_vote_valid(voter_id, target_id, attendees, dropped, voted):
		return
	if target_id != MatchRules.SKIP_VOTE and not Game.server_is_alive(target_id):
		return
	_ballots[voter_id] = target_id
	voted[voter_id] = true
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			# За кого отдан голос, узнаёт только сам голосовавший.
			_receive_vote.rpc_id(peer_id, voter_id, target_id if peer_id == voter_id else NO_VOTE)
	vote_cast.emit(voter_id)
	_server_settle_stage()


func _server_begin_verdict() -> void:
	votes = _ballots.duplicate()
	ejected_id = MatchRules.tally_votes(votes)
	ejected_role = Game.Role.NONE
	# Раскрывать можно только роль самого изгнанного.
	if ejected_id != MatchRules.SKIP_VOTE and Game.config.reveal_role_on_eject:
		ejected_role = Game.get_role(ejected_id)
	stage = Stage.VERDICT
	stage_seconds_left = maxf(Game.config.meeting_verdict_seconds, 0.0)
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_receive_verdict.rpc_id(peer_id, votes, ejected_id, ejected_role, stage_seconds_left)
	stage_changed.emit(stage)
	verdict_ready.emit()
	_server_settle_stage()


## Конец вердикта: изгнать, закрыть собрание и вернуть игру.
func _server_finish() -> void:
	if ejected_id != MatchRules.SKIP_VOTE:
		# Карта убирает аватар, тот сообщает Game — и матч может на этом закончиться.
		ejected.emit(ejected_id)
	# Матч закончился на изгнании: собрание уже закрыто сменой фазы.
	if not is_active():
		return
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_receive_closed.rpc_id(peer_id)
	_close()
	Game.server_end_meeting()


## Вошедшему или всем на старте: собрание целиком, как оно есть сейчас.
func _server_send_snapshot(peer_id: int) -> void:
	if _snapshot_sent.has(peer_id) or not Net.is_peer_reachable(peer_id):
		return
	_snapshot_sent[peer_id] = true
	_receive_meeting.rpc_id(peer_id, caller_id, reason, victim_id, attendees, stage,
			stage_seconds_left, PackedInt32Array(voted.keys()), PackedInt32Array(dropped.keys()),
			votes, ejected_id, ejected_role)


# --- Сервер: тревожная кнопка ---


func _server_get_button_uses(peer_id: int) -> int:
	return _button_uses[peer_id] if _button_uses.has(peer_id) else 0


func _server_spend_button_use(peer_id: int) -> void:
	_button_uses[peer_id] = maxi(_server_get_button_uses(peer_id) - 1, 0)
	_server_send_button(peer_id)


## Каждому — только его собственный остаток нажатий; пауза у всех общая.
func _server_send_button(peer_id: int) -> void:
	if Net.players.has(peer_id) and Net.is_peer_reachable(peer_id):
		_receive_button.rpc_id(peer_id, _server_get_button_uses(peer_id), button_cooldown_left)


## Игра началась или продолжилась после собрания: кнопка заперта на время паузы.
func _server_start_button_cooldown() -> void:
	button_cooldown_left = maxf(Game.config.emergency_cooldown_seconds, 0.0)
	for peer_id: int in Game.participants:
		_server_send_button(peer_id)


# --- Сервер: события матча ---


## Роли розданы: у каждого участника полный запас нажатий кнопки.
func _on_round_started() -> void:
	_reset()
	for peer_id: int in Game.participants:
		_button_uses[peer_id] = maxi(Game.config.emergency_meetings_per_player, 0)


## Участник выбыл (вышел из игры) во время обсуждения или голосования: его голос и
## голоса за него пропадают. Второго голоса те, кто голосовал за него, не получают.
func _on_participant_out(peer_id: int) -> void:
	if stage != Stage.DISCUSSION and stage != Stage.VOTING:
		return
	if not attendees.has(peer_id) or dropped.has(peer_id):
		return
	dropped[peer_id] = true
	voted.erase(peer_id)
	_ballots = MeetingRules.discard_votes_of(_ballots, peer_id)
	for other_id: int in Net.players:
		if Net.is_peer_reachable(other_id):
			_receive_dropped.rpc_id(other_id, peer_id)
	attendee_dropped.emit(peer_id)
	_server_settle_stage()


## Вошедший посреди матча — зритель: собрание он видит, как и все.
func _on_player_joined(peer_id: int) -> void:
	if Net.is_server() and is_active() and Net.players.has(peer_id):
		_server_send_snapshot(peer_id)


# --- Общее ---


func _on_phase_changed(new_phase: Game.Phase) -> void:
	match new_phase:
		Game.Phase.PLAYING:
			if Net.is_server():
				_server_start_button_cooldown()
		Game.Phase.ENDED:
			# Матч закончился посреди собрания: закрываем без вердикта.
			_close()
		Game.Phase.NONE:
			_close()
			_reset()


func _on_session_ended(_reason: String) -> void:
	_close()
	_reset()


## Закрыть собрание на этом пире. Поля прошедшего собрания остаются до следующего.
func _close() -> void:
	if not is_active():
		return
	stage = Stage.NONE
	stage_seconds_left = 0.0
	_ballots.clear()
	_vote_requests.clear()
	closed.emit()


## Забыть всё о матче: и прошедшее собрание, и тревожную кнопку.
func _reset() -> void:
	_clear_meeting()
	_button_uses.clear()
	var had_button_state: bool = button_uses_left != 0 or button_cooldown_left > 0.0
	button_uses_left = 0
	button_cooldown_left = 0.0
	if had_button_state:
		button_changed.emit()


## Вернуть поля собрания в исходное состояние. Стадию не трогает.
func _clear_meeting() -> void:
	caller_id = 0
	reason = Reason.BUTTON
	victim_id = 0
	attendees = PackedInt32Array()
	voted = {}
	votes = {}
	ejected_id = MatchRules.SKIP_VOTE
	ejected_role = Game.Role.NONE
	dropped = {}
	local_vote = NO_VOTE
	_ballots.clear()
	_vote_requests.clear()
	_snapshot_sent.clear()


## Клиент: собрать в result множество id из присланного списка. false — список не годится.
func _fill_id_set(ids: PackedInt32Array, allowed: PackedInt32Array, result: Dictionary[int, bool]) -> bool:
	if ids.size() > Net.MAX_PLAYERS:
		return false
	for peer_id: int in ids:
		if not allowed.has(peer_id):
			return false
		result[peer_id] = true
	return true


## Клиент: через RPC словарь приходит нетипизированным — собираем его заново в result
## с проверкой. false — словарь не годится.
func _fill_votes(raw: Dictionary, allowed: PackedInt32Array, result: Dictionary[int, int]) -> bool:
	if raw.size() > Net.MAX_PLAYERS:
		return false
	for key: Variant in raw:
		var value: Variant = raw[key]
		if not (key is int and value is int) or not allowed.has(key as int):
			return false
		var target_id: int = value as int
		if target_id != MatchRules.SKIP_VOTE and not allowed.has(target_id):
			return false
		result[key as int] = target_id
	return true


## Клиент: изгнать могли только участника собрания (или никого).
func _is_ejected_id_valid(peer_id: int, allowed: PackedInt32Array) -> bool:
	return peer_id == MatchRules.SKIP_VOTE or allowed.has(peer_id)


# --- RPC: клиент -> сервер ---


## Голос клиента. Только ставится в очередь: проверка — в ближайшем кадре сервера.
@rpc("any_peer", "call_remote", "reliable")
func _request_vote(target_id: int) -> void:
	if not Net.is_server() or stage != Stage.VOTING:
		return
	var voter_id: int = multiplayer.get_remote_sender_id()
	if not attendees.has(voter_id) or voted.has(voter_id) or _vote_requests.has(voter_id):
		return
	_vote_requests[voter_id] = target_id


# --- RPC: сервер -> клиенты ---


## Собрание целиком: всем в его начале и вошедшему посреди него.
@rpc("authority", "call_remote", "reliable")
func _receive_meeting(new_caller_id: int, new_reason: int, new_victim_id: int,
		attendee_ids: PackedInt32Array, new_stage: int, seconds_left: float,
		voted_ids: PackedInt32Array, dropped_ids: PackedInt32Array,
		new_votes: Dictionary, new_ejected_id: int, new_ejected_role: int) -> void:
	if not Net.is_joined() or not Reason.values().has(new_reason):
		return
	if not Stage.values().has(new_stage) or new_stage == Stage.NONE or not is_finite(seconds_left):
		return
	if attendee_ids.is_empty() or attendee_ids.size() > Net.MAX_PLAYERS:
		return
	if not Game.Role.values().has(new_ejected_role):
		return
	var voted_set: Dictionary[int, bool] = {}
	var dropped_set: Dictionary[int, bool] = {}
	var typed_votes: Dictionary[int, int] = {}
	if not _fill_id_set(voted_ids, attendee_ids, voted_set):
		return
	if not _fill_id_set(dropped_ids, attendee_ids, dropped_set):
		return
	if not _fill_votes(new_votes, attendee_ids, typed_votes):
		return
	if not _is_ejected_id_valid(new_ejected_id, attendee_ids):
		return
	_clear_meeting()
	caller_id = new_caller_id
	reason = new_reason as Reason
	victim_id = new_victim_id
	attendees = attendee_ids
	voted = voted_set
	dropped = dropped_set
	stage = new_stage as Stage
	stage_seconds_left = maxf(seconds_left, 0.0)
	if stage == Stage.VERDICT:
		votes = typed_votes
		ejected_id = new_ejected_id
		ejected_role = new_ejected_role as Game.Role
	started.emit()
	stage_changed.emit(stage)
	if stage == Stage.VERDICT:
		verdict_ready.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_stage(new_stage: int, seconds_left: float) -> void:
	if not Net.is_joined() or not is_active() or not is_finite(seconds_left):
		return
	# Вердикт приходит своим сообщением, вместе с голосами.
	if new_stage != Stage.DISCUSSION and new_stage != Stage.VOTING:
		return
	stage = new_stage as Stage
	stage_seconds_left = maxf(seconds_left, 0.0)
	stage_changed.emit(stage)


## target_id — настоящий только у самого голосовавшего, остальным приходит NO_VOTE.
@rpc("authority", "call_remote", "reliable")
func _receive_vote(voter_id: int, target_id: int) -> void:
	if not Net.is_joined() or stage != Stage.VOTING:
		return
	if not attendees.has(voter_id) or dropped.has(voter_id):
		return
	voted[voter_id] = true
	if voter_id == Net.local_id() and (target_id == MatchRules.SKIP_VOTE or attendees.has(target_id)):
		local_vote = target_id
	vote_cast.emit(voter_id)


@rpc("authority", "call_remote", "reliable")
func _receive_dropped(peer_id: int) -> void:
	if not Net.is_joined() or not is_active():
		return
	if not attendees.has(peer_id) or dropped.has(peer_id):
		return
	dropped[peer_id] = true
	voted.erase(peer_id)
	attendee_dropped.emit(peer_id)


@rpc("authority", "call_remote", "reliable")
func _receive_verdict(new_votes: Dictionary, new_ejected_id: int, new_ejected_role: int,
		seconds_left: float) -> void:
	if not Net.is_joined() or not is_active() or not is_finite(seconds_left):
		return
	if not Game.Role.values().has(new_ejected_role):
		return
	var typed_votes: Dictionary[int, int] = {}
	if not _fill_votes(new_votes, attendees, typed_votes):
		return
	if not _is_ejected_id_valid(new_ejected_id, attendees):
		return
	votes = typed_votes
	ejected_id = new_ejected_id
	ejected_role = new_ejected_role as Game.Role
	stage = Stage.VERDICT
	stage_seconds_left = maxf(seconds_left, 0.0)
	stage_changed.emit(stage)
	verdict_ready.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_closed() -> void:
	if Net.is_joined():
		_close()


## Личное: сколько нажатий кнопки осталось у этого игрока и сколько ещё длится общая пауза.
@rpc("authority", "call_remote", "reliable")
func _receive_button(uses_left: int, cooldown_left: float) -> void:
	if not Net.is_joined() or uses_left < 0 or uses_left > MAX_BUTTON_USES:
		return
	if not is_finite(cooldown_left):
		return
	button_uses_left = uses_left
	button_cooldown_left = maxf(cooldown_left, 0.0)
	button_changed.emit()

