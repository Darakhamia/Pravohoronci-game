extends Node
## Подключение, лобби и список игроков.
## Единственное место, где трогаем ENetMultiplayerPeer и сигналы подключения multiplayer.*.
## Роль всегда определяем через Net.is_server(): после закрытия сессии движок ставит
## OfflineMultiplayerPeer, для которого multiplayer.is_server() возвращает true.

## Клиент: сервер принял регистрацию (пришёл первый список лобби).
signal connected
## Клиент: в лобби попасть не удалось (сервер недоступен, тайм-аут, отказ).
signal connection_failed(reason: String)
## Клиент: сессия закончилась после входа в лобби. После leave() причина пустая.
signal disconnected(reason: String)
## Все: изменился список игроков или хост.
signal lobby_changed
signal player_joined(peer_id: int)
signal player_left(peer_id: int)

enum Status { OFFLINE, CONNECTING, JOINED, SERVER }

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 8
const PROTOCOL_VERSION: int = 4
const SERVER_ID: int = 1

## Соединений принимаем больше, чем игроков: лишнему нужно успеть объяснить отказ.
const SPARE_CONNECTIONS: int = 4
const CONNECT_TIMEOUT_SEC: float = 8.0
## Сервер: имя длиннее этого обрезаем до разбора. Иначе мегабайтная строка от любого
## подключившегося заняла бы главный поток сервера на секунды.
const MAX_RAW_NAME_LENGTH: int = 64
const REGISTER_TIMEOUT_SEC: float = 5.0

const REASON_CONNECT_FAILED: String = "Не удалось подключиться к серверу"
const REASON_NO_RESPONSE: String = "Сервер не отвечает"
const REASON_CONNECTION_LOST: String = "Соединение с сервером потеряно"
const REASON_VERSION_MISMATCH: String = "Версия игры не совпадает с сервером. Обнови игру."
const REASON_NOT_REGISTERED: String = "Клиент не прошёл регистрацию"
const REASON_SERVER_FULL: String = "Сервер заполнен"

## Остальные скрипты эти три поля только читают.
var status: Status = Status.OFFLINE
## peer_id -> имя. Порядок вставки == порядок входа.
var players: Dictionary[int, String] = {}
## peer_id -> номер цвета из PlayerPalette. Закреплён за игроком, пока он на сервере.
var player_colors: Dictionary[int, int] = {}
## Хост лобби — самый ранний из зарегистрированных игроков. 0 — хоста нет.
var host_id: int = 0

## Номер сессии. Отложенные проверки сравнивают его, чтобы не сработать в чужой сессии.
var _session: int = 0
## Сервер: подключённые пиры, которые ещё могут зарегистрироваться.
var _unregistered: Dictionary[int, bool] = {}
## Клиент: имя, с которым регистрируемся.
var _local_name: String = ""


func _ready() -> void:
	# Клиенты общаются только с сервером и не знают друг о друге.
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_server(port: int = DEFAULT_PORT) -> Error:
	if status != Status.OFFLINE:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS + SPARE_CONNECTIONS)
	if error != OK:
		return error
	_session += 1
	multiplayer.multiplayer_peer = peer
	status = Status.SERVER
	return OK


func join_server(address: String, port: int, player_name: String) -> Error:
	if status != Status.OFFLINE:
		return ERR_ALREADY_IN_USE
	if address.strip_edges().is_empty() or port < CmdArgs.MIN_PORT or port > CmdArgs.MAX_PORT:
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address.strip_edges(), port)
	if error != OK:
		return error
	_session += 1
	_local_name = PlayerName.sanitize(player_name)
	multiplayer.multiplayer_peer = peer
	status = Status.CONNECTING
	_watch_connect_timeout(_session)
	return OK


## Закрывает сессию. Клиент в лобби получит disconnected(""), подключающийся — connection_failed("").
func leave() -> void:
	match status:
		Status.CONNECTING, Status.JOINED:
			_end_client_session("")
		Status.SERVER:
			_close_session()


func is_server() -> bool:
	return status == Status.SERVER


func is_joined() -> bool:
	return status == Status.JOINED


func local_id() -> int:
	return 0 if status == Status.OFFLINE else multiplayer.get_unique_id()


func is_host(peer_id: int) -> bool:
	return host_id != 0 and peer_id == host_id


func is_local_host() -> bool:
	return is_joined() and host_id == local_id()


func get_player_name(peer_id: int) -> String:
	return players[peer_id] if players.has(peer_id) else ""


## Номер цвета игрока из PlayerPalette, -1 если игрок неизвестен.
func get_player_color(peer_id: int) -> int:
	return player_colors[peer_id] if player_colors.has(peer_id) else -1


## Сервер: можно ли сейчас отправлять этому пиру. Пир, который отключился в этом же
## опросе сети, ещё числится подключённым, но отправка ему даёт ошибку движка.
func is_peer_reachable(peer_id: int) -> bool:
	if not is_server() or not multiplayer.get_peers().has(peer_id):
		return false
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	return enet.get_peer(peer_id).get_state() == ENetPacketPeer.STATE_CONNECTED


# --- Сервер ---


func _on_peer_connected(peer_id: int) -> void:
	if not is_server():
		return
	_unregistered[peer_id] = true
	_watch_registration(peer_id, _session)


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_server():
		return
	_unregistered.erase(peer_id)
	if not players.has(peer_id):
		return
	players.erase(peer_id)
	player_colors.erase(peer_id)
	if host_id == peer_id:
		host_id = _first_player_id()
	_send_lobby_to_players()
	player_left.emit(peer_id)
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, protocol_version: int) -> void:
	if not is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	# Уже зарегистрированных, кикнутых и неизвестных игнорируем.
	if not _unregistered.has(sender):
		return
	if protocol_version != PROTOCOL_VERSION:
		_kick(sender, REASON_VERSION_MISMATCH)
		return
	if players.size() >= MAX_PLAYERS:
		_kick(sender, REASON_SERVER_FULL)
		return
	_unregistered.erase(sender)
	var clean_name: String = PlayerName.sanitize(player_name.left(MAX_RAW_NAME_LENGTH))
	players[sender] = PlayerName.make_unique(clean_name, PackedStringArray(players.values()))
	player_colors[sender] = _first_free_color()
	if host_id == 0:
		host_id = sender
	# Сначала список: новичок должен стать JOINED раньше, чем получит что-то ещё от сервера.
	_send_lobby_to_players()
	player_joined.emit(sender)
	lobby_changed.emit()


## Только зарегистрированным: остальные пиры о лобби знать не должны.
func _send_lobby_to_players() -> void:
	for peer_id: int in players:
		if is_peer_reachable(peer_id):
			_lobby_snapshot.rpc_id(peer_id, players, player_colors, host_id)


func _first_free_color() -> int:
	var taken: Array = player_colors.values()
	for slot: int in PlayerPalette.COLORS.size():
		if not taken.has(slot):
			return slot
	return 0


func _first_player_id() -> int:
	for peer_id: int in players:
		return peer_id
	return 0


func _watch_registration(peer_id: int, session: int) -> void:
	await get_tree().create_timer(REGISTER_TIMEOUT_SEC).timeout
	if session == _session and _unregistered.has(peer_id):
		_kick(peer_id, REASON_NOT_REGISTERED)


## Сообщает пиру причину и рвёт соединение.
func _kick(peer_id: int, reason: String) -> void:
	_unregistered.erase(peer_id)
	if not is_peer_reachable(peer_id):
		return
	_kicked.rpc_id(peer_id, reason)
	# Разрыв только после доставки: обычный disconnect_peer() обгоняет RPC, и причина теряется.
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	enet.get_peer(peer_id).peer_disconnect_later()


# --- Клиент ---


func _on_connected_to_server() -> void:
	if status == Status.CONNECTING:
		_register.rpc_id(SERVER_ID, _local_name, PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	if status == Status.CONNECTING:
		_end_client_session(REASON_CONNECT_FAILED)


func _on_server_disconnected() -> void:
	if status == Status.JOINED:
		_end_client_session(REASON_CONNECTION_LOST)
	elif status == Status.CONNECTING:
		_end_client_session(REASON_CONNECT_FAILED)


func _watch_connect_timeout(session: int) -> void:
	await get_tree().create_timer(CONNECT_TIMEOUT_SEC).timeout
	if session == _session and status == Status.CONNECTING:
		_end_client_session(REASON_NO_RESPONSE)


@rpc("authority", "call_remote", "reliable")
func _lobby_snapshot(names: Dictionary, colors: Dictionary, new_host_id: int) -> void:
	if status != Status.CONNECTING and status != Status.JOINED:
		return
	# Через RPC словарь приходит нетипизированным: собираем заново с проверкой.
	var new_players: Dictionary[int, String] = {}
	for key: Variant in names:
		var value: Variant = names[key]
		if not (key is int and value is String):
			return
		new_players[key as int] = value as String
	var new_colors: Dictionary[int, int] = {}
	for key: Variant in colors:
		var slot: Variant = colors[key]
		if not (key is int and slot is int) or not new_players.has(key as int):
			return
		new_colors[key as int] = slot as int
	if new_players.size() > MAX_PLAYERS or not new_players.has(local_id()) or not new_players.has(new_host_id):
		return
	var old_players: Dictionary[int, String] = players
	var is_first: bool = status == Status.CONNECTING
	players = new_players
	player_colors = new_colors
	host_id = new_host_id
	status = Status.JOINED
	for peer_id: int in old_players:
		if not new_players.has(peer_id):
			player_left.emit(peer_id)
	for peer_id: int in new_players:
		if not old_players.has(peer_id):
			player_joined.emit(peer_id)
	if is_first:
		connected.emit()
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _kicked(reason: String) -> void:
	if status != Status.CONNECTING and status != Status.JOINED:
		return
	if reason.is_empty():
		reason = REASON_CONNECTION_LOST if status == Status.JOINED else REASON_CONNECT_FAILED
	_end_client_session(reason)


func _end_client_session(reason: String) -> void:
	var was_joined: bool = status == Status.JOINED
	_close_session()
	if was_joined:
		disconnected.emit(reason)
	else:
		connection_failed.emit(reason)


# --- Общее ---


func _close_session() -> void:
	_session += 1
	status = Status.OFFLINE
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	player_colors = {}
	host_id = 0
	_unregistered.clear()
	lobby_changed.emit()
