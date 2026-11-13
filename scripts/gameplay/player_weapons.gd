class_name PlayerWeapons
extends Node
## Оружие и предметы в руках игрока (узел Weapons внутри Player). Решает сервер.
## Всем видно только то, что игрок держит (Player.held_item — номер в наборе ITEMS).
## Что ещё у него есть и сколько патронов, знают сервер и хозяин аватара.

## Клиент-владелец: изменился набор оружия или патроны.
signal loadout_changed
## Сервер: игрок лишился груза, который нёс (бросил, сменил оружие, умер).
signal carried_lost(item: ItemConfig)

const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
## Номер пустых рук (кулаков) в наборе: они есть у каждого.
const EMPTY_HANDS: int = 0

## Сервер: груз в руках (канистра); null — груза нет.
var _carried: ItemConfig = null
## Сервер: что игрок держал до того, как взял груз.
var _held_before_carry: int = EMPTY_HANDS

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	if Net.is_server():
		_player.life_changed.connect(_on_life_changed)


## Все пиры: предмет, который игрок держит в руках.
func get_held_item() -> ItemConfig:
	return ITEMS.get_item(_player.held_item)


## Все пиры: несёт ли игрок этот груз.
func is_carrying(item: ItemConfig) -> bool:
	return item != null and get_held_item() == item


## Сервер и клиент-владелец: патроны оружия в руках; -1 — у него нет счётчика.
func get_ammo() -> int:
	return -1


## Сервер и клиент-владелец: есть ли на что переключиться.
func can_switch() -> bool:
	return false


## Сервер: начало раунда — кулаки всем, нож предателю.
func server_reset(_role: Game.Role) -> void:
	if not Net.is_server():
		return
	_carried = null
	_held_before_carry = EMPTY_HANDS
	_player.held_item = EMPTY_HANDS


## Сервер: клиент нажал атаку; углы взгляда уже очищены. Сама атака — в физическом тике.
## Пока игрок несёт груз, атаковать нельзя.
func server_fire(_yaw: float, _pitch: float) -> void:
	pass


## Сервер: клиент нажал смену оружия. Если игрок нёс груз — он его бросает.
func server_switch() -> void:
	if Net.is_server() and _carried != null:
		_drop_carried()


## Сервер: выдать оружие с патронами (подобрал со стойки). false — не взял.
func server_give(_weapon: WeaponConfig, _ammo: int) -> bool:
	return false


## Сервер: взять груз в руки. Пока игрок его несёт, атаковать нельзя. false — не взял
## (мёртв, уже что-то несёт или предмета нет в наборе ITEMS).
func server_carry(item: ItemConfig) -> bool:
	if not Net.is_server() or _player.life != Player.Life.ALIVE or _carried != null:
		return false
	var index: int = ITEMS.index_of(item)
	if index <= EMPTY_HANDS:
		return false
	_carried = item
	_held_before_carry = _player.held_item
	_player.held_item = index
	return true


## Сервер: забрать груз из рук (игрок его доставил) — без сигнала carried_lost.
func server_take_carried() -> void:
	if not Net.is_server() or _carried == null:
		return
	_carried = null
	_player.held_item = _held_before_carry


## Клиент-владелец: личные данные об оружии пришли с сервера. Вызывает Player.
func apply_loadout(_data: Array) -> void:
	pass


## Сервер: игрок бросил груз или потерял его.
func _drop_carried() -> void:
	var item: ItemConfig = _carried
	server_take_carried()
	carried_lost.emit(item)


func _on_life_changed(new_life: Player.Life) -> void:
	if new_life != Player.Life.ALIVE and _carried != null:
		_drop_carried()
