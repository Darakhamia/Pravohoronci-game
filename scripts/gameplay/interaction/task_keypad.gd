class_name TaskKeypad
extends TaskStation
## Задание «код»: игрок нажимает E, сервер придумывает ему код и присылает лично
## (Game.tasks.task_opened с данными {"code": "4821"}), игрок вводит его на экране и
## отправляет через Game.tasks.request_answer(). Сервер сверяет: тот же игрок, жив, рядом,
## код совпал. Ошибся — пробует ещё раз с тем же кодом.

## Ключ кода в данных задания.
const CODE_KEY: String = "code"
## Сколько цифр в коде.
const CODE_LENGTH: int = 4
## Цифры кода — от 0 до DIGITS - 1.
const DIGITS: int = 10

## Сервер: peer_id -> код, выданный этому игроку на этой станции.
var _codes: Dictionary[int, String] = {}
## Сервер: peer_id -> id объекта аватара, открывшего станцию (по нему проверяем, что игрок
## рядом). Храним id, а не узел: аватар вышедшего игрока удаляется.
var _opener_ids: Dictionary[int, int] = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	if Net.is_server():
		Game.tasks.answer_received.connect(_on_answer_received)


## Сервер: игрок открыл терминал — выдаём ему код (повторно — тот же).
func server_interact(player: Player) -> void:
	var peer_id: int = player.peer_id
	if not _codes.has(peer_id):
		_codes[peer_id] = make_code(_rng)
	_opener_ids[peer_id] = player.get_instance_id()
	Game.tasks.server_open(peer_id, interact_id, {CODE_KEY: _codes[peer_id]})


## Случайный код из CODE_LENGTH цифр, ведущие нули сохраняются: "0482".
static func make_code(rng: RandomNumberGenerator) -> String:
	var code: String = ""
	for index: int in CODE_LENGTH:
		code += str(rng.randi_range(0, DIGITS - 1))
	return code


## Сервер: игрок прислал введённый код.
func _on_answer_received(peer_id: int, station_id: int, answer: String) -> void:
	if station_id != interact_id or not _codes.has(peer_id):
		return
	var player: Player = instance_from_id(_opener_ids[peer_id]) as Player
	# Аватар мог исчезнуть (игрок вышел), а задание — уже не ждать этого игрока.
	if player == null or not can_interact(player):
		return
	if _server_is_in_reach(player) and answer == _codes[peer_id]:
		_codes.erase(peer_id)
		_opener_ids.erase(peer_id)
		_server_succeed(player)
	else:
		_server_fail(player)
