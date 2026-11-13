class_name TaskFuelDock
extends TaskStation
## Задание «доставка»: принести канистру со стеллажа (CanisterRack) и удержать E у порта.
## Без канистры порт всё равно попадает под прицел того, кого ждёт это задание, но вместо
## действия объясняет, чего не хватает (TEXT_NEEDS_CANISTER), а нажатие E ничего не даёт.
## Метка над портом на клиенте хозяина задания горит, только когда канистра уже в руках:
## до этого отмечен стеллаж.

## Груз, который нужно принести.
const CANISTER: ItemConfig = preload("res://resources/items/canister.tres")
## Группа всех портов карты: по ней стеллаж узнаёт, кому нужна канистра.
const GROUP: StringName = &"task_fuel_docks"
## Подсказка у порта, пока у игрока нет канистры.
const TEXT_NEEDS_CANISTER: String = "Нужна канистра со склада"

## Клиент: руки своего игрока — от них зависит метка. На сервере null.
var _hands: TaskLocalHands = null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	super._ready()
	if _marker == null or Net.is_server():
		return
	_hands = TaskLocalHands.new(self)
	_hands.changed.connect(_update_marker)


## Без канистры в руках у порта делать нечего. Работает и на клиенте про своего игрока:
## предмет в руках виден всем.
func get_missing_hint(player: Player) -> String:
	return "" if player.weapons.is_carrying(CANISTER) else TEXT_NEEDS_CANISTER


## Сервер: игрок додержал E — если канистра у него в руках, забираем её и засчитываем
## задание. Без канистры ничего не происходит.
func server_interact(player: Player) -> void:
	if not player.weapons.is_carrying(CANISTER):
		return
	player.weapons.server_take_carried()
	_server_succeed(player)


## Клиент: порт отмечен, когда доставка ждёт своего игрока и канистра уже у него в руках.
func _is_marker_needed() -> bool:
	return super._is_marker_needed() and _hands != null and _hands.is_carrying(CANISTER)
