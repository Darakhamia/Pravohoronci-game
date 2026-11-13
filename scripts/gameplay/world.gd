class_name World
extends Node3D
## Держит текущую карту и принимает ввод игроков.
## Живёт всю сессию на каждом пире, поэтому RPC ввода приходят сюда, а не в Player:
## пакеты, которые ещё летят, когда игрока или карту уже убрали, не вызывают ошибок движка.

## Все пиры. null — карты больше нет.
signal map_changed(map: GameMap)

var current_map: GameMap = null

@onready var _map_spawner: MultiplayerSpawner = $MapSpawner


func _ready() -> void:
	# Путь к карте живёт только в game_config.tres.
	_map_spawner.add_spawnable_scene(Game.CONFIG.map_scene)
	_map_spawner.spawned.connect(_on_map_spawned)
	_map_spawner.despawned.connect(_on_map_despawned)
	Game.state_changed.connect(_on_state_changed)
	Net.disconnected.connect(_on_session_ended)
	Net.connection_failed.connect(_on_session_ended)


# --- Сервер: карта живёт, пока идёт матч ---


func _on_state_changed(new_state: Game.State) -> void:
	if not Net.is_server():
		return
	_remove_map()
	if new_state == Game.State.MATCH:
		_load_map()


func _load_map() -> void:
	var scene: PackedScene = load(Game.CONFIG.map_scene) as PackedScene
	var map: GameMap = scene.instantiate() as GameMap if scene != null else null
	if map == null:
		push_error("Сцена карты не найдена или её корень не GameMap: %s" % Game.CONFIG.map_scene)
		return
	add_child(map, true)
	_set_map(map)


func _remove_map() -> void:
	if current_map == null:
		return
	var map: GameMap = current_map
	_set_map(null)
	remove_child(map)
	map.queue_free()


# --- Клиент: карту создаёт и убирает MapSpawner ---


func _on_map_spawned(node: Node) -> void:
	_set_map(node as GameMap)


func _on_map_despawned(node: Node) -> void:
	if node == current_map:
		_set_map(null)


func _on_session_ended(_reason: String) -> void:
	# Реплицированная карта сама не исчезает, когда соединение закрыто.
	_remove_map()


# --- Общее ---


func _set_map(map: GameMap) -> void:
	if map == current_map:
		return
	current_map = map
	if map != null:
		map.player_added.connect(_on_player_added)
		for player: Player in map.get_players():
			_on_player_added(player)
	map_changed.emit(map)


## Ввод отправляет только свой игрок: подписываемся на его PlayerInput.
func _on_player_added(player: Player) -> void:
	if not player.is_local() or player.input.sampled.is_connected(_send_input):
		return
	player.input.sampled.connect(_send_input)
	player.input.jump_pressed.connect(_send_jump)


func _send_input(direction: Vector2, yaw: float, pitch: float) -> void:
	if Net.is_joined():
		_receive_input.rpc_id(Net.SERVER_ID, direction, yaw, pitch)


func _send_jump() -> void:
	if Net.is_joined():
		_receive_jump.rpc_id(Net.SERVER_ID)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_input(direction: Vector2, yaw: float, pitch: float) -> void:
	var player: Player = _get_sender_player()
	if player != null:
		player.input.receive(direction, yaw, pitch)


@rpc("any_peer", "call_remote", "reliable")
func _receive_jump() -> void:
	var player: Player = _get_sender_player()
	if player != null:
		player.input.queue_jump()


## Только сервер: игрок того пира, от которого пришёл RPC. Чужим игроком управлять нельзя.
func _get_sender_player() -> Player:
	if not Net.is_server() or current_map == null:
		return null
	return current_map.get_player(multiplayer.get_remote_sender_id())
