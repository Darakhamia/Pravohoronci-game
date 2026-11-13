class_name Sabotage
extends Node
## Саботаж предателей (узел Game.sabotage, есть на каждом пире). В MVP он один и
## критический: перегрев реактора. Если его не починить за отведённое время, побеждают
## предатели. Чинит любой живой игрок на пульте реактора (ReactorPanel).
## Отсчёт до взрыва виден всем. Пауза до следующего саботажа — скрытая информация: её
## получают только предатели. Пауза идёт, только пока идёт игра (не на показе ролей и не
## на собрании); первая после начала матча — Game.config.sabotage_first_delay_seconds.

## Все пиры: саботаж начался; сколько осталось — в seconds_left.
signal started
## Все пиры: саботаж закончился. fixed == false — время вышло, или его сбросило собрание.
signal ended(fixed: bool)
## Клиент-предатель: изменилась пауза до следующего саботажа (cooldown_left): сервер
## прислал новое значение или она дошла до нуля.
signal cooldown_changed

## Сервер: больше просьб до ближайшего физического тика не копим.
const MAX_QUEUED_REQUESTS: int = 8
## Клиент: отсчёт или паузу длиннее сервер прислать не может (см. пределы в GameConfig).
const MAX_SECONDS: float = 600.0

## Идёт ли саботаж.
var active: bool = false
## Сколько секунд осталось до взрыва. Идёт на всех пирах.
var seconds_left: float = 0.0
## Сколько секунд до того, как саботаж снова можно включить. Знают сервер и предатели.
var cooldown_left: float = 0.0

## Сервер: кто просил включить саботаж с прошлого физического тика.
var _requests: PackedInt32Array = []


func _ready() -> void:
	set_physics_process(false)
	Game.round_started.connect(_on_round_started)
	Game.phase_changed.connect(_on_phase_changed)
	Game.meeting.started.connect(_on_meeting_started)
	Net.player_joined.connect(_on_player_joined)
	# Сессия может оборваться раньше, чем клиент узнал о начале матча: тогда Game о конце
	# матча не сообщает, а пауза предателю уже могла прийти.
	Net.disconnected.connect(_reset.unbind(1))
	Net.connection_failed.connect(_reset.unbind(1))


## Все пиры: идут отсчёт до взрыва и пауза до следующего саботажа — только пока идёт игра.
func _process(delta: float) -> void:
	if not Game.is_playing():
		return
	if active:
		seconds_left = maxf(seconds_left - delta, 0.0)
		if seconds_left <= 0.0 and Net.is_server():
			_server_explode()
	elif cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
		if cooldown_left <= 0.0:
			cooldown_changed.emit()


## Сервер: разбираем просьбы клиентов, пришедшие с прошлого тика.
func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	var requests: PackedInt32Array = _requests
	_requests = PackedInt32Array()
	for peer_id: int in requests:
		if can_trigger(peer_id):
			_server_start()


## Клиент-предатель: попросить сервер включить саботаж.
func request() -> void:
	if Net.is_joined():
		_request_trigger.rpc_id(Net.SERVER_ID)


## Может ли игрок сейчас включить саботаж. Сервер: про любого. Клиент: про себя
## (по тому, что он знает: роль, фаза, идёт ли саботаж, пауза).
func can_trigger(peer_id: int) -> bool:
	if active or cooldown_left > 0.0 or not Game.is_playing():
		return false
	if Net.is_server():
		return Game.server_is_alive(peer_id) and Game.get_role(peer_id) == Game.Role.TRAITOR
	return Net.is_joined() and peer_id == Net.local_id() and Game.local_role == Game.Role.TRAITOR


## Сервер: игрок починил реактор (вызывает пульт после удержания).
func server_fix(peer_id: int) -> void:
	if Net.is_server() and active and Game.is_playing() and Game.server_is_alive(peer_id):
		_server_end(true)


# --- Сервер ---


## Роли розданы: саботажа нет, первая пауза пошла.
func _on_round_started() -> void:
	if not Net.is_server():
		return
	active = false
	seconds_left = 0.0
	_requests.clear()
	cooldown_left = Game.config.sabotage_first_delay_seconds
	_send_cooldown_to_traitors()


## Собрание сбрасывает саботаж.
func _on_meeting_started() -> void:
	if Net.is_server() and active:
		_server_end(false)


## Вошедший посреди матча (зритель) узнаёт об идущем саботаже. Пауза ему не положена.
func _on_player_joined(peer_id: int) -> void:
	if Net.is_server() and active and Net.is_peer_reachable(peer_id):
		_receive_started.rpc_id(peer_id, seconds_left)


func _server_start() -> void:
	active = true
	seconds_left = Game.config.sabotage_countdown_seconds
	started.emit()
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_receive_started.rpc_id(peer_id, seconds_left)


## Саботаж закончился: починили (fixed) или сбросили. Пауза начинается заново.
func _server_end(fixed: bool) -> void:
	active = false
	seconds_left = 0.0
	cooldown_left = Game.config.sabotage_cooldown_seconds
	ended.emit(fixed)
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_receive_ended.rpc_id(peer_id, fixed)
	_send_cooldown_to_traitors()


## Время вышло: реактор взорвался, победа предателей.
func _server_explode() -> void:
	_server_end(false)
	Game.server_finish(Game.Winner.TRAITORS, Game.EndReason.SABOTAGE)


## Паузу узнают только предатели (живые и мёртвые): экипажу она ни к чему.
func _send_cooldown_to_traitors() -> void:
	for peer_id: int in Game.participants:
		if (Game.get_role(peer_id) == Game.Role.TRAITOR and Net.players.has(peer_id)
				and Net.is_peer_reachable(peer_id)):
			_receive_cooldown.rpc_id(peer_id, cooldown_left)


# --- Общее ---


func _on_phase_changed(new_phase: Game.Phase) -> void:
	match new_phase:
		Game.Phase.NONE:
			_reset()
		Game.Phase.PLAYING:
			# Пауза стояла, пока не шла игра: сверяем часы предателей с сервером.
			if Net.is_server():
				_send_cooldown_to_traitors()
		Game.Phase.ENDED:
			# Матч закончился — отсчёт останавливается.
			if Net.is_server() and active:
				_server_end(false)


## Матча больше нет (на всех пирах).
func _reset() -> void:
	_requests.clear()
	seconds_left = 0.0
	if active:
		active = false
		ended.emit(false)
	if cooldown_left > 0.0:
		cooldown_left = 0.0
		cooldown_changed.emit()


# --- Сеть ---


@rpc("any_peer", "call_remote", "reliable")
func _request_trigger() -> void:
	if not Net.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not Net.players.has(sender) or not Game.is_participant(sender):
		return
	if _requests.size() >= MAX_QUEUED_REQUESTS or _requests.has(sender):
		return
	_requests.append(sender)
	set_physics_process(true)


@rpc("authority", "call_remote", "reliable")
func _receive_started(seconds: float) -> void:
	if not Net.is_joined() or not is_finite(seconds) or seconds <= 0.0 or seconds > MAX_SECONDS:
		return
	seconds_left = seconds
	if not active:
		active = true
		started.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_ended(fixed: bool) -> void:
	if not Net.is_joined() or not active:
		return
	active = false
	seconds_left = 0.0
	ended.emit(fixed)


@rpc("authority", "call_remote", "reliable")
func _receive_cooldown(seconds: float) -> void:
	if not Net.is_joined() or not is_finite(seconds) or seconds < 0.0 or seconds > MAX_SECONDS:
		return
	cooldown_left = seconds
	cooldown_changed.emit()
