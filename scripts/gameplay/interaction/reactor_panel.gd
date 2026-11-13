class_name ReactorPanel
extends Interactable
## Пульт реактора: пока идёт саботаж, любой живой игрок чинит реактор удержанием E
## (hold_seconds). Без саботажа пультом пользоваться нельзя.
## На клиенте над пультом горит метка (узел Marker), пока саботаж не починен.

## Метка «чинить здесь»; null, если её нет в сцене.
@onready var _marker: Node3D = get_node_or_null(^"Marker") as Node3D


func _ready() -> void:
	if _marker == null:
		return
	_marker.visible = false
	if Net.is_server():
		return
	Game.sabotage.started.connect(_update_marker)
	Game.sabotage.ended.connect(_update_marker.unbind(1))
	# Опоздавший мог получить карту уже во время саботажа.
	_update_marker()


## Пульт работает, только пока идёт саботаж (это знают все пиры). Что игрок жив и рядом,
## проверяет PlayerInteractor.
func can_interact(_player: Player) -> bool:
	return Game.sabotage.active


## Сервер: игрок додержал E — реактор починен.
func server_interact(player: Player) -> void:
	Game.sabotage.server_fix(player.peer_id)


## Клиент: горит ли над пультом метка.
func is_marked() -> bool:
	return _marker != null and _marker.visible


func _update_marker() -> void:
	_marker.visible = Game.sabotage.active
