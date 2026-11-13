extends Node
## Бот-клиент для дымового теста (его запускает tests/smoke/run_smoke.sh):
##   godot --headless res://tests/smoke/smoke_client.tscn -- --port=<порт> --name=<ник> --players=2
## Проходит путь игрока: лобби -> матч -> движение и прыжок по очереди -> конец матча -> выход.
## Игрой управляет только через публичные API и Input.action_press(), как живой клиент.
## Успех: строка "SMOKE OK <ник>" и код выхода 0. Провал: "SMOKE FAIL <ник>: <что>" и код 1.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const SERVER_ADDRESS: String = "127.0.0.1"
const DEFAULT_NAME: String = "Bot"
const DEFAULT_PLAYERS: int = 2
## Без окна кадры ничем не ограничены: держим их на частоте физики.
const MAX_FPS: int = 60
const MSEC_PER_SEC: float = 1000.0

## Запас сверх очередей ботов на запуск, лобби и выход.
const HARD_DEADLINE_BASE_SEC: float = 30.0
const CONNECT_DEADLINE_SEC: float = 10.0
const LOBBY_DEADLINE_SEC: float = 15.0
const MATCH_DEADLINE_SEC: float = 10.0
## MATCH приходит ботам одновременно, дальше все идут по общему расписанию от этого момента.
## Первая очередь начинается через столько секунд: к этому времени аватары обязаны появиться.
const FIRST_TURN_AFTER_SEC: float = 2.0
## Очередь одного бота: идёт вперёд, останавливается, прыгает. Остальные стоят и смотрят.
const TURN_SEC: float = 3.2
const MOVE_HOLD_SEC: float = 1.2
## Пауза после ходьбы: аватар должен остановиться, а его позиция — дойти до всех клиентов.
const SETTLE_SEC: float = 0.5
const JUMP_WATCH_SEC: float = 1.0
const MIN_MOVE_DISTANCE: float = 1.0
const MIN_JUMP_HEIGHT: float = 0.3
## Аватар бота, который сейчас не ходит, должен остаться на месте.
const MAX_IDLE_MOVE_DISTANCE: float = 0.3
const MAX_IDLE_JUMP_HEIGHT: float = 0.1
const END_DEADLINE_SEC: float = 12.0
## С запасом на случай, когда сервер замечает пропажу соседнего бота только по тайм-ауту ENet.
const LEAVE_DEADLINE_SEC: float = 10.0

var _bot_name: String = DEFAULT_NAME
var _expected_players: int = DEFAULT_PLAYERS
var _world: World = null
var _finished: bool = false
## Чьи аватары были на карте в начале матча.
var _avatar_ids: Array[int] = []
## Пока true, пропажа карты или любого из этих аватаров — провал.
var _avatars_required: bool = false


func _ready() -> void:
	Engine.max_fps = MAX_FPS
	_bot_name = CmdArgs.get_value("--name", DEFAULT_NAME)
	_expected_players = CmdArgs.get_int("--players", DEFAULT_PLAYERS, 1, Net.MAX_PLAYERS)
	var hard_deadline_sec: float = HARD_DEADLINE_BASE_SEC + _expected_players * TURN_SEC
	get_tree().create_timer(hard_deadline_sec).timeout.connect(
			_fail.bind("весь прогон не уложился в %d с" % int(hard_deadline_sec)))
	Net.connection_failed.connect(_on_session_lost)
	Net.disconnected.connect(_on_session_lost)
	# Корень дерева ещё собирает детей: добавить к нему Main можно только отложенно.
	_run.call_deferred()


func _run() -> void:
	var main_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		_fail("не загрузилась сцена %s" % MAIN_SCENE_PATH)
		return
	# Main должен лежать в /root/Main, как на сервере: пути реплицируемых узлов обязаны совпасть.
	var main: Node = main_scene.instantiate()
	get_tree().root.add_child(main)
	_world = main.get_node_or_null(^"World") as World
	if _world == null:
		_fail("в сцене Main нет узла World")
		return

	var port: int = CmdArgs.get_int("--port", Net.DEFAULT_PORT, CmdArgs.MIN_PORT, CmdArgs.MAX_PORT)
	_step("1: подключаемся к %s:%d" % [SERVER_ADDRESS, port])
	var error: Error = Net.join_server(SERVER_ADDRESS, port, _bot_name)
	if error != OK:
		_fail("Net.join_server вернул %s" % error_string(error))
		return
	if not await _wait_until(Net.is_joined, CONNECT_DEADLINE_SEC):
		_fail("сервер не пустил в лобби за %d с" % int(CONNECT_DEADLINE_SEC))
		return

	_step("2: ждём %d игроков в лобби и начало матча" % _expected_players)
	if not await _wait_until(_is_lobby_full, LOBBY_DEADLINE_SEC):
		_fail("в лобби %d игроков из %d" % [Net.players.size(), _expected_players])
		return
	if Net.is_local_host():
		if not await _wait_until(Game.can_start_match, MATCH_DEADLINE_SEC):
			_fail("хост не может начать матч: игроков %d, минимум %d" % [Net.players.size(), Game.min_players])
			return
		_step("2: мы хост, просим сервер начать матч")
		Game.request_start_match()
	if not await _wait_until(_is_in_match, MATCH_DEADLINE_SEC):
		_fail("матч не начался за %d с" % int(MATCH_DEADLINE_SEC))
		return
	var match_started_msec: int = Time.get_ticks_msec()

	_step("3: ждём карту и аватары всех игроков")
	if not await _wait_until(_are_avatars_spawned, FIRST_TURN_AFTER_SEC):
		_fail("на карте нет аватаров всех игроков из лобби")
		return
	_avatar_ids.assign(Net.players.keys())
	_avatars_required = true
	for id: int in _avatar_ids:
		var avatar: Player = _get_avatar(id)
		if avatar.is_local() != (id == Net.local_id()):
			_fail("is_local() аватара %d вернул %s" % [id, avatar.is_local()])
			return
		if avatar.display_name != Net.get_player_name(id):
			_fail("имя аватара %d \"%s\", а в лобби \"%s\"" % [id, avatar.display_name, Net.get_player_name(id)])
			return

	# Боты ходят и прыгают по очереди в порядке входа в лобби. Аватар того, чья очередь,
	# обязан сдвинуться и подпрыгнуть на каждом клиенте, остальные — остаться на месте:
	# это проверяет путь ввод -> сервер -> все клиенты и то, что ввод достаётся своему аватару.
	for turn: int in _avatar_ids.size():
		var turn_starts_sec: float = FIRST_TURN_AFTER_SEC + turn * TURN_SEC
		if not await _wait_seconds(turn_starts_sec - _seconds_since(match_started_msec)):
			return
		if not await _play_turn(turn, _avatar_ids[turn]):
			return

	_step("6: ждём конец матча")
	if Net.is_local_host():
		var match_length_sec: float = FIRST_TURN_AFTER_SEC + _avatar_ids.size() * TURN_SEC
		if not await _wait_seconds(match_length_sec - _seconds_since(match_started_msec)):
			return
		_step("6: мы хост, просим сервер завершить матч")
		Game.request_end_match()
	# Дальше карта и аватары должны пропасть (не хост не знает, когда именно).
	_avatars_required = false
	if not await _wait_until(_is_back_in_lobby, END_DEADLINE_SEC):
		_fail("матч не закончился: состояние %s, карта %s" % [
				Game.State.find_key(Game.state), "осталась" if _world.current_map != null else "убрана"])
		return

	# Выходим по одному, начиная с последнего вошедшего: тест не должен зависеть от того,
	# в каком порядке сервер обработает одновременные отключения.
	_step("7: ждём своей очереди и выходим")
	if not await _wait_until(_is_last_in_lobby, LEAVE_DEADLINE_SEC):
		_fail("игроки, вошедшие позже, не вышли из лобби: осталось %d" % Net.players.size())
		return
	_finished = true
	Net.leave()
	print("SMOKE OK %s" % _bot_name)
	get_tree().quit(0)


## Одна очередь: бот walker_id идёт вперёд и прыгает, остальные стоят. false — провал.
func _play_turn(turn: int, walker_id: int) -> bool:
	var is_my_turn: bool = walker_id == Net.local_id()
	var walker_name: String = Net.get_player_name(walker_id)
	_step("4.%d: %s идёт вперёд %.1f с" % [turn + 1, "бот" if is_my_turn else walker_name, MOVE_HOLD_SEC])
	var start_positions: Dictionary[int, Vector3] = _get_avatar_positions()
	if is_my_turn:
		Input.action_press(&"move_forward")
	var held: bool = await _wait_seconds(MOVE_HOLD_SEC)
	if is_my_turn:
		Input.action_release(&"move_forward")
	if not held or not await _wait_seconds(SETTLE_SEC):
		return false
	for id: int in _avatar_ids:
		var offset: Vector3 = _get_avatar(id).position - start_positions[id]
		var distance: float = Vector2(offset.x, offset.z).length()
		if id == walker_id and distance < MIN_MOVE_DISTANCE:
			_fail("%s шёл вперёд, но его аватар сдвинулся только на %.2f м" % [walker_name, distance])
			return false
		if id != walker_id and distance > MAX_IDLE_MOVE_DISTANCE:
			_fail("шёл %s, а на %.2f м сдвинулся аватар %s" % [walker_name, distance, Net.get_player_name(id)])
			return false

	_step("5.%d: %s прыгает" % [turn + 1, "бот" if is_my_turn else walker_name])
	var ground: Dictionary[int, Vector3] = _get_avatar_positions()
	var rise: Dictionary[int, float] = {}
	for id: int in _avatar_ids:
		rise[id] = 0.0
	if is_my_turn:
		Input.action_press(&"jump")
	var watched: bool = await _wait_until(func() -> bool:
		for id: int in _avatar_ids:
			rise[id] = maxf(rise[id], _get_avatar(id).position.y - ground[id].y)
		return false, JUMP_WATCH_SEC)
	if is_my_turn:
		Input.action_release(&"jump")
	# _wait_until вернул false по времени — это норма; провал виден по _finished.
	if watched or _finished:
		return false
	for id: int in _avatar_ids:
		if id == walker_id and rise[id] < MIN_JUMP_HEIGHT:
			_fail("%s прыгал, но его аватар поднялся только на %.2f м" % [walker_name, rise[id]])
			return false
		if id != walker_id and rise[id] > MAX_IDLE_JUMP_HEIGHT:
			_fail("прыгал %s, а на %.2f м подпрыгнул аватар %s" % [walker_name, rise[id], Net.get_player_name(id)])
			return false
	return true


func _get_avatar_positions() -> Dictionary[int, Vector3]:
	var positions: Dictionary[int, Vector3] = {}
	for id: int in _avatar_ids:
		positions[id] = _get_avatar(id).position
	return positions


func _seconds_since(msec: int) -> float:
	return (Time.get_ticks_msec() - msec) / MSEC_PER_SEC


func _step(text: String) -> void:
	print("SMOKE %s: step %s" % [_bot_name, text])


func _fail(what: String) -> void:
	if _finished:
		return
	_finished = true
	print("SMOKE FAIL %s: %s" % [_bot_name, what])
	Net.leave()
	get_tree().quit(1)


## До шага 7 сессия сама закончиться не должна.
func _on_session_lost(reason: String) -> void:
	_fail("сессия оборвалась: %s" % reason)


## Проверяет условие каждый кадр. false — время вышло или прогон уже провален.
func _wait_until(condition: Callable, timeout_sec: float) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + int(timeout_sec * MSEC_PER_SEC)
	while not _finished:
		if _avatars_required and not _get_missing_avatars().is_empty():
			_fail("до конца матча пропали аватары: %s" % ", ".join(_get_missing_avatars()))
			break
		var is_met: bool = condition.call()
		if is_met:
			return true
		if Time.get_ticks_msec() >= deadline_msec:
			break
		await get_tree().process_frame
	return false


## Пауза, во время которой продолжают работать проверки из _wait_until. false — прогон провален.
func _wait_seconds(seconds: float) -> bool:
	await _wait_until(func() -> bool: return false, seconds)
	return not _finished


func _is_lobby_full() -> bool:
	return Net.players.size() >= _expected_players


func _is_in_match() -> bool:
	return Game.state == Game.State.MATCH


func _is_back_in_lobby() -> bool:
	return Game.state == Game.State.LOBBY and _world.current_map == null


## Net.players хранит игроков в порядке входа.
func _is_last_in_lobby() -> bool:
	return not Net.players.is_empty() and Net.players.keys().back() == Net.local_id()


func _get_avatar(peer_id: int) -> Player:
	return _world.current_map.get_player(peer_id) if _world.current_map != null else null


func _are_avatars_spawned() -> bool:
	for id: int in Net.players:
		if _get_avatar(id) == null:
			return false
	return true


## Имена игроков, чьих аватаров на карте уже нет (все сразу, если пропала сама карта).
func _get_missing_avatars() -> PackedStringArray:
	var missing: PackedStringArray = []
	for id: int in _avatar_ids:
		if _get_avatar(id) == null:
			missing.append(Net.get_player_name(id) if Net.players.has(id) else "игрок %d (вышел)" % id)
	return missing
