class_name TaskLocalHands
extends RefCounted
## Клиент: что держит в руках свой игрок на карте, где стоит предмет. Нужен меткам
## доставки: стеллаж отмечен, пока канистры нет, порты — когда она уже в руках.
## Создаёт предмет карты (TaskFuelDock, CanisterRack) у себя в _ready и слушает changed.
## Своего аватара может ещё не быть (он появляется после карты) или не быть вовсе
## (зритель): тогда в руках ничего нет. На сервере не используется.

## Свой аватар появился или взял в руки другой предмет.
signal changed

## Карта, на которой стоит предмет; null — предмет не на карте (тесты).
var _map: GameMap = null
## Свой аватар, за руками которого следим; null — его ещё не видели.
var _player: Player = null


## node — предмет карты, которому нужны руки своего игрока.
func _init(node: Node) -> void:
	var parent: Node = node.get_parent()
	while parent != null and not parent is GameMap:
		parent = parent.get_parent()
	_map = parent as GameMap
	if _map != null:
		_map.player_added.connect(_on_player_added)


## Несёт ли свой игрок этот груз. Без аватара — нет.
func is_carrying(item: ItemConfig) -> bool:
	var player: Player = _get_player()
	return player != null and player.weapons.is_carrying(item)


## Свой аватар; null, если его нет. Аватар, появившийся раньше предмета, находим здесь:
## в _ready предмета сама карта ещё не готова.
func _get_player() -> Player:
	if not is_instance_valid(_player):
		_player = null
		if is_instance_valid(_map) and _map.is_node_ready() and Net.is_joined():
			_bind(_map.get_player(Net.local_id()))
	return _player


func _bind(player: Player) -> void:
	if player == null or player == _player:
		return
	_player = player
	player.held_item_changed.connect(_on_held_item_changed)


func _on_player_added(player: Player) -> void:
	if not player.is_local():
		return
	_bind(player)
	changed.emit()


func _on_held_item_changed(_item_id: int) -> void:
	changed.emit()
