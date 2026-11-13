class_name TaskBoard
extends Node
## Задания экипажа (узел Game.tasks, есть на каждом пире).
## У каждого участника свой список станций. Общий прогресс виден всем, личный список —
## только хозяину. Задания предателей — фальшивые: выглядят так же, но в прогресс не идут.
## Станции карта сообщает сама (server_register_stations), о сценах TaskBoard не знает.

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

## Общий прогресс экипажа: сколько заданий сделано и сколько нужно.
var done_count: int = 0
var total_count: int = 0


## Все задания экипажа сделаны. Без заданий (карта без станций) победы по ним нет.
func is_all_done() -> bool:
	return total_count > 0 and done_count >= total_count


## Сервер: карта сообщает id своих станций заданий (до начала раунда).
func server_register_stations(_station_ids: PackedInt32Array) -> void:
	pass


## Сервер: ждёт ли это задание этого игрока. Клиент: то же, но только про себя.
func is_pending(_peer_id: int, _station_id: int) -> bool:
	return false


## Клиент: наш список — id станций в порядке выдачи.
func get_local_tasks() -> PackedInt32Array:
	return PackedInt32Array()


## Клиент: сделано ли наше задание на этой станции.
func is_local_done(_station_id: int) -> bool:
	return false


## Сервер: игрок выполнил задание на станции. Чужое или уже сделанное задание — ничего.
func server_complete(_peer_id: int, _station_id: int) -> void:
	pass


## Клиент: отправить серверу ответ на открытое задание (например, введённый код).
func request_answer(_station_id: int, _answer: String) -> void:
	pass


## Сервер: открыть игроку задание с данными (придёт ему сигналом task_opened).
func server_open(_peer_id: int, _station_id: int, _data: Dictionary) -> void:
	pass


## Сервер: сообщить игроку исход попытки (придёт ему сигналом task_feedback).
func server_send_feedback(_peer_id: int, _station_id: int, _success: bool) -> void:
	pass
