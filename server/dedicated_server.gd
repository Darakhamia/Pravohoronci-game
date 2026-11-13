class_name DedicatedServer
extends Node
## Выделенный сервер: Main добавляет этот узел при запуске с флагом --server.
## Параметры: --port=<порт>, --min-players=<число>.

## Серверу без окна незачем крутить кадры быстрее физики.
const MAX_FPS: int = 60


func _ready() -> void:
	Engine.max_fps = MAX_FPS
	var port: int = CmdArgs.get_int("--port", Net.DEFAULT_PORT, CmdArgs.MIN_PORT, CmdArgs.MAX_PORT)
	Game.min_players = CmdArgs.get_int("--min-players", Game.CONFIG.min_players, 1, Net.MAX_PLAYERS)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Game.state_changed.connect(_on_state_changed)
	var error: Error = Net.start_server(port)
	if error != OK:
		push_error("[server] не удалось открыть порт %d: %s" % [port, error_string(error)])
		get_tree().quit(1)
		return
	# Тесты ждут именно эту строку.
	print("[server] ready port=%d min_players=%d protocol=%d" % [port, Game.min_players, Net.PROTOCOL_VERSION])


func _on_player_joined(peer_id: int) -> void:
	print("[server] player joined id=%d name=\"%s\" players=%d" % [peer_id, Net.get_player_name(peer_id), Net.players.size()])


func _on_player_left(peer_id: int) -> void:
	print("[server] player left id=%d players=%d" % [peer_id, Net.players.size()])


func _on_state_changed(new_state: Game.State) -> void:
	if new_state == Game.State.MATCH:
		print("[server] match started players=%d" % Net.players.size())
	else:
		print("[server] match ended")
