class_name TaskFuelDock
extends TaskStation
## Задание «доставка»: принести канистру со стеллажа (CanisterRack) и удержать E у порта.
## Без канистры в руках портом пользоваться нельзя.

## Груз, который нужно принести.
const CANISTER: ItemConfig = preload("res://resources/items/canister.tres")
## Группа всех портов карты: по ней стеллаж узнаёт, кому нужна канистра.
const GROUP: StringName = &"task_fuel_docks"


func _enter_tree() -> void:
	add_to_group(GROUP)


## Портом пользуется тот, у кого доставка не сделана и канистра в руках. Работает и на
## клиенте про своего игрока: предмет в руках виден всем, а свой список клиент знает.
func can_interact(player: Player) -> bool:
	return super.can_interact(player) and player.weapons.is_carrying(CANISTER)


## Сервер: игрок додержал E с канистрой в руках — забираем её и засчитываем задание.
func server_interact(player: Player) -> void:
	if not player.weapons.is_carrying(CANISTER):
		return
	player.weapons.server_take_carried()
	_server_succeed(player)
