class_name ScenarioBot
extends Node
## База для ботов сценарных тестов. Бот — обычный клиент без окна: заходит в лобби,
## дожидается матча и дальше играет по сценарию из _run(). Игрой управляет только через
## публичные API и Input.action_press(), как живой клиент.
## Сценарий — файл tests/scenarios/<имя>.gd с классом-наследником и файл <имя>.cfg
## с настройками запуска (см. run_scenario.sh). Все боты сценария выполняют один и тот же
## скрипт и различают себя по номеру (bot_number) или по роли.
## Успех: строка "SCENARIO OK <сценарий> <ник>" и код выхода 0.
## Провал: "SCENARIO FAIL <сценарий> <ник>: <что>" и код 1.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const SERVER_ADDRESS: String = "127.0.0.1"
const DEFAULT_NAME: String = "Bot1"
## Без окна кадры ничем не ограничены: держим их на частоте физики.
const MAX_FPS: int = 60
const MSEC_PER_SEC: float = 1000.0
const DEFAULT_DEADLINE_SEC: int = 60
const CONNECT_DEADLINE_SEC: float = 10.0
const LOBBY_DEADLINE_SEC: float = 15.0
const MATCH_DEADLINE_SEC: float = 10.0
const AVATARS_DEADLINE_SEC: float = 5.0
## С запасом на случай, когда сервер замечает пропажу соседнего бота только по тайм-ауту ENet.
const LEAVE_DEADLINE_SEC: float = 15.0
## Сколько держать клавишу при коротком нажатии: игра опрашивает ввод раз в физический тик.
const TAP_SEC: float = 0.1

## Имя сценария (файл без расширения).
var scenario_name: String = ""
var bot_name: String = DEFAULT_NAME
## Номер бота из имени: Bot1 -> 1.
var bot_number: int = 1
var expected_players: int = 1
var world: World = null

var _finished: bool = false
var _is_leaving: bool = false
var _pressed_actions: Array[StringName] = []


func _ready() -> void:
	Engine.max_fps = MAX_FPS
	bot_name = CmdArgs.get_value("--name", DEFAULT_NAME)
	bot_number = maxi(bot_name.trim_prefix("Bot").to_int(), 1)
	expected_players = CmdArgs.get_int("--players", 1, 1, Net.MAX_PLAYERS)
	var deadline_sec: int = CmdArgs.get_int("--deadline", DEFAULT_DEADLINE_SEC, 1, 3600)
	get_tree().create_timer(deadline_sec).timeout.connect(
			fail.bind("весь прогон не уложился в %d с" % deadline_sec))
	Net.connection_failed.connect(_on_session_lost)
	Net.disconnected.connect(_on_session_lost)
	# Корень дерева ещё собирает детей: добавить к нему Main можно только отложенно.
	_boot.call_deferred()


## Сценарий бота. К этому моменту матч начался, а карта и аватары всех игроков на месте.
func _run() -> void:
	pass


# --- Что может бот ---


func step(text: String) -> void:
	print("SCENARIO %s %s: %s" % [scenario_name, bot_name, text])


## Провал сценария: бот выходит с кодом 1.
func fail(what: String) -> void:
	if _finished:
		return
	_finished = true
	print("SCENARIO FAIL %s %s: %s" % [scenario_name, bot_name, what])
	_release_all()
	Net.leave()
	get_tree().quit(1)


## Провал, если условие ложно. Возвращает само условие.
func check(condition: bool, what: String) -> bool:
	if not condition:
		fail(what)
	return condition and not _finished


## Проверяет условие каждый кадр. false — время вышло или прогон уже провален.
func wait_until(condition: Callable, timeout_sec: float) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + int(timeout_sec * MSEC_PER_SEC)
	while not _finished:
		var is_met: bool = condition.call()
		if is_met:
			return true
		if Time.get_ticks_msec() >= deadline_msec:
			break
		await get_tree().process_frame
	return false


## Как wait_until, но если условие не выполнилось вовремя — это провал с текстом what.
func expect(condition: Callable, timeout_sec: float, what: String) -> bool:
	if await wait_until(condition, timeout_sec):
		return true
	fail("%s (ждали %.1f с)" % [what, timeout_sec])
	return false


## Пауза. false — прогон провален.
func wait_seconds(seconds: float) -> bool:
	await wait_until(func() -> bool: return false, seconds)
	return not _finished


func map() -> GameMap:
	return world.current_map


## Свой аватар; null, если его нет.
func me() -> Player:
	return avatar(Net.local_id())


func avatar(peer_id: int) -> Player:
	return world.current_map.get_player(peer_id) if world.current_map != null else null


## peer_id игрока по имени; 0, если такого нет.
func peer_named(player_name: String) -> int:
	for peer_id: int in Net.players:
		if Net.players[peer_id] == player_name:
			return peer_id
	return 0


func avatar_named(player_name: String) -> Player:
	return avatar(peer_named(player_name))


## Повернуть взгляд на точку в мире (как если бы игрок довёл мышь).
func look_at_point(point: Vector3) -> void:
	var player: Player = me()
	if player == null:
		return
	var offset: Vector3 = point - player.get_eye_position()
	# Вперёд у игрока смотрит -Z.
	player.input.yaw = atan2(-offset.x, -offset.z)
	player.input.pitch = PlayerInput.sanitize_pitch(atan2(offset.y, Vector2(offset.x, offset.z).length()))


## Идти к точке по прямой, пока до неё не останется stop_distance (по горизонтали).
## false — не дошёл за timeout_sec.
func walk_to(point: Vector3, stop_distance: float, timeout_sec: float) -> bool:
	press(&"move_forward")
	var reached: bool = await wait_until(func() -> bool:
		var player: Player = me()
		if player == null:
			return false
		look_at_point(Vector3(point.x, player.get_eye_position().y, point.z))
		var offset: Vector3 = point - player.position
		return Vector2(offset.x, offset.z).length() <= stop_distance, timeout_sec)
	release(&"move_forward")
	return reached


func press(action: StringName) -> void:
	Input.action_press(action)
	if not _pressed_actions.has(action):
		_pressed_actions.append(action)


func release(action: StringName) -> void:
	Input.action_release(action)
	_pressed_actions.erase(action)


## Короткое нажатие.
func tap(action: StringName) -> void:
	await hold(action, TAP_SEC)


## Зажать клавишу на время.
func hold(action: StringName, seconds: float) -> void:
	press(action)
	await wait_seconds(seconds)
	release(action)


## Нажать и отпустить клавишу так, как это видит интерфейс: событием ввода, а не опросом
## (например, Esc закрывает панель, которая держит курсор и не даёт ходить).
func press_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


# --- Запуск и выход ---


func _boot() -> void:
	var main_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		fail("не загрузилась сцена %s" % MAIN_SCENE_PATH)
		return
	# Main должен лежать в /root/Main, как на сервере: пути реплицируемых узлов обязаны совпасть.
	var main: Node = main_scene.instantiate()
	get_tree().root.add_child(main)
	world = main.get_node_or_null(^"World") as World
	if world == null:
		fail("в сцене Main нет узла World")
		return
	var port: int = CmdArgs.get_int("--port", Net.DEFAULT_PORT, CmdArgs.MIN_PORT, CmdArgs.MAX_PORT)
	var error: Error = Net.join_server(SERVER_ADDRESS, port, bot_name)
	if error != OK:
		fail("Net.join_server вернул %s" % error_string(error))
		return
	if not await expect(Net.is_joined, CONNECT_DEADLINE_SEC, "сервер не пустил в лобби"):
		return
	if not await expect(func() -> bool: return Net.players.size() >= expected_players,
			LOBBY_DEADLINE_SEC, "в лобби не собралось %d игроков" % expected_players):
		return
	if Net.is_local_host():
		if not await expect(Game.can_start_match, MATCH_DEADLINE_SEC, "хост не может начать матч"):
			return
		Game.request_start_match()
	if not await expect(func() -> bool: return Game.state == Game.State.MATCH,
			MATCH_DEADLINE_SEC, "матч не начался"):
		return
	if not await expect(_are_avatars_spawned, AVATARS_DEADLINE_SEC, "на карте нет аватаров всех игроков"):
		return
	step("матч начался, выполняем сценарий")
	await _run()
	if _finished:
		return
	# Выходим по одному, начиная с последнего вошедшего: тест не должен зависеть от того,
	# в каком порядке сервер обработает одновременные отключения.
	_release_all()
	if not await expect(_is_last_in_lobby, LEAVE_DEADLINE_SEC, "игроки, вошедшие позже, не вышли"):
		return
	_finished = true
	_is_leaving = true
	Net.leave()
	print("SCENARIO OK %s %s" % [scenario_name, bot_name])
	get_tree().quit(0)


func _are_avatars_spawned() -> bool:
	if world.current_map == null:
		return false
	for peer_id: int in Net.players:
		if avatar(peer_id) == null:
			return false
	return true


## Net.players хранит игроков в порядке входа.
func _is_last_in_lobby() -> bool:
	return not Net.players.is_empty() and Net.players.keys().back() == Net.local_id()


func _release_all() -> void:
	for action: StringName in _pressed_actions.duplicate():
		release(action)


func _on_session_lost(reason: String) -> void:
	if not _is_leaving:
		fail("сессия оборвалась: %s" % reason)
