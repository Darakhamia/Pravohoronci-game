class_name World
extends Node3D
## Держит текущую карту и служит почтой между аватарами клиента и сервера.
## Живёт всю сессию на каждом пире, поэтому все RPC аватаров идут сюда, а не в Player:
## пакеты, которые ещё летят, когда игрока или карту уже убрали, не вызывают ошибок движка.
## Клиент присылает только ввод и действия; сервер проверяет отправителя и каждый аргумент.
##
## Скрытое в мире. Предмет в чужих руках и чужие атаки — подсказка, кто предатель, поэтому
## сервер рассказывает о них не всем, а тем, кто игрока замечает (правило — Perception):
## ему самому, тем, кто рядом или видит его без стен, призракам и зрителям. О смене предмета
## замечающие узнают на следующем тике; остальные — когда игрок попадётся им на глаза
## (проверка несколько раз в секунду), а до тех пор помнят то, что видели. Событие атаки
## получают те, кто замечает атакующего или точку, где атака закончилась. Незарегистрированный
## пир не получает ничего.

## Все пиры. null — карты больше нет.
signal map_changed(map: GameMap)

## Папки с картами. Карта — любая сцена прямо в такой папке (вложенные папки не смотрим).
## Список одинаков на всех пирах: по нему MapSpawner узнаёт сцену карты.
const MAP_DIRS: PackedStringArray = ["res://scenes/maps", "res://tests/maps"]
const SCENE_EXTENSION: String = "tscn"
## В собранной игре сцены в списке файлов называются "<имя>.tscn.remap".
const REMAP_SUFFIX: String = ".remap"
## Сервер: раз во столько физических тиков проверяем, кто кого начал замечать (6 раз в секунду).
const PERCEPTION_INTERVAL_TICKS: int = 10
## Слой world: стены закрывают обзор, игроки — нет.
const SIGHT_MASK: int = 1
## Точка, до которой луч взгляда не дошёл меньше этого, видна: она лежит на самой стене
## (место, куда попала пуля), м.
const SIGHT_END_MARGIN: float = 0.1

var current_map: GameMap = null

## Загружена заранее. Иначе клиент грузил бы карту прямо во время приёма спавна
## и на это время переставал бы отвечать серверу.
var _default_map_scene: PackedScene = null
var _map_paths: PackedStringArray = []
## Сервер: что каждому игроку рассказано о предмете в руках каждого аватара:
## peer_id наблюдателя -> (peer_id аватара -> номер предмета). Записи нет — клиент думает,
## что руки пустые: так аватар появляется у него на экране.
var _told_items: Dictionary[int, Dictionary] = {}
## Сервер: аватары, у которых предмет в руках сменился с прошлого физического тика.
var _changed_holders: Dictionary[int, bool] = {}
## Сервер: сколько тиков осталось до следующей проверки «кто кого начал замечать».
var _perception_ticks_left: int = 0

@onready var _map_spawner: MultiplayerSpawner = $MapSpawner


func _ready() -> void:
	_map_paths = find_map_scenes()
	for path: String in _map_paths:
		_map_spawner.add_spawnable_scene(path)
	# Путь к основной карте живёт только в game_config.tres.
	if _map_paths.has(Game.config.map_scene):
		_default_map_scene = load(Game.config.map_scene) as PackedScene
	else:
		push_error("Карта из game_config.tres не лежит в папке карт: %s" % Game.config.map_scene)
	_map_spawner.spawned.connect(_on_map_spawned)
	_map_spawner.despawned.connect(_on_map_despawned)
	Game.state_changed.connect(_on_state_changed)
	Net.player_joined.connect(_on_net_player_joined)
	Net.player_left.connect(_on_net_player_left)
	Net.disconnected.connect(_on_session_ended)
	Net.connection_failed.connect(_on_session_ended)


## Пути всех сцен карт, по алфавиту.
static func find_map_scenes() -> PackedStringArray:
	var paths: PackedStringArray = []
	for dir: String in MAP_DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file: String in DirAccess.get_files_at(dir):
			var scene_file: String = file.trim_suffix(REMAP_SUFFIX)
			var path: String = dir.path_join(scene_file)
			if scene_file.get_extension() == SCENE_EXTENSION and not paths.has(path):
				paths.append(path)
	paths.sort()
	return paths


## Путь карты по имени файла без расширения ("test_map"); пусто, если такой нет.
static func find_map_by_name(map_name: String) -> String:
	for path: String in find_map_scenes():
		if path.get_file().get_basename() == map_name:
			return path
	return ""


# --- Сервер: кто что замечает ---


## Сервер: рассказать о предметах в руках тем, кому пора о них узнать. Сразу — о тех, у кого
## предмет только что сменился; раз в PERCEPTION_INTERVAL_TICKS — обо всех (кто-то мог
## попасться на глаза). В физическом тике, потому что видимость проверяется лучами.
func _physics_process(_delta: float) -> void:
	if not Net.is_server() or current_map == null:
		return
	_perception_ticks_left -= 1
	var is_full_pass: bool = _perception_ticks_left <= 0
	if is_full_pass:
		_perception_ticks_left = PERCEPTION_INTERVAL_TICKS
	elif _changed_holders.is_empty():
		return
	for subject: Player in current_map.get_players():
		if not is_full_pass and not _changed_holders.has(subject.peer_id):
			continue
		for observer_id: int in Net.players:
			if _knows_held_item(observer_id, subject) or not Net.is_peer_reachable(observer_id):
				continue
			if _perceives_player(observer_id, subject):
				_tell_held_item(observer_id, subject)
	_changed_holders.clear()


## Сервер: знает ли наблюдатель, что сейчас в руках у аватара.
func _knows_held_item(observer_id: int, subject: Player) -> bool:
	var told: Dictionary = _told_items.get(observer_id, {})
	var item: int = told.get(subject.peer_id, PlayerWeapons.EMPTY_HANDS)
	return item == subject.held_item


## Сервер: рассказать наблюдателю, что в руках у аватара. Вызывающий уже проверил, что
## наблюдатель его замечает и что до него можно дотянуться.
func _tell_held_item(observer_id: int, subject: Player) -> void:
	if not _told_items.has(observer_id):
		_told_items[observer_id] = {}
	_told_items[observer_id][subject.peer_id] = subject.held_item
	_receive_held_item.rpc_id(observer_id, subject.peer_id, subject.held_item)


## Сервер: замечает ли наблюдатель этого игрока (Perception): он сам, зритель или мёртвый —
## всегда; живой — если игрок рядом или виден без стен.
func _perceives_player(observer_id: int, subject: Player) -> bool:
	var observer: Player = _get_living_avatar(observer_id)
	return Perception.can_observe(observer_id == subject.peer_id, observer != null,
			observer.get_eye_position() if observer != null else Vector3.ZERO,
			subject.get_sight_points(), Game.config.perception_near_radius,
			Game.config.perception_sight_range, _is_line_clear)


## Сервер: замечает ли наблюдатель хотя бы одну из точек мира (место, где закончилась атака).
func _perceives_points(observer_id: int, points: PackedVector3Array) -> bool:
	if points.is_empty():
		return false
	var observer: Player = _get_living_avatar(observer_id)
	return Perception.can_observe(false, observer != null,
			observer.get_eye_position() if observer != null else Vector3.ZERO,
			points, Game.config.perception_near_radius, Game.config.perception_sight_range, _is_line_clear)


## Сервер: живой аватар игрока; null — его нет (зритель) или игрок мёртв.
func _get_living_avatar(peer_id: int) -> Player:
	var player: Player = current_map.get_player(peer_id) if current_map != null else null
	return player if player != null and player.life == Player.Life.ALIVE else null


## Сервер: нет ли стены между двумя точками (один физический луч по слою world).
func _is_line_clear(from: Vector3, to: Vector3) -> bool:
	if current_map == null or from.is_equal_approx(to):
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, SIGHT_MASK)
	var hit: Dictionary = current_map.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_position: Vector3 = hit["position"]
	return hit_position.distance_to(to) <= SIGHT_END_MARGIN


## Сервер: точки мира, по которым событие замечают те, кто не видит самого игрока.
## У атаки это место, где она закончилась.
func _get_event_points(kind: Player.Event, data: Array) -> PackedVector3Array:
	var points: PackedVector3Array = []
	if kind == Player.Event.ATTACK:
		var attack: AttackEvent = AttackEvent.decode(data, PlayerWeapons.ITEMS)
		if attack != null:
			points.append(attack.to)
	return points


func _on_held_item_changed(_item_id: int, player: Player) -> void:
	_changed_holders[player.peer_id] = true


## Сервер: аватар убран — если игрок появится снова, руки нового аватара у всех пустые.
func _on_player_removed(peer_id: int) -> void:
	_changed_holders.erase(peer_id)
	for observer_id: int in _told_items:
		_told_items[observer_id].erase(peer_id)


func _on_net_player_left(peer_id: int) -> void:
	_told_items.erase(peer_id)


# --- Сервер: карта живёт, пока идёт матч ---


func _on_state_changed(new_state: Game.State) -> void:
	if not Net.is_server():
		return
	_remove_map()
	if new_state == Game.State.MATCH:
		_load_map()


func _load_map() -> void:
	var path: String = Game.config.map_scene
	var scene: PackedScene = _default_map_scene
	if not Game.debug_map_name.is_empty():
		path = find_map_by_name(Game.debug_map_name)
		scene = load(path) as PackedScene if not path.is_empty() else null
	var map: GameMap = scene.instantiate() as GameMap if scene != null else null
	if map == null:
		push_error("Сцена карты не найдена или её корень не GameMap: %s" % path)
		return
	add_child(map, true)
	_set_map(map)
	# После map_changed: подписчики уже слушают player_added.
	map.spawn_players()


func _remove_map() -> void:
	if current_map == null:
		return
	var map: GameMap = current_map
	_set_map(null)
	remove_child(map)
	map.queue_free()


## Опоздавший получил карту в начальном виде: досылаем состояние её предметов и то, что
## игроки держат в руках (он зритель без аватара и видит всех).
func _on_net_player_joined(peer_id: int) -> void:
	if not Net.is_server() or current_map == null or not Net.is_peer_reachable(peer_id):
		return
	var states: Dictionary[int, int] = current_map.get_interactable_states()
	for interact_id: int in states:
		_receive_interactable_state.rpc_id(peer_id, interact_id, states[interact_id])
	_told_items.erase(peer_id)
	if current_map.get_player(peer_id) != null:
		return
	for subject: Player in current_map.get_players():
		if not _knows_held_item(peer_id, subject):
			_tell_held_item(peer_id, subject)


func _on_interactable_state_changed(interact_id: int, state: int) -> void:
	for peer_id: int in Net.players:
		if Net.is_peer_reachable(peer_id):
			_receive_interactable_state.rpc_id(peer_id, interact_id, state)


func _send_private(kind: Player.Private, data: Array, player: Player) -> void:
	if Net.is_peer_reachable(player.peer_id):
		_receive_private.rpc_id(player.peer_id, kind, data)


## Сервер: событие аватара получают те, кто замечает его самого или место события.
## Тот, кто видит игрока, заодно узнаёт, что у него в руках: событие не должно обогнать нож.
func _send_event(kind: Player.Event, data: Array, player: Player) -> void:
	var points: PackedVector3Array = _get_event_points(kind, data)
	for peer_id: int in Net.players:
		if not Net.is_peer_reachable(peer_id):
			continue
		if _perceives_player(peer_id, player):
			if not _knows_held_item(peer_id, player):
				_tell_held_item(peer_id, player)
		elif not _perceives_points(peer_id, points):
			continue
		_receive_event.rpc_id(peer_id, player.peer_id, kind, data)


# --- Клиент: карту создаёт и убирает MapSpawner ---


func _on_map_spawned(node: Node) -> void:
	_set_map(node as GameMap)


func _on_map_despawned(node: Node) -> void:
	if node == current_map:
		_set_map(null)


func _on_session_ended(_reason: String) -> void:
	# Движок сам удаляет реплицированную карту при закрытии сессии, но сигнал despawned
	# не приходит: сбрасываем current_map и сообщаем map_changed(null) сами.
	_remove_map()


# --- Общее ---


func _set_map(map: GameMap) -> void:
	if map == current_map:
		return
	current_map = map
	_told_items.clear()
	_changed_holders.clear()
	if map != null:
		map.player_added.connect(_on_player_added)
		if Net.is_server():
			map.interactable_state_changed.connect(_on_interactable_state_changed)
			map.player_removed.connect(_on_player_removed)
		for player: Player in map.get_players():
			_on_player_added(player)
	map_changed.emit(map)


## Сервер рассылает сообщения аватара, клиент отправляет ввод своего игрока.
func _on_player_added(player: Player) -> void:
	if Net.is_server():
		if player.private_sent.get_connections().is_empty():
			player.private_sent.connect(_send_private.bind(player))
			player.event_sent.connect(_send_event.bind(player))
			player.held_item_changed.connect(_on_held_item_changed.bind(player))
		return
	if not player.is_local() or player.input.sampled.is_connected(_send_input):
		return
	player.input.sampled.connect(_send_input)
	player.input.jump_pressed.connect(_send_jump)
	player.input.fire_pressed.connect(_send_fire.bind(player))
	player.input.switch_weapon_pressed.connect(_send_switch_weapon)
	player.input.weapon_slot_pressed.connect(_send_select_weapon)
	player.input.sabotage_pressed.connect(Game.sabotage.request)
	player.interactor.press_requested.connect(_send_interact)


func _send_input(direction: Vector2, yaw: float, pitch: float) -> void:
	if Net.is_joined():
		_receive_input.rpc_id(Net.SERVER_ID, direction, yaw, pitch)


func _send_jump() -> void:
	if Net.is_joined():
		_receive_jump.rpc_id(Net.SERVER_ID)


## Вместе с нажатием уходит точный взгляд: обычный ввод мог ещё не дойти.
func _send_fire(player: Player) -> void:
	if Net.is_joined():
		_receive_fire.rpc_id(Net.SERVER_ID, player.input.yaw, player.input.pitch)


func _send_switch_weapon() -> void:
	if Net.is_joined():
		_receive_switch_weapon.rpc_id(Net.SERVER_ID)


func _send_select_weapon(slot: int) -> void:
	if Net.is_joined():
		_receive_select_weapon.rpc_id(Net.SERVER_ID, slot)


func _send_interact(interact_id: int, pressed: bool) -> void:
	if Net.is_joined():
		_receive_interact.rpc_id(Net.SERVER_ID, interact_id, pressed)


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


@rpc("any_peer", "call_remote", "reliable")
func _receive_fire(yaw: float, pitch: float) -> void:
	var player: Player = _get_sender_player()
	if player != null:
		player.weapons.server_fire(PlayerInput.sanitize_yaw(yaw), PlayerInput.sanitize_pitch(pitch))


@rpc("any_peer", "call_remote", "reliable")
func _receive_switch_weapon() -> void:
	var player: Player = _get_sender_player()
	if player != null:
		player.weapons.server_switch()


## Сервер: клиент нажал цифровую клавишу оружия. Номер клавиши проверяется здесь, есть ли
## у игрока такое оружие — в PlayerWeapons в физическом тике.
@rpc("any_peer", "call_remote", "reliable")
func _receive_select_weapon(slot: int) -> void:
	var player: Player = _get_sender_player()
	if player != null and slot >= 1 and slot <= PlayerWeapons.ITEMS.items.size():
		player.weapons.server_select(slot)


@rpc("any_peer", "call_remote", "reliable")
func _receive_interact(interact_id: int, pressed: bool) -> void:
	var player: Player = _get_sender_player()
	if player != null:
		player.interactor.server_request(interact_id, pressed)


@rpc("authority", "call_remote", "reliable")
func _receive_private(kind: int, data: Array) -> void:
	var player: Player = _get_local_player()
	if player != null:
		player.receive_private(kind, data)


@rpc("authority", "call_remote", "reliable")
func _receive_event(peer_id: int, kind: int, data: Array) -> void:
	var player: Player = current_map.get_player(peer_id) if current_map != null and Net.is_joined() else null
	if player != null:
		player.receive_event(kind, data)


## Клиент: сервер рассказал, что в руках у игрока, которого свой игрок заметил.
@rpc("authority", "call_remote", "reliable")
func _receive_held_item(peer_id: int, item_id: int) -> void:
	var player: Player = current_map.get_player(peer_id) if current_map != null and Net.is_joined() else null
	if player != null:
		player.receive_held_item(item_id)


@rpc("authority", "call_remote", "reliable")
func _receive_interactable_state(interact_id: int, state: int) -> void:
	if current_map == null or not Net.is_joined():
		return
	var interactable: Interactable = current_map.get_interactable(interact_id)
	if interactable != null:
		interactable.apply_state(state)


## Только сервер: игрок того пира, от которого пришёл RPC. Чужим игроком управлять нельзя.
func _get_sender_player() -> Player:
	if not Net.is_server() or current_map == null:
		return null
	return current_map.get_player(multiplayer.get_remote_sender_id())


## Только клиент: свой аватар.
func _get_local_player() -> Player:
	if not Net.is_joined() or current_map == null:
		return null
	return current_map.get_player(Net.local_id())
