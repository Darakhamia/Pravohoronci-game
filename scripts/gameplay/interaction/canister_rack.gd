class_name CanisterRack
extends Interactable
## Стеллаж с канистрами (не задание). По E выдаёт канистру живому игроку, у которого
## есть несделанная доставка (TaskFuelDock) и ещё нет канистры в руках. Канистры не
## кончаются: брошенная (Q или смерть) просто пропадает, за новой можно вернуться.
## На клиенте над стеллажом горит метка (узел Marker), пока своему игроку нужна доставка.

## Метка «тебе сюда»; null, если её нет в сцене.
@onready var _marker: Node3D = get_node_or_null(^"Marker") as Node3D


func _ready() -> void:
	if _marker == null:
		return
	_marker.visible = false
	if Net.is_server():
		return
	Game.tasks.local_tasks_changed.connect(_update_marker)
	# Номера станций карта выдаёт после _ready своих детей.
	_update_marker.call_deferred()


## Канистру берёт тот, у кого есть несделанная доставка и ещё нет канистры в руках.
## Работает и на клиенте про своего игрока.
func can_interact(player: Player) -> bool:
	return (not player.weapons.is_carrying(TaskFuelDock.CANISTER)
			and _has_pending_delivery(player.peer_id))


## Сервер: игрок нажал E — даём канистру в руки.
func server_interact(player: Player) -> void:
	player.weapons.server_carry(TaskFuelDock.CANISTER)


## Клиент: горит ли над стеллажом метка для своего игрока.
func is_marked() -> bool:
	return _marker != null and _marker.visible


## Есть ли у игрока несделанная доставка. Сервер: про любого. Клиент: про себя.
func _has_pending_delivery(peer_id: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group(TaskFuelDock.GROUP):
		var dock: TaskFuelDock = node as TaskFuelDock
		if dock != null and Game.tasks.is_pending(peer_id, dock.interact_id):
			return true
	return false


func _update_marker() -> void:
	_marker.visible = _has_pending_delivery(Net.local_id())
