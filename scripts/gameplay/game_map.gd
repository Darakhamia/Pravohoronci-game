class_name GameMap
extends Node3D
## Общий скрипт карты. Сервер расставляет аватары по точкам спавна, клиенты получают
## их через PlayerSpawner. Сцена карты обязана содержать:
## - SpawnPoints: хотя бы один Marker3D, -Z смотрит в сторону взгляда игрока;
## - Players (в начале координат) и PlayerSpawner со сценой игрока в списке;
## - Camera3D с current = true: вид для тех, у кого нет аватара (опоздавшие).
## По желанию: MeetingSeats — Marker3D, куда игроков рассаживает собрание (иначе SpawnPoints).
## Предметы карты (Interactable) могут лежать где угодно, кроме Players: карта сама находит
## их при загрузке и выдаёт номера по порядку в дереве — одинаково на всех пирах.

## Все пиры: аватар появился и готов.
signal player_added(player: Player)
## Все пиры: аватар убран.
signal player_removed(peer_id: int)
## Сервер: предмет карты сменил общее состояние — World рассылает его игрокам.
signal interactable_state_changed(interact_id: int, state: int)

## Та же сцена должна быть в списке PlayerSpawner.
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player.tscn")
const GHOST_SCENE: PackedScene = preload("res://scenes/characters/ghost.tscn")

## Игрока, упавшего ниже этой высоты, сервер возвращает на точку спавна.
@export var kill_plane_y: float = -25.0
## Границы, в которых летает призрак.
@export var ghost_bounds: AABB = AABB(Vector3(-60.0, 0.3, -60.0), Vector3(120.0, 12.0, 120.0))

## Сервер: где появился каждый игрок.
var _spawn_points_by_peer: Dictionary[int, Marker3D] = {}
## Предметы карты; номер предмета — его место в списке плюс один.
var _interactables: Array[Interactable] = []
## Клиент: камера призрака своего игрока.
var _ghost: GhostCamera = null

@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _players: Node3D = $Players
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	_players.child_exiting_tree.connect(_on_player_exiting_tree)
	# Проверяем до появления аватаров: камера своего игрока не должна скрыть пропажу.
	if find_children("*", "Camera3D", true, false).is_empty():
		push_warning("На карте %s нет Camera3D: игрок без аватара увидит пустой экран" % name)
	_register_interactables(self)
	if Net.is_server():
		Net.player_left.connect(_on_net_player_left)
		Game.meeting.started.connect(_on_meeting_started)
		Game.meeting.ejected.connect(_on_player_ejected)
		Game.tasks.server_register_stations(_get_station_ids())
	else:
		set_physics_process(false)
		_player_spawner.spawned.connect(_on_player_spawned)


## Сервер: вернуть выпавших с карты.
func _physics_process(_delta: float) -> void:
	for player: Player in get_players():
		if player.position.y < kill_plane_y and player.life != Player.Life.GONE:
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


## Предмет по номеру: положительный — предмет карты, отрицательный — тело игрока
## с peer_id, равным номеру без знака. null — такого нет.
func get_interactable(interact_id: int) -> Interactable:
	if interact_id > 0:
		return _interactables[interact_id - 1] if interact_id <= _interactables.size() else null
	var player: Player = get_player(-interact_id) if interact_id < 0 else null
	return player.corpse if player != null else null


## Предметы самой карты (без тел игроков), по порядку номеров.
func get_interactables() -> Array[Interactable]:
	return _interactables.duplicate()


## Всё, на что игрок может навести прицел: предметы карты и тела игроков.
func get_focus_candidates() -> Array[Interactable]:
	var result: Array[Interactable] = _interactables.duplicate()
	for player: Player in get_players():
		result.append(player.corpse)
	return result


## Номера и состояния предметов, которые уже не в начальном состоянии.
func get_interactable_states() -> Dictionary[int, int]:
	var states: Dictionary[int, int] = {}
	for interactable: Interactable in _interactables:
		if interactable.state != 0:
			states[interactable.interact_id] = interactable.state
	return states


## Обходит карту в порядке дерева и выдаёт предметам номера. Players пропускаем:
## аватары появляются позже и у всех пиров в разном порядке.
func _register_interactables(node: Node) -> void:
	for child: Node in node.get_children():
		if child == _players:
			continue
		var interactable: Interactable = child as Interactable
		if interactable != null:
			_interactables.append(interactable)
			interactable.interact_id = _interactables.size()
			if Net.is_server():
				interactable.state_changed.connect(
						_on_interactable_state_changed.bind(interactable.interact_id))
		_register_interactables(child)


func _get_station_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = []
	for interactable: Interactable in _interactables:
		if interactable is TaskStation:
			ids.append(interactable.interact_id)
	return ids


func _on_interactable_state_changed(state: int, interact_id: int) -> void:
	interactable_state_changed.emit(interact_id, state)


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
	player.map = self
	player.position = spawn_point.global_position
	player.rotation.y = spawn_point.global_rotation.y
	_spawn_points_by_peer[id] = spawn_point
	_players.add_child(player, true)
	player_added.emit(player)


## Первая свободная точка; если заняты все — по кругу.
func _pick_spawn_point() -> Marker3D:
	var points: Array[Marker3D] = _get_markers(_spawn_points)
	if points.is_empty():
		return null
	var taken: Array = _spawn_points_by_peer.values()
	for point: Marker3D in points:
		if not taken.has(point):
			return point
	return points[_spawn_points_by_peer.size() % points.size()]


func _get_markers(parent: Node) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for child: Node in parent.get_children():
		var marker: Marker3D = child as Marker3D
		if marker != null:
			markers.append(marker)
	return markers


## Сервер: началось собрание. Тела убираем (о погибших все узнают на собрании),
## живых рассаживаем по местам лицом к столу.
func _on_meeting_started() -> void:
	var seats_parent: Node = get_node_or_null(^"MeetingSeats")
	var seats: Array[Marker3D] = _get_markers(seats_parent if seats_parent != null else _spawn_points)
	var seat_index: int = 0
	for player: Player in get_players():
		if player.life == Player.Life.CORPSE:
			player.server_set_life(Player.Life.GONE)
			# Тело вышедшего игрока больше никому не нужно.
			if not Net.players.has(player.peer_id):
				player.queue_free()
		elif player.life == Player.Life.ALIVE and not seats.is_empty():
			var seat: Marker3D = seats[seat_index % seats.size()]
			seat_index += 1
			player.teleport(seat.global_position, seat.global_rotation.y)


## Сервер: игрока изгнали голосованием — тела он не оставляет.
func _on_player_ejected(peer_id: int) -> void:
	var player: Player = get_player(peer_id)
	if player != null:
		player.server_set_life(Player.Life.GONE)


func _on_player_spawned(node: Node) -> void:
	var player: Player = node as Player
	if player == null:
		return
	player.map = self
	if player.is_local():
		player.life_changed.connect(_on_local_life_changed.bind(player))
		_on_local_life_changed(player.life, player)
	player_added.emit(player)


## Клиент: свой игрок умер — дальше он смотрит на карту призраком.
func _on_local_life_changed(new_life: Player.Life, player: Player) -> void:
	if new_life == Player.Life.ALIVE or _ghost != null:
		return
	_ghost = GHOST_SCENE.instantiate() as GhostCamera
	add_child(_ghost)
	_ghost.setup(player.input, player.get_eye_position(), ghost_bounds)


## Сервер: игрок вышел из игры. Живой аватар убираем сразу, а тело убитого остаётся
## лежать до ближайшего собрания: иначе убийца избавлялся бы от улики чужим выходом.
func _on_net_player_left(peer_id: int) -> void:
	var player: Player = get_player(peer_id)
	if player != null and player.life != Player.Life.CORPSE:
		player.queue_free()


func _on_player_exiting_tree(node: Node) -> void:
	var player: Player = node as Player
	if player == null:
		return
	_spawn_points_by_peer.erase(player.peer_id)
	player_removed.emit(player.peer_id)
