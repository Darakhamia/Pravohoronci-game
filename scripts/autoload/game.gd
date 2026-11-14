extends Node
## Состояние матча: лобби или матч, фазы раунда, роли, условия победы. Решает сервер,
## клиенты получают копию. О сценах Game ничего не знает: карту ведёт World, а о смертях
## Game узнаёт от аватаров через server_participant_out().
## Части матча со своей сетевой логикой — дочерние узлы tasks, meeting и sabotage. Они есть
## на каждом пире по одним и тем же путям и никогда не удаляются, поэтому их RPC безопасны.
## Роли — скрытая информация: сервер шлёт каждому только его роль (предателям ещё и
## напарников). Остальные роли клиент узнаёт лишь из итогов матча.

signal state_changed(new_state: State)
signal min_players_changed(value: int)
## Все пиры: сменилась фаза матча. Сколько она продлится — в phase_seconds_left.
signal phase_changed(new_phase: Phase)
## Сервер: роли розданы, раунд начинается. Части матча готовят здесь своё состояние.
signal round_started
## Клиент: сервер сообщил нам нашу роль.
signal role_assigned(role: Role)
## Сервер: участник выбыл из живых (убит, изгнан или вышел из игры).
signal participant_out(peer_id: int)
## Все пиры: матч закончился, итог лежит и в last_result.
signal match_ended(result: MatchResult)

enum State { LOBBY, MATCH }
## Фазы матча. NONE — матча нет. В ROLE_REVEAL, MEETING и ENDED игроки не двигаются.
enum Phase { NONE, ROLE_REVEAL, PLAYING, MEETING, ENDED }
enum Role { NONE, CREW, TRAITOR }
enum Winner { NONE, CREW, TRAITORS }
enum EndReason { NONE, TASKS_DONE, TRAITORS_ELIMINATED, CREW_OUTNUMBERED, SABOTAGE }

## debug_traitor_count: число предателей считается по правилам.
const TRAITORS_BY_RULES: int = -1

## Настройки матча. Переменная, а не константа: свойства ресурса из const preload GDScript
## подставляет в код при компиляции, и переопределение флагом --set на них бы не действовало.
var config: GameConfig = preload("res://resources/game_config.tres")
var state: State = State.LOBBY
## Сервер: действующий минимум игроков для старта. Клиенты: копия с сервера.
var min_players: int = config.min_players:
	set(value):
		var clamped: int = clampi(value, 1, Net.MAX_PLAYERS)
		if clamped == min_players:
			return
		min_players = clamped
		min_players_changed.emit(min_players)
		_send_state_to_players()
var phase: Phase = Phase.NONE
## Сколько секунд осталось до конца фазы; 0 — у фазы нет таймера. Идёт на всех пирах.
var phase_seconds_left: float = 0.0
## Участники идущего матча (у кого есть аватар), в порядке лобби. Известно всем.
var participants: PackedInt32Array = []
## Клиент: своя роль в идущем матче.
var local_role: Role = Role.NONE
## Итог последнего матча; null, пока идёт новый или матчей не было.
var last_result: MatchResult = null

## Задания экипажа.
var tasks: TaskBoard = null
## Собрание и голосование.
var meeting: Meeting = null
## Саботаж предателей.
var sabotage: Sabotage = null

## Сервер, отладка и тесты (флаг --traitors): сколько предателей раздать.
var debug_traitor_count: int = TRAITORS_BY_RULES
## Сервер, отладка и тесты (флаг --traitor-name): игроки с этими именами — предатели.
var debug_traitor_names: PackedStringArray = []
## Сервер, отладка и тесты (флаг --map): имя файла карты без расширения вместо основной.
var debug_map_name: String = ""

## Сервер: роли всех участников. Клиент: только те, что ему известны.
var _roles: Dictionary[int, Role] = {}
## Сервер: кто из участников жив.
var _alive: Dictionary[int, bool] = {}
## Сервер: имена участников на старте (вышедший игрок остаётся в итогах).
var _names_at_start: Dictionary[int, String] = {}
var _colors_at_start: Dictionary[int, int] = {}
var _traitors_at_start: int = 0
var _crew_at_start: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	tasks = TaskBoard.new()
	tasks.name = &"Tasks"
	add_child(tasks)
	meeting = Meeting.new()
	meeting.name = &"Meeting"
	add_child(meeting)
	sabotage = Sabotage.new()
	sabotage.name = &"Sabotage"
	add_child(sabotage)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.disconnected.connect(_on_session_ended)
	Net.connection_failed.connect(_on_session_ended)


func _process(delta: float) -> void:
	if phase_seconds_left <= 0.0:
		return
	phase_seconds_left = maxf(phase_seconds_left - delta, 0.0)
	if phase_seconds_left <= 0.0 and Net.is_server():
		_on_phase_timeout()


func can_start_match() -> bool:
	return state == State.LOBBY and Net.players.size() >= min_players


## Клиент просит сервер начать матч. Сервер выполнит просьбу только от хоста.
func request_start_match() -> void:
	if Net.is_joined():
		_request_start_match.rpc_id(Net.SERVER_ID)


## Хост прерывает матч без победителя (кнопка в паузе).
func request_end_match() -> void:
	if Net.is_joined():
		_request_end_match.rpc_id(Net.SERVER_ID)


## Только сервер. false, если начать нельзя.
func start_match() -> bool:
	if not Net.is_server() or not can_start_match():
		return false
	# World по этому сигналу сразу загружает карту и расставляет аватары.
	_set_state(State.MATCH)
	_begin_round()
	return true


## Только сервер: вернуться в лобби (после итогов или по просьбе хоста).
func end_match() -> void:
	if not Net.is_server():
		return
	_clear_round()
	_send_round_to_players()
	_set_state(State.LOBBY)


## Идёт ли обычная игра: можно двигаться, стрелять, пользоваться предметами.
func is_playing() -> bool:
	return state == State.MATCH and phase == Phase.PLAYING


func is_participant(peer_id: int) -> bool:
	return participants.has(peer_id)


## Сервер: роль любого участника. Клиент: своя роль, напарники-предатели, а после
## конца матча — все. Неизвестная роль — Role.NONE.
func get_role(peer_id: int) -> Role:
	return _roles[peer_id] if _roles.has(peer_id) else Role.NONE


## Клиент-предатель: id напарников. У экипажа и на сервере пусто.
func get_fellow_traitors() -> PackedInt32Array:
	var fellows: PackedInt32Array = []
	if Net.is_server() or local_role != Role.TRAITOR:
		return fellows
	for peer_id: int in _roles:
		if _roles[peer_id] == Role.TRAITOR and peer_id != Net.local_id():
			fellows.append(peer_id)
	return fellows


## Сервер: жив ли участник.
func server_is_alive(peer_id: int) -> bool:
	return _alive.has(peer_id) and _alive[peer_id]


## Сервер: живые участники в порядке лобби.
func server_get_alive() -> Array[int]:
	var result: Array[int] = []
	for peer_id: int in participants:
		if server_is_alive(peer_id):
			result.append(peer_id)
	return result


## Сервер: участник больше не жив. Вызывает аватар при смерти и изгнании, а Game сам —
## когда игрок вышел. Повторный вызов ничего не делает.
func server_participant_out(peer_id: int) -> void:
	if not Net.is_server() or not server_is_alive(peer_id):
		return
	_alive[peer_id] = false
	participant_out.emit(peer_id)
	server_check_win()


## Сервер: проверить условия победы. Вызывается после каждой смерти, выхода игрока
## и каждого задания — в том числе во время показа ролей: игрок может выйти и тогда.
func server_check_win() -> void:
	if not Net.is_server() or phase == Phase.NONE or phase == Phase.ENDED:
		return
	var traitors_alive: int = 0
	var crew_alive: int = 0
	for peer_id: int in _alive:
		if not _alive[peer_id]:
			continue
		if _roles[peer_id] == Role.TRAITOR:
			traitors_alive += 1
		else:
			crew_alive += 1
	var winner: Winner = MatchRules.winner_by_headcount(
			traitors_alive, crew_alive, _traitors_at_start, _crew_at_start)
	if winner == Winner.CREW:
		server_finish(winner, EndReason.TRAITORS_ELIMINATED)
	elif winner == Winner.TRAITORS:
		server_finish(winner, EndReason.CREW_OUTNUMBERED)
	elif tasks.is_all_done():
		server_finish(Winner.CREW, EndReason.TASKS_DONE)


## Сервер: закончить матч с этим исходом и показать всем итоги.
func server_finish(winner: Winner, reason: EndReason) -> void:
	if not Net.is_server() or state != State.MATCH or phase == Phase.NONE or phase == Phase.ENDED:
		return
	last_result = _build_result(winner, reason)
	_set_phase(Phase.ENDED, config.results_seconds)
	for peer_id: int in Net.players:
		_send_result(peer_id)
	match_ended.emit(last_result)
	if config.results_seconds <= 0.0:
		end_match()


## Сервер: начать собрание. false, если сейчас нельзя. Вызывает только Meeting.
func server_begin_meeting() -> bool:
	if not Net.is_server() or not is_playing():
		return false
	_set_phase(Phase.MEETING)
	return true


## Сервер: собрание закончилось, игра продолжается. Вызывает только Meeting.
func server_end_meeting() -> void:
	if Net.is_server() and phase == Phase.MEETING:
		_set_phase(Phase.PLAYING)


# --- Сервер: ход раунда ---


func _begin_round() -> void:
	var peer_ids: Array[int] = []
	peer_ids.assign(Net.players.keys())
	participants = PackedInt32Array(peer_ids)
	var forced: Array[int] = []
	for peer_id: int in peer_ids:
		if debug_traitor_names.has(Net.get_player_name(peer_id)):
			forced.append(peer_id)
	var traitors: int = debug_traitor_count
	if traitors == TRAITORS_BY_RULES:
		traitors = MatchRules.traitor_count(peer_ids.size(), config)
	_roles = MatchRules.deal_roles(peer_ids, traitors, forced, _rng)
	_alive.clear()
	_names_at_start.clear()
	_colors_at_start.clear()
	_traitors_at_start = 0
	for peer_id: int in peer_ids:
		_alive[peer_id] = true
		_names_at_start[peer_id] = Net.get_player_name(peer_id)
		_colors_at_start[peer_id] = Net.get_player_color(peer_id)
		if _roles[peer_id] == Role.TRAITOR:
			_traitors_at_start += 1
	_crew_at_start = peer_ids.size() - _traitors_at_start
	last_result = null
	for peer_id: int in peer_ids:
		_send_role(peer_id)
	round_started.emit()
	if config.role_reveal_seconds > 0.0:
		_set_phase(Phase.ROLE_REVEAL, config.role_reveal_seconds)
	else:
		_set_phase(Phase.PLAYING)


func _on_phase_timeout() -> void:
	match phase:
		Phase.ROLE_REVEAL:
			_set_phase(Phase.PLAYING)
		Phase.ENDED:
			end_match()


func _build_result(winner: Winner, reason: EndReason) -> MatchResult:
	var result: MatchResult = MatchResult.new()
	result.winner = winner
	result.reason = reason
	for peer_id: int in participants:
		result.add_entry(peer_id, _names_at_start[peer_id], _colors_at_start[peer_id],
				_roles[peer_id], server_is_alive(peer_id))
	return result


## Каждому — только его роль; напарников узнают одни предатели.
func _send_role(peer_id: int) -> void:
	if not Net.is_peer_reachable(peer_id):
		return
	var role: Role = _roles[peer_id]
	var fellows: PackedInt32Array = []
	if role == Role.TRAITOR:
		for other_id: int in _roles:
			if other_id != peer_id and _roles[other_id] == Role.TRAITOR:
				fellows.append(other_id)
	_receive_role.rpc_id(peer_id, role, fellows)


func _send_result(peer_id: int) -> void:
	if last_result != null and Net.is_peer_reachable(peer_id):
		_receive_result.rpc_id(peer_id, last_result.winner, last_result.reason, last_result.to_rows())


# --- Общее ---


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)
	_send_state_to_players()


func _set_phase(new_phase: Phase, seconds: float = 0.0) -> void:
	phase_seconds_left = maxf(seconds, 0.0)
	if new_phase != phase:
		phase = new_phase
		phase_changed.emit(phase)
	_send_round_to_players()


## Забыть всё о раунде: и на сервере после матча, и на клиенте после выхода.
func _clear_round() -> void:
	participants = PackedInt32Array()
	local_role = Role.NONE
	_roles.clear()
	_alive.clear()
	_names_at_start.clear()
	_colors_at_start.clear()
	_traitors_at_start = 0
	_crew_at_start = 0
	phase_seconds_left = 0.0
	if phase != Phase.NONE:
		phase = Phase.NONE
		phase_changed.emit(phase)


func _send_state_to_players() -> void:
	if not Net.is_server():
		return
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_sync_state.rpc_id(peer_id, state, min_players)


func _send_round_to_players() -> void:
	if not Net.is_server():
		return
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_sync_round.rpc_id(peer_id, phase, phase_seconds_left, participants)


func _on_player_joined(peer_id: int) -> void:
	if not Net.is_peer_reachable(peer_id):
		return
	_sync_state.rpc_id(peer_id, state, min_players)
	# Вошедший посреди матча смотрит его зрителем: роли ему не положены, итоги — да.
	_sync_round.rpc_id(peer_id, phase, phase_seconds_left, participants)
	if phase == Phase.ENDED:
		_send_result(peer_id)


func _on_player_left(peer_id: int) -> void:
	if not Net.is_server():
		return
	if state == State.MATCH:
		server_participant_out(peer_id)
	# Матч без игроков не нужен: возвращаемся в лобби и ждём новых.
	if Net.players.is_empty():
		end_match()


func _on_session_ended(_reason: String) -> void:
	min_players = config.min_players
	last_result = null
	_clear_round()
	_set_state(State.LOBBY)


@rpc("any_peer", "call_remote", "reliable")
func _request_start_match() -> void:
	if Net.is_server() and Net.is_host(multiplayer.get_remote_sender_id()):
		start_match()


@rpc("any_peer", "call_remote", "reliable")
func _request_end_match() -> void:
	if Net.is_server() and Net.is_host(multiplayer.get_remote_sender_id()):
		end_match()


@rpc("authority", "call_remote", "reliable")
func _sync_state(new_state: int, new_min_players: int) -> void:
	if not Net.is_joined():
		return
	if not State.values().has(new_state) or new_min_players < 1 or new_min_players > Net.MAX_PLAYERS:
		return
	min_players = new_min_players
	_set_state(new_state as State)


@rpc("authority", "call_remote", "reliable")
func _sync_round(new_phase: int, seconds_left: float, participant_ids: PackedInt32Array) -> void:
	if not Net.is_joined() or not Phase.values().has(new_phase) or not is_finite(seconds_left):
		return
	if participant_ids.size() > Net.MAX_PLAYERS:
		return
	if new_phase == Phase.NONE:
		_clear_round()
		return
	if phase == Phase.NONE:
		# Новый матч: итоги прошлого больше не нужны.
		last_result = null
	participants = participant_ids
	phase_seconds_left = maxf(seconds_left, 0.0)
	if new_phase != phase:
		phase = new_phase as Phase
		phase_changed.emit(phase)


@rpc("authority", "call_remote", "reliable")
func _receive_role(role: int, fellow_ids: PackedInt32Array) -> void:
	if not Net.is_joined() or (role != Role.CREW and role != Role.TRAITOR):
		return
	if fellow_ids.size() > Net.MAX_PLAYERS:
		return
	local_role = role as Role
	_roles.clear()
	_roles[Net.local_id()] = local_role
	if local_role == Role.TRAITOR:
		for peer_id: int in fellow_ids:
			_roles[peer_id] = Role.TRAITOR
	role_assigned.emit(local_role)


@rpc("authority", "call_remote", "reliable")
func _receive_result(winner: int, reason: int, rows: Array) -> void:
	if not Net.is_joined():
		return
	var result: MatchResult = MatchResult.from_rows(winner, reason, rows)
	if result == null:
		return
	last_result = result
	# С этого момента роли открыты всем.
	for entry: MatchResult.Entry in result.entries:
		_roles[entry.peer_id] = entry.role
	match_ended.emit(result)
