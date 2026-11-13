class_name TaskBoard
extends Node
## Задания экипажа (узел Game.tasks, есть на каждом пире).
## У каждого участника свой список станций. Общий прогресс виден всем, личный список —
## только хозяину. Задания предателей — фальшивые: выглядят так же, но в прогресс не идут.
## Станции карта сообщает сама (server_register_stations), о сценах TaskBoard не знает.
## Сам учёт (раздача, выполнение, работа выбывшего) — чистый класс TaskLedger.

## Все пиры: изменился общий прогресс экипажа (done_count, total_count).
signal progress_changed
## Клиент: изменился наш личный список заданий.
signal local_tasks_changed
## Клиент: сервер открыл нам задание с данными (например, код, который нужно ввести).
signal task_opened(station_id: int, data: Dictionary)
## Клиент: сервер ответил на нашу попытку выполнить задание.
signal task_feedback(station_id: int, success: bool)
## Сервер: игрок прислал ответ на задание (введённый код). Станция слушает этот сигнал
## и сама проверяет, что игрок рядом и ответ верный.
signal answer_received(peer_id: int, station_id: int, answer: String)

## Ответы на задания длиннее сервер не принимает.
const MAX_ANSWER_LENGTH: int = 16
## Сервер: больше ответов в секунду от одного игрока не принимаем (лишние молча пропадают).
const MAX_ANSWERS_PER_SECOND: int = 4
## Сервер: больше ответов до ближайшего физического тика не копим.
const MAX_QUEUED_ANSWERS: int = 32
## Клиент: список длиннее сервер прислать не может.
const MAX_LOCAL_TASKS: int = 64
## Клиент: данных у одного задания больше не бывает.
const MAX_OPEN_DATA_ENTRIES: int = 8
## Окно, в котором считаются ответы одного игрока, мс.
const ANSWER_WINDOW_MSEC: int = 1000

## Общий прогресс экипажа: сколько заданий сделано и сколько нужно.
var done_count: int = 0
var total_count: int = 0

## Сервер: станции заданий текущей карты.
var _station_ids: PackedInt32Array = []
## Сервер: кому что выдано и что сделано.
var _ledger: TaskLedger = TaskLedger.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Сервер: ответы клиентов ждут ближайшего физического тика: [peer_id, station_id, answer].
var _answers: Array[Array] = []
## Сервер: peer_id -> начало текущей секунды учёта ответов (мс) и сколько ответов в ней.
var _answer_window_start: Dictionary[int, int] = {}
var _answer_window_count: Dictionary[int, int] = {}

## Клиент: наш список — станции в порядке выдачи и какие из них сделаны.
var _local_tasks: PackedInt32Array = []
var _local_done: PackedInt32Array = []
## Клиент: можем ли мы ещё выполнять задания (false — наш игрок выбыл).
var _local_active: bool = false


func _ready() -> void:
	set_physics_process(false)
	Game.round_started.connect(_on_round_started)
	Game.participant_out.connect(_on_participant_out)
	Game.phase_changed.connect(_on_phase_changed)
	Net.player_joined.connect(_on_player_joined)
	# Сессия может оборваться раньше, чем клиент узнал о начале матча: тогда Game о конце
	# матча не сообщает, а список заданий уже мог прийти.
	Net.disconnected.connect(_reset.unbind(1))
	Net.connection_failed.connect(_reset.unbind(1))


## Сервер: разбираем ответы клиентов, пришедшие с прошлого тика.
func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	var answers: Array[Array] = _answers
	_answers = []
	for entry: Array in answers:
		var peer_id: int = entry[0]
		# Пока ответ ждал тика, игрок мог умереть или началось собрание.
		if Game.is_playing() and Game.server_is_alive(peer_id):
			answer_received.emit(peer_id, entry[1] as int, entry[2] as String)


## Все задания экипажа сделаны. Без заданий (карта без станций) победы по ним нет.
func is_all_done() -> bool:
	return total_count > 0 and done_count >= total_count


## Сервер: карта сообщает id своих станций заданий (до начала раунда).
func server_register_stations(station_ids: PackedInt32Array) -> void:
	if Net.is_server():
		_station_ids = station_ids.duplicate()


## Сервер: ждёт ли это задание этого игрока. Клиент: то же, но только про себя.
## У выбывшего игрока (мёртв, изгнан) заданий в работе нет, хотя список он видит.
func is_pending(peer_id: int, station_id: int) -> bool:
	if Net.is_server():
		return _ledger.is_pending(peer_id, station_id)
	return (_local_active and Net.is_joined() and peer_id == Net.local_id()
			and _local_tasks.has(station_id) and not _local_done.has(station_id))


## Клиент: наш список — id станций в порядке выдачи.
func get_local_tasks() -> PackedInt32Array:
	return _local_tasks.duplicate()


## Клиент: сделано ли наше задание на этой станции.
func is_local_done(station_id: int) -> bool:
	return _local_done.has(station_id)


## Сервер: игрок выполнил задание на станции. Чужое или уже сделанное задание — ничего.
## Вызывает станция; задания засчитываются только живым и только пока идёт игра.
func server_complete(peer_id: int, station_id: int) -> void:
	if not Net.is_server() or not Game.is_playing() or not Game.server_is_alive(peer_id):
		return
	if not _ledger.complete(peer_id, station_id):
		return
	_send_tasks(peer_id)
	_server_update_progress()
	Game.server_check_win()


## Клиент: отправить серверу ответ на открытое задание (например, введённый код).
func request_answer(station_id: int, answer: String) -> void:
	if Net.is_joined():
		_request_answer.rpc_id(Net.SERVER_ID, station_id, answer.left(MAX_ANSWER_LENGTH))


## Сервер: открыть игроку задание с данными (придёт ему сигналом task_opened).
func server_open(peer_id: int, station_id: int, data: Dictionary) -> void:
	if Net.is_server() and Net.players.has(peer_id) and Net.is_peer_reachable(peer_id):
		_receive_opened.rpc_id(peer_id, station_id, data)


## Сервер: сообщить игроку исход попытки (придёт ему сигналом task_feedback).
func server_send_feedback(peer_id: int, station_id: int, success: bool) -> void:
	if Net.is_server() and Net.players.has(peer_id) and Net.is_peer_reachable(peer_id):
		_receive_feedback.rpc_id(peer_id, station_id, success)


# --- Сервер ---


## Роли розданы: каждому участнику — свой список, всем — общий счёт.
func _on_round_started() -> void:
	if not Net.is_server():
		return
	var peer_ids: Array[int] = []
	var crew_ids: Array[int] = []
	for peer_id: int in Game.participants:
		peer_ids.append(peer_id)
		if Game.get_role(peer_id) != Game.Role.TRAITOR:
			crew_ids.append(peer_id)
	_ledger.assign(peer_ids, crew_ids, _station_ids, Game.config.tasks_per_player, _rng)
	_answers.clear()
	_answer_window_start.clear()
	_answer_window_count.clear()
	_server_update_progress()
	for peer_id: int in peer_ids:
		_send_tasks(peer_id)


## Участник выбыл: его несделанные задания достаются живому экипажу («работа коллеги»).
## Победу после этого проверяет сам Game.
func _on_participant_out(peer_id: int) -> void:
	if not Net.is_server() or not _ledger.is_active(peer_id):
		return
	var receivers: Array[int] = _ledger.remove(peer_id)
	# Выбывший видит свой список и дальше, но узнаёт, что выполнять его уже не может.
	_send_tasks(peer_id)
	for receiver: int in receivers:
		_send_tasks(receiver)
	_server_update_progress()


## Вошедший посреди матча (зритель) узнаёт общий прогресс. Списка у него нет.
func _on_player_joined(peer_id: int) -> void:
	if Net.is_server() and Game.phase != Game.Phase.NONE and Net.is_peer_reachable(peer_id):
		_receive_progress.rpc_id(peer_id, done_count, total_count)


func _server_update_progress() -> void:
	var new_done: int = _ledger.get_done_count()
	var new_total: int = _ledger.get_total_count()
	if new_done == done_count and new_total == total_count:
		return
	_set_progress(new_done, new_total)
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_receive_progress.rpc_id(peer_id, done_count, total_count)


## Личный список — только хозяину.
func _send_tasks(peer_id: int) -> void:
	if not _ledger.has_peer(peer_id) or not Net.players.has(peer_id) or not Net.is_peer_reachable(peer_id):
		return
	var tasks: PackedInt32Array = _ledger.get_tasks(peer_id)
	var done: PackedInt32Array = []
	for station_id: int in tasks:
		if _ledger.is_done(peer_id, station_id):
			done.append(station_id)
	_receive_tasks.rpc_id(peer_id, tasks, done, _ledger.is_active(peer_id))


## Не больше MAX_ANSWERS_PER_SECOND ответов в секунду от одного игрока.
func _is_answer_allowed(peer_id: int) -> bool:
	var now: int = Time.get_ticks_msec()
	if not _answer_window_start.has(peer_id) or now - _answer_window_start[peer_id] >= ANSWER_WINDOW_MSEC:
		_answer_window_start[peer_id] = now
		_answer_window_count[peer_id] = 0
	if _answer_window_count[peer_id] >= MAX_ANSWERS_PER_SECOND:
		return false
	_answer_window_count[peer_id] += 1
	return true


# --- Общее ---


func _on_phase_changed(new_phase: Game.Phase) -> void:
	if new_phase == Game.Phase.NONE:
		_reset()


## Матча больше нет (на всех пирах): забываем списки, станции и счёт.
func _reset() -> void:
	_station_ids = PackedInt32Array()
	_ledger.clear()
	_answers.clear()
	_answer_window_start.clear()
	_answer_window_count.clear()
	_set_progress(0, 0)
	_set_local_tasks(PackedInt32Array(), PackedInt32Array(), false)


func _set_progress(new_done: int, new_total: int) -> void:
	if new_done == done_count and new_total == total_count:
		return
	done_count = new_done
	total_count = new_total
	progress_changed.emit()


func _set_local_tasks(tasks: PackedInt32Array, done: PackedInt32Array, active: bool) -> void:
	if tasks == _local_tasks and done == _local_done and active == _local_active:
		return
	_local_tasks = tasks
	_local_done = done
	_local_active = active
	local_tasks_changed.emit()


# --- Сеть ---


@rpc("any_peer", "call_remote", "reliable")
func _request_answer(station_id: int, answer: String) -> void:
	if not Net.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not Net.players.has(sender) or not Game.is_participant(sender):
		return
	if not _station_ids.has(station_id) or answer.length() > MAX_ANSWER_LENGTH:
		return
	if _answers.size() >= MAX_QUEUED_ANSWERS or not _is_answer_allowed(sender):
		return
	_answers.append([sender, station_id, answer])
	set_physics_process(true)


@rpc("authority", "call_remote", "reliable")
func _receive_progress(new_done: int, new_total: int) -> void:
	if not Net.is_joined() or new_done < 0 or new_total < new_done or new_total > Net.MAX_PLAYERS * MAX_LOCAL_TASKS:
		return
	_set_progress(new_done, new_total)


@rpc("authority", "call_remote", "reliable")
func _receive_tasks(tasks: PackedInt32Array, done: PackedInt32Array, active: bool) -> void:
	if not Net.is_joined() or tasks.size() > MAX_LOCAL_TASKS or done.size() > tasks.size():
		return
	for station_id: int in done:
		if not tasks.has(station_id):
			return
	_set_local_tasks(tasks, done, active)


@rpc("authority", "call_remote", "reliable")
func _receive_opened(station_id: int, data: Dictionary) -> void:
	if Net.is_joined() and data.size() <= MAX_OPEN_DATA_ENTRIES:
		task_opened.emit(station_id, data)


@rpc("authority", "call_remote", "reliable")
func _receive_feedback(station_id: int, success: bool) -> void:
	if Net.is_joined():
		task_feedback.emit(station_id, success)
