class_name DedicatedServer
extends Node
## Выделенный сервер: Main добавляет этот узел при запуске с флагом --server.
## Параметры: --port=<порт>, --min-players=<число>.
## Для отладки и тестов:
##   --traitors=<число>          сколько предателей раздать (по умолчанию — по правилам);
##   --traitor-name=<имя>        сделать этого игрока предателем (можно несколько раз);
##   --map=<имя>                 карта вместо основной: имя файла сцены без расширения;
##   --set=<свойство>=<значение> переопределить число или флаг из game_config.tres
##                               (можно несколько раз), например --set=role_reveal_seconds=0;
##   --director=<путь к .gd>     добавить на сервер узел-помощник теста: скрипт наследует
##                               Node и сам вызывает серверные методы игры.

## Серверу без окна незачем крутить кадры быстрее физики.
const MAX_FPS: int = 60


func _ready() -> void:
	Engine.max_fps = MAX_FPS
	var port: int = CmdArgs.get_int("--port", Net.DEFAULT_PORT, CmdArgs.MIN_PORT, CmdArgs.MAX_PORT)
	Game.min_players = CmdArgs.get_int("--min-players", Game.config.min_players, 1, Net.MAX_PLAYERS)
	if not _apply_debug_flags():
		get_tree().quit(1)
		return
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Game.state_changed.connect(_on_state_changed)
	Game.round_started.connect(_on_round_started)
	Game.match_ended.connect(_on_match_ended)
	var error: Error = Net.start_server(port)
	if error != OK:
		push_error("[server] не удалось открыть порт %d: %s" % [port, error_string(error)])
		get_tree().quit(1)
		return
	if not _add_director():
		get_tree().quit(1)
		return
	# Тесты ждут именно эту строку.
	print("[server] ready port=%d min_players=%d protocol=%d" % [port, Game.min_players, Net.PROTOCOL_VERSION])


## false — в флагах ошибка: сервер с неверными настройками лучше не запускать.
func _apply_debug_flags() -> bool:
	Game.debug_traitor_count = CmdArgs.get_int("--traitors", Game.TRAITORS_BY_RULES, 0, Net.MAX_PLAYERS)
	Game.debug_traitor_names = CmdArgs.get_values("--traitor-name")
	var map_name: String = CmdArgs.get_value("--map")
	if not map_name.is_empty():
		if World.find_map_by_name(map_name).is_empty():
			push_error("[server] --map: нет карты \"%s\"" % map_name)
			return false
		Game.debug_map_name = map_name
	for setting: String in CmdArgs.get_values("--set"):
		var separator: int = setting.find("=")
		var property: String = setting.left(separator) if separator != -1 else setting
		var value: String = setting.substr(separator + 1) if separator != -1 else ""
		if not Game.config.override_from_text(property, value):
			push_error("[server] --set: не удалось задать \"%s\"" % setting)
			return false
		print("[server] config %s=%s" % [property, value])
	return true


## false — скрипт помощника не загрузился.
func _add_director() -> bool:
	var path: String = CmdArgs.get_value("--director")
	if path.is_empty():
		return true
	var script: GDScript = load(path) as GDScript if ResourceLoader.exists(path) else null
	var director: Node = null
	if script != null and script.can_instantiate():
		director = script.new() as Node
	if director == null:
		push_error("[server] --director: не удалось загрузить узел из \"%s\"" % path)
		return false
	director.name = &"Director"
	add_child(director)
	print("[server] director %s" % path)
	return true


func _on_player_joined(peer_id: int) -> void:
	print("[server] player joined id=%d name=\"%s\" players=%d" % [peer_id, Net.get_player_name(peer_id), Net.players.size()])


func _on_player_left(peer_id: int) -> void:
	print("[server] player left id=%d players=%d" % [peer_id, Net.players.size()])


func _on_state_changed(new_state: Game.State) -> void:
	if new_state == Game.State.MATCH:
		print("[server] match started players=%d" % Net.players.size())
	else:
		print("[server] match ended")


func _on_round_started() -> void:
	var traitors: int = 0
	for peer_id: int in Game.participants:
		if Game.get_role(peer_id) == Game.Role.TRAITOR:
			traitors += 1
	print("[server] round started players=%d traitors=%d" % [Game.participants.size(), traitors])


func _on_match_ended(result: MatchResult) -> void:
	print("[server] match result winner=%s reason=%s" % [
			Game.Winner.find_key(result.winner), Game.EndReason.find_key(result.reason)])
