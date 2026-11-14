class_name TaskStation
extends Interactable
## Станция задания на карте. Виды заданий и их проверка — в наследниках (TaskWiring,
## TaskKeypad, TaskCalibrator, TaskFuelDock) и в Game.tasks; карта сообщает TaskBoard
## номера всех станций.
## На клиенте над станцией, которая ждёт своего игрока, горит метка (узел Marker, если
## он есть в сцене). Другие игроки её не видят: личный список знает только хозяин.

## Название задания в списке игрока: «Починить проводку».
@export var title: String = ""
## Где находится станция — показывается рядом с названием: «Реактор».
@export var location: String = ""

## Метка «это твоё задание»; null, если её нет в сцене.
@onready var _marker: Node3D = get_node_or_null(^"Marker") as Node3D


func _ready() -> void:
	if _marker == null:
		return
	_marker.visible = false
	if Net.is_server():
		return
	Game.tasks.local_tasks_changed.connect(_update_marker)
	# Номер станции карта выдаёт после _ready своих детей.
	_update_marker.call_deferred()


## Пользоваться станцией может только тот, у кого это задание ещё не сделано.
func can_interact(player: Player) -> bool:
	return Game.tasks.is_pending(player.peer_id, interact_id)


## Подсказка под прицелом: действие станции или, если игроку для задания чего-то не
## хватает, — чего именно.
func get_prompt(player: Player) -> String:
	var hint: String = get_missing_hint(player)
	return prompt if hint.is_empty() else hint


## Чего этому игроку не хватает, чтобы выполнить задание прямо сейчас («Нужна канистра со
## склада»); пустая строка — всего хватает. Пока чего-то не хватает, станция всё равно
## попадает под прицел, но HUD показывает это объяснение вместо клавиши с действием, а
## нажатие E ничего не даёт: сервер такую попытку не засчитывает (server_interact
## наследника). Вызывается на сервере и на клиенте (про своего игрока), поэтому опирается
## только на то, что известно обоим.
func get_missing_hint(_player: Player) -> String:
	return ""


## Клиент: горит ли над станцией метка задания своего игрока.
func is_marked() -> bool:
	return _marker != null and _marker.visible


## Сервер: игрок выполнил задание на этой станции — засчитать и сообщить ему об успехе.
func _server_succeed(player: Player) -> void:
	if not Game.tasks.is_pending(player.peer_id, interact_id):
		return
	Game.tasks.server_complete(player.peer_id, interact_id)
	if not Game.tasks.is_pending(player.peer_id, interact_id):
		Game.tasks.server_send_feedback(player.peer_id, interact_id, true)


## Сервер: попытка не удалась — задание остаётся, игрок пробует ещё раз.
func _server_fail(player: Player) -> void:
	Game.tasks.server_send_feedback(player.peer_id, interact_id, false)


## Сервер: игрок жив, идёт игра, и он стоит достаточно близко к станции. Нужно там, где
## попытку завершает не PlayerInteractor (ответ с клавиатуры, отпущенная клавиша).
func _server_is_in_reach(player: Player) -> bool:
	if player.life != Player.Life.ALIVE or not Game.is_playing():
		return false
	var distance: float = player.get_eye_position().distance_to(get_focus_position())
	return distance <= interact_range + PlayerInteractor.RANGE_TOLERANCE


## Клиент: показать или спрятать метку. Вызывается при каждом изменении своего списка.
func _update_marker() -> void:
	_marker.visible = _is_marker_needed()


## Клиент: нужна ли сейчас метка над станцией — пока задание ждёт своего игрока.
## Наследник может сузить условие (порт доставки отмечен, только когда канистра в руках).
func _is_marker_needed() -> bool:
	return Game.tasks.is_pending(Net.local_id(), interact_id)
