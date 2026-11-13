extends Node
## Состояние матча. Решает сервер, клиенты получают копию через _sync_state.
## О сценах Game ничего не знает: на state_changed реагирует World.

signal state_changed(new_state: State)
signal min_players_changed(value: int)

enum State { LOBBY, MATCH }

const CONFIG: GameConfig = preload("res://resources/game_config.tres")

var state: State = State.LOBBY
## Сервер: действующий минимум игроков для старта. Клиенты: копия с сервера.
var min_players: int = CONFIG.min_players:
	set(value):
		var clamped: int = clampi(value, 1, Net.MAX_PLAYERS)
		if clamped == min_players:
			return
		min_players = clamped
		min_players_changed.emit(min_players)
		_send_state_to_players()


func _ready() -> void:
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.disconnected.connect(_on_session_ended)
	Net.connection_failed.connect(_on_session_ended)


func can_start_match() -> bool:
	return state == State.LOBBY and Net.players.size() >= min_players


## Клиент просит сервер начать матч. Сервер выполнит просьбу только от хоста.
func request_start_match() -> void:
	if Net.is_joined():
		_request_start_match.rpc_id(Net.SERVER_ID)


## Временный инструмент хоста, пока нет условий победы.
func request_end_match() -> void:
	if Net.is_joined():
		_request_end_match.rpc_id(Net.SERVER_ID)


## Только сервер. false, если начать нельзя.
func start_match() -> bool:
	if not Net.is_server() or not can_start_match():
		return false
	_set_state(State.MATCH)
	return true


## Только сервер.
func end_match() -> void:
	if Net.is_server():
		_set_state(State.LOBBY)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)
	_send_state_to_players()


func _send_state_to_players() -> void:
	if not Net.is_server():
		return
	for peer_id: int in Net.players:
		_sync_state.rpc_id(peer_id, state, min_players)


func _on_player_joined(peer_id: int) -> void:
	if Net.is_server():
		_sync_state.rpc_id(peer_id, state, min_players)


func _on_player_left(_peer_id: int) -> void:
	# Матч без игроков не нужен: возвращаемся в лобби и ждём новых.
	if Net.is_server() and Net.players.is_empty():
		end_match()


func _on_session_ended(_reason: String) -> void:
	min_players = CONFIG.min_players
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
