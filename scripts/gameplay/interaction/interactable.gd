class_name Interactable
extends Node3D
## Предмет, с которым игрок взаимодействует клавишей E: станция задания, кнопка, стойка
## с оружием, тело. Физики у предмета нет: игрок должен стоять рядом и смотреть в его сторону.
## Клиент показывает подсказку, сервер проверяет дальность и видимость (PlayerInteractor)
## и вызывает server_interact(). Наследник переопределяет can_interact() и server_*().
##
## Номер interact_id выдаёт карта: по нему клиент называет предмет серверу. Общее для всех
## состояние предмета — одно число state: его меняет сервер, клиентам рассылает World.
## В _ready() состояние не меняй: начальное у всех равно 0.

## Все пиры: изменилось state.
signal state_changed(new_state: int)

## interact_id предмета, которого нет: карта выдаёт номера с 1, тела игроков — минус peer_id.
const NO_ID: int = 0

## Текст подсказки после клавиши: «Починить проводку».
@export var prompt: String = ""
## Сколько секунд держать E. 0 — срабатывает по нажатию.
@export_range(0.0, 30.0, 0.1) var hold_seconds: float = 0.0
## С какого расстояния (от глаз игрока до точки предмета) можно пользоваться.
@export_range(0.5, 6.0, 0.1) var interact_range: float = 2.5
## Точка, на которую смотрит игрок, в координатах предмета.
@export var focus_offset: Vector3 = Vector3.ZERO

var interact_id: int = NO_ID
## Общее состояние предмета; смысл числа задаёт наследник.
var state: int = 0


func get_focus_position() -> Vector3:
	return to_global(focus_offset)


## Текст подсказки для этого игрока.
func get_prompt(_player: Player) -> String:
	return prompt


## Может ли игрок сейчас пользоваться предметом. Вызывается и на сервере (про любого
## игрока), и на клиенте (про своего — чтобы показать подсказку), поэтому опирается
## только на то, что известно обоим.
func can_interact(_player: Player) -> bool:
	return true


## Сервер: игрок нажал E (hold_seconds == 0) или додержал до конца.
func server_interact(_player: Player) -> void:
	pass


## Сервер: игрок отпустил E или отошёл раньше времени; held_seconds — сколько держал.
func server_release(_player: Player, _held_seconds: float) -> void:
	pass


## Сервер: сменить общее состояние; клиенты получат его через World.
func server_set_state(value: int) -> void:
	if Net.is_server():
		_set_state(value)


## Клиент: состояние пришло с сервера. Вызывает World.
func apply_state(value: int) -> void:
	if not Net.is_server():
		_set_state(value)


## Все пиры: state изменилось — наследник обновляет здесь внешний вид.
func _on_state_changed() -> void:
	pass


func _set_state(value: int) -> void:
	if value == state:
		return
	state = value
	_on_state_changed()
	state_changed.emit(state)
