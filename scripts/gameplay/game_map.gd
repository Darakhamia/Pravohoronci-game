class_name GameMap
extends Node3D
## Общий скрипт карты. Сервер расставляет аватары по точкам спавна, клиенты получают
## их через PlayerSpawner. Сцена карты обязана содержать SpawnPoints (Marker3D, -Z смотрит
## в сторону взгляда), Players и PlayerSpawner; Players стоит в начале координат.

## Все пиры: аватар появился и готов.
signal player_added(player: Player)
## Все пиры: аватар убран.
signal player_removed(peer_id: int)

## Та же сцена должна быть в списке PlayerSpawner.
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player.tscn")

## Игрока, упавшего ниже этой высоты, сервер возвращает на точку спавна.
@export var kill_plane_y: float = -25.0

## Сервер: где появился каждый игрок.
var _spawn_points_by_peer: Dictionary[int, Marker3D] = {}

@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _players: Node3D = $Players
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	_players.child_exiting_tree.connect(_on_player_exiting_tree)
	if not Net.is_server():
		set_physics_process(false)
		_player_spawner.spawned.connect(_on_player_spawned)
		return
	Net.player_left.connect(_on_net_player_left)
	# Аватар получают только те, кто был в лобби на старте матча.
	for id: int in Net.players:
		_spawn_player(id)


## Сервер: вернуть выпавших с карты.
func _physics_process(_delta: float) -> void:
	for player: Player in get_players():
		if player.position.y < kill_plane_y:
			player.teleport(_spawn_points_by_peer[player.peer_id].global_position)


func get_player(peer_id: int) -> Player:
	return _players.get_node_or_null(str(peer_id)) as Player


func get_players() -> Array[Player]:
	var result: Array[Player] = []
	for child: Node in _players.get_children():
		var player: Player = child as Player
		if player != null:
			result.append(player)
	return result


func _spawn_player(id: int) -> void:
	var index: int = _spawn_points_by_peer.size() % _spawn_points.get_child_count()
	var spawn_point: Marker3D = _spawn_points.get_child(index) as Marker3D
	var player: Player = PLAYER_SCENE.instantiate() as Player
	# По имени узла все пиры узнают владельца аватара.
	player.name = str(id)
	player.position = spawn_point.global_position
	player.rotation.y = spawn_point.global_rotation.y
	_spawn_points_by_peer[id] = spawn_point
	_players.add_child(player, true)
	player_added.emit(player)


func _on_player_spawned(node: Node) -> void:
	var player: Player = node as Player
	if player != null:
		player_added.emit(player)


func _on_net_player_left(peer_id: int) -> void:
	var player: Player = get_player(peer_id)
	if player != null:
		player.queue_free()


func _on_player_exiting_tree(node: Node) -> void:
	var player: Player = node as Player
	if player == null:
		return
	_spawn_points_by_peer.erase(player.peer_id)
	player_removed.emit(player.peer_id)
