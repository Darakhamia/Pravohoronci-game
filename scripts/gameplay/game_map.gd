class_name GameMap
extends Node3D
## Общий скрипт карты. Сервер расставляет аватары по точкам спавна, клиенты получают
## их через PlayerSpawner. Сцена карты обязана содержать:
## - SpawnPoints: хотя бы один Marker3D, -Z смотрит в сторону взгляда игрока;
## - Players (в начале координат) и PlayerSpawner со сценой игрока в списке;
## - Camera3D с current = true: вид для тех, у кого нет аватара (опоздавшие, позже призраки).

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
	# Проверяем до появления аватаров: камера своего игрока не должна скрыть пропажу.
	if find_children("*", "Camera3D", true, false).is_empty():
		push_warning("На карте %s нет Camera3D: игрок без аватара увидит пустой экран" % name)
	if Net.is_server():
		Net.player_left.connect(_on_net_player_left)
	else:
		set_physics_process(false)
		_player_spawner.spawned.connect(_on_player_spawned)


## Сервер: вернуть выпавших с карты.
func _physics_process(_delta: float) -> void:
	for player: Player in get_players():
		if player.position.y < kill_plane_y:
			player.teleport(_spawn_points_by_peer[player.peer_id].global_position)


## Сервер: расставить аватары всех, кто сейчас в лобби; вошедшие позже ждут следующего матча.
## Вызывает World уже после map_changed, чтобы подписчики успели подключиться к player_added.
func spawn_players() -> void:
	if not Net.is_server():
		return
	for id: int in Net.players:
		_spawn_player(id)


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
	# При повторном спавне игрок возвращается на свою точку.
	var spawn_point: Marker3D = _spawn_points_by_peer.get(id) as Marker3D
	# Узел с тем же именем сдвинул бы имя нового (12 -> 13), и аватар достался бы чужому id.
	var stale: Player = get_player(id)
	if stale != null:
		_players.remove_child(stale)
		stale.queue_free()
	if spawn_point == null:
		spawn_point = _pick_spawn_point()
	if spawn_point == null:
		push_error("На карте %s нет точек спавна: нужен хотя бы один Marker3D в SpawnPoints" % name)
		return
	var player: Player = PLAYER_SCENE.instantiate() as Player
	# По имени узла все пиры узнают владельца аватара.
	player.name = str(id)
	player.position = spawn_point.global_position
	player.rotation.y = spawn_point.global_rotation.y
	_spawn_points_by_peer[id] = spawn_point
	_players.add_child(player, true)
	player_added.emit(player)


## Первая свободная точка; если заняты все — по кругу.
func _pick_spawn_point() -> Marker3D:
	var points: Array[Marker3D] = []
	for child: Node in _spawn_points.get_children():
		var point: Marker3D = child as Marker3D
		if point != null:
			points.append(point)
	if points.is_empty():
		return null
	var taken: Array = _spawn_points_by_peer.values()
	for point: Marker3D in points:
		if not taken.has(point):
			return point
	return points[_spawn_points_by_peer.size() % points.size()]


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
