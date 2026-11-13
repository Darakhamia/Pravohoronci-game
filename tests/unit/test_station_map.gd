extends TestCase
## Боевая карта scenes/maps/station.tscn: договор с GameMap, точки спавна и места собрания,
## нужное число станций и предметов, доступность каждого предмета и проходимость карты.
## Физические проверки идут в настоящем мире: карта добавляется в дерево на время теста.

const MAP_PATH: String = "res://scenes/maps/station.tscn"
const ITEMS_DIR: String = "res://scenes/items/"
const DOORWAY_SCENE: String = "res://scenes/maps/kit/wall_doorway.tscn"
const PLAYER_SCENE: String = "res://scenes/characters/player.tscn"
const SIGN_FONT: String = "res://assets/fonts/Unbounded.ttf"

## Слой «world» (layer_names/3d_physics/layer_1): стены, пол, реквизит.
const WORLD_MASK: int = 1
## Сколько физических кадров ждать, чтобы тела карты попали в мир.
const SETTLE_FRAMES: int = 2

const MIN_SPAWN_POINTS: int = 8
const MIN_SEATS: int = 8
## Капсула игрока (scenes/characters/player.tscn).
const PLAYER_RADIUS: float = 0.35
const PLAYER_HEIGHT: float = 1.8
const EYE_HEIGHT: float = 1.6
## Капсулу для проверок приподнимаем над полом, чтобы касание пола не считалось препятствием.
const FLOOR_LIFT: float = 0.1
## Точка считается стоящей на полу, если пол не дальше этого под ней.
const MAX_FLOOR_GAP: float = 0.3
## От стола собрания до места игрока: радиус стола плюс свободный метр с запасом.
const TABLE_RADIUS: float = 1.6
const MIN_SEAT_GAP: float = 1.2
## Насколько место может смотреть мимо центра стола.
const MAX_SEAT_ANGLE: float = deg_to_rad(10.0)

## Сколько чего должно стоять на карте: файл сцены -> наименьшее число.
const MIN_COUNTS: Dictionary[String, int] = {
	"task_wiring": 5, "task_keypad": 3, "task_calibrator": 3, "task_fuel_dock": 2,
	"weapon_pickup": 4, "emergency_button": 1, "canister_rack": 1, "reactor_panel": 1,
	"reactor_core": 1, "sabotage_alarm": 8,
}
## Чего не должно быть больше: файл сцены -> наибольшее число.
const MAX_COUNTS: Dictionary[String, int] = {
	"emergency_button": 1, "canister_rack": 2, "reactor_panel": 1, "reactor_core": 1, "sabotage_alarm": 10,
}
const MIN_TASK_STATIONS: int = 13
## Стойки с оружием: не в кают-компании и в разных углах карты.
const MIN_WEAPON_TO_BUTTON: float = 8.0
const MIN_WEAPON_SPACING: float = 15.0
## Канистры берут далеко от места, куда их несут.
const MIN_RACK_TO_DOCK: float = 20.0

## На каком расстоянии перед предметом (по его -Z) стоит игрок.
const STAND_DISTANCE: float = 1.0
## Исключения: кнопка собрания стоит в отверстии стола, к ней подходят от края столешницы.
const STAND_DISTANCE_BY_SCENE: Dictionary[String, float] = {"emergency_button": 2.0}
## Как в PlayerInteractor: препятствие у самой точки предмета не считается.
const SIGHT_MARGIN: float = 0.25

const NAV_NODE: String = "NavCheck"
const MIN_NAV_MARKERS: int = 20
## Обход проходит через каждый проём: его точка лежит не дальше этого от середины проёма.
const DOORWAY_REACH: float = 0.5
## Табличка с названием висит над проёмом с каждой стороны.
const SIGN_REACH: float = 0.6
const SIGNS_PER_DOORWAY: int = 2
## Надпись читается с 8 м, если кегль (font_size * pixel_size) не меньше этого, в метрах:
## заглавная буква тогда выше 18 см — около 14 пикселей на экране 720p.
const MIN_SIGN_EM: float = 0.25


func test_map_follows_game_map_contract() -> void:
	var map: GameMap = await _spawn_map()
	if map == null:
		return
	var players: Node3D = map.get_node_or_null(^"Players") as Node3D
	assert_true(players != null, "на карте есть узел Players")
	if players != null:
		assert_true(players.global_position.is_zero_approx(), "Players стоит в начале координат")
	var spawner: MultiplayerSpawner = map.get_node_or_null(^"PlayerSpawner") as MultiplayerSpawner
	assert_true(spawner != null, "на карте есть PlayerSpawner")
	if spawner != null:
		assert_eq(spawner.get_node_or_null(spawner.spawn_path), players, "PlayerSpawner кладёт игроков в Players")
		var has_player_scene: bool = false
		for index: int in spawner.get_spawnable_scene_count():
			has_player_scene = has_player_scene or spawner.get_spawnable_scene(index) == PLAYER_SCENE
		assert_true(has_player_scene, "в списке PlayerSpawner есть сцена игрока")
	var current_cameras: int = 0
	for node: Node in map.find_children("*", "Camera3D", true, false):
		var camera: Camera3D = node as Camera3D
		if camera.current:
			current_cameras += 1
			assert_true(map.ghost_bounds.grow(1.0).has_point(camera.global_position), "камера карты стоит внутри станции")
	assert_eq(current_cameras, 1, "на карте одна камера с current = true")
	assert_true(not map.find_children("*", "WorldEnvironment", true, false).is_empty(), "на карте есть WorldEnvironment")
	assert_true(map.kill_plane_y < -1.0, "kill_plane_y лежит ниже пола")
	assert_true(map.ghost_bounds.position.y > 0.0 and map.ghost_bounds.end.y < 3.2,
			"границы призрака лежат между полом и потолком")
	for interactable: Interactable in map.get_interactables():
		assert_true(map.ghost_bounds.grow(0.5).has_point(interactable.get_focus_position()),
				"%s лежит внутри границ призрака" % interactable.get_path())
	await _free_map(map)


func test_spawn_points_and_seats_are_usable() -> void:
	var map: GameMap = await _spawn_map()
	if map == null:
		return
	var spawn_points: Array[Marker3D] = _markers(map, "SpawnPoints")
	var seats: Array[Marker3D] = _markers(map, "MeetingSeats")
	assert_true(spawn_points.size() >= MIN_SPAWN_POINTS, "точек спавна не меньше %d (найдено %d)" % [MIN_SPAWN_POINTS, spawn_points.size()])
	assert_true(seats.size() >= MIN_SEATS, "мест собрания не меньше %d (найдено %d)" % [MIN_SEATS, seats.size()])
	for marker: Marker3D in spawn_points + seats:
		assert_true(_stands_on_floor(map, marker.global_position), "%s стоит на полу" % marker.get_path())
		assert_true(_capsule_is_free(map, marker.global_position), "%s не внутри стены или реквизита" % marker.get_path())
		assert_true(map.ghost_bounds.has_point(marker.global_position + Vector3.UP), "%s лежит внутри станции" % marker.get_path())
	for group: Array[Marker3D] in [spawn_points, seats]:
		for first: int in group.size():
			for second: int in range(first + 1, group.size()):
				assert_true(group[first].global_position.distance_to(group[second].global_position) > PLAYER_RADIUS * 2.0,
						"%s и %s не стоят друг в друге" % [group[first].name, group[second].name])
	var buttons: Array[Node3D] = _instances_of(map, "emergency_button")
	if buttons.is_empty():
		assert_true(false, "на карте есть кнопка собрания")
	else:
		var center: Vector3 = buttons[0].global_position
		for seat: Marker3D in seats:
			var to_center: Vector3 = center - seat.global_position
			to_center.y = 0.0
			assert_true(to_center.length() >= TABLE_RADIUS + MIN_SEAT_GAP - 0.01,
					"%s не ближе %.1f м к столу" % [seat.name, MIN_SEAT_GAP])
			var look: Vector3 = -seat.global_basis.z
			assert_true(look.angle_to(to_center) <= MAX_SEAT_ANGLE, "%s смотрит на центр стола" % seat.name)
	await _free_map(map)


func test_required_stations_and_items_are_placed() -> void:
	var map: GameMap = await _spawn_map()
	if map == null:
		return
	for scene_name: String in MIN_COUNTS:
		var count: int = _instances_of(map, scene_name).size()
		assert_true(count >= MIN_COUNTS[scene_name], "%s: нужно не меньше %d, на карте %d" % [scene_name, MIN_COUNTS[scene_name], count])
	for scene_name: String in MAX_COUNTS:
		var count: int = _instances_of(map, scene_name).size()
		assert_true(count <= MAX_COUNTS[scene_name], "%s: нужно не больше %d, на карте %d" % [scene_name, MAX_COUNTS[scene_name], count])
	var station_count: int = 0
	for interactable: Interactable in map.get_interactables():
		var station: TaskStation = interactable as TaskStation
		if station == null:
			continue
		station_count += 1
		assert_true(not station.title.strip_edges().is_empty(), "у станции %s есть название задания" % station.get_path())
		assert_true(not station.location.strip_edges().is_empty(), "у станции %s указано помещение" % station.get_path())
	assert_true(station_count >= MIN_TASK_STATIONS, "станций заданий не меньше %d (найдено %d)" % [MIN_TASK_STATIONS, station_count])
	var buttons: Array[Node3D] = _instances_of(map, "emergency_button")
	var stands: Array[Node3D] = _instances_of(map, "weapon_pickup")
	for stand: Node3D in stands:
		assert_true(stand.get(&"weapon") != null, "на стойке %s лежит оружие" % stand.get_path())
		var ammo: Variant = stand.get(&"ammo")
		assert_true(ammo is int and ammo > 0, "на стойке %s есть патроны" % stand.get_path())
		if not buttons.is_empty():
			assert_true(stand.global_position.distance_to(buttons[0].global_position) >= MIN_WEAPON_TO_BUTTON,
					"стойка %s стоит не в кают-компании" % stand.get_path())
	for first: int in stands.size():
		for second: int in range(first + 1, stands.size()):
			assert_true(stands[first].global_position.distance_to(stands[second].global_position) >= MIN_WEAPON_SPACING,
					"стойки %s и %s стоят в разных углах карты" % [stands[first].name, stands[second].name])
	for rack: Node3D in _instances_of(map, "canister_rack"):
		for dock: Node3D in _instances_of(map, "task_fuel_dock"):
			assert_true(rack.global_position.distance_to(dock.global_position) >= MIN_RACK_TO_DOCK,
					"стеллаж %s далеко от заправки %s" % [rack.name, dock.name])
	await _free_map(map)


## У каждого предмета есть место, где игрок помещается, дотягивается и видит точку предмета.
func test_every_interactable_can_be_reached() -> void:
	var map: GameMap = await _spawn_map()
	if map == null:
		return
	var interactables: Array[Interactable] = map.get_interactables()
	assert_true(not interactables.is_empty(), "на карте есть предметы")
	for interactable: Interactable in interactables:
		var focus: Vector3 = interactable.get_focus_position()
		var front: Vector3 = -interactable.global_basis.z
		front.y = 0.0
		front = front.normalized()
		var scene_name: String = interactable.scene_file_path.get_file().get_basename()
		var distance: float = STAND_DISTANCE_BY_SCENE.get(scene_name, STAND_DISTANCE)
		var feet: Vector3 = interactable.global_position + front * distance
		feet.y = 0.0
		var eye: Vector3 = feet + Vector3.UP * EYE_HEIGHT
		var place: String = "%s (%s)" % [interactable.get_path(), feet]
		assert_true(_stands_on_floor(map, feet) and _capsule_is_free(map, feet), "перед %s есть свободное место" % place)
		assert_true(eye.distance_to(focus) <= interactable.interact_range, "с места перед %s игрок дотягивается до предмета" % place)
		assert_true(_has_line_of_sight(map, eye, focus, interactable), "с места перед %s видна точка предмета %s" % [place, focus])
	await _free_map(map)


## Обход NavCheck: капсула игрока проходит между соседними точками, обход замкнут
## и заходит в каждый проём — так ловится стена на месте двери и реквизит в проходе.
func test_map_is_walkable() -> void:
	var map: GameMap = await _spawn_map()
	if map == null:
		return
	var tour: Array[Marker3D] = _markers(map, NAV_NODE)
	assert_true(tour.size() >= MIN_NAV_MARKERS, "в обходе %s не меньше %d точек (найдено %d)" % [NAV_NODE, MIN_NAV_MARKERS, tour.size()])
	if tour.size() < 2:
		await _free_map(map)
		return
	assert_true(tour[0].global_position.distance_to(tour[-1].global_position) < 0.01, "обход возвращается в начало")
	for index: int in tour.size() - 1:
		var from: Vector3 = tour[index].global_position
		var to: Vector3 = tour[index + 1].global_position
		assert_true(_stands_on_floor(map, from), "точка обхода %s стоит на полу" % tour[index].name)
		assert_true(_capsule_is_free(map, from), "точка обхода %s свободна" % tour[index].name)
		assert_true(_capsule_can_move(map, from, to), "проход от %s %s до %s %s свободен" % [tour[index].name, from, tour[index + 1].name, to])
	var doorways: Array[Node3D] = _instances_at(map, DOORWAY_SCENE)
	assert_true(not doorways.is_empty(), "на карте есть проёмы")
	var labels: Array[Node] = map.find_children("*", "Label3D", true, false)
	for doorway: Node3D in doorways:
		var is_visited: bool = false
		for marker: Marker3D in tour:
			is_visited = is_visited or _flat_distance(marker.global_position, doorway.global_position) <= DOORWAY_REACH
		assert_true(is_visited, "обход проходит через проём %s %s" % [doorway.name, doorway.global_position])
		var signs: int = 0
		for node: Node in labels:
			var label: Label3D = node as Label3D
			if _flat_distance(label.global_position, doorway.global_position) <= SIGN_REACH and not label.text.is_empty():
				signs += 1
		assert_true(signs >= SIGNS_PER_DOORWAY, "над проёмом %s %s есть таблички с обеих сторон" % [doorway.name, doorway.global_position])
	await _free_map(map)


func test_signs_are_readable() -> void:
	var map: GameMap = await _spawn_map()
	if map == null:
		return
	var labels: Array[Node] = map.find_children("*", "Label3D", true, false)
	assert_true(not labels.is_empty(), "на карте есть таблички")
	for node: Node in labels:
		var label: Label3D = node as Label3D
		if label.text.is_empty():
			continue
		var font_file: FontFile = label.font as FontFile
		var variation: FontVariation = label.font as FontVariation
		if variation != null:
			font_file = variation.base_font as FontFile
		assert_true(font_file != null and font_file.resource_path == SIGN_FONT, "табличка «%s» набрана шрифтом Unbounded" % label.text)
		assert_true(label.font_size * label.pixel_size >= MIN_SIGN_EM, "табличка «%s» достаточно крупная" % label.text)
		assert_true(not label.no_depth_test, "табличка «%s» не видна сквозь стены" % label.text)
	await _free_map(map)


## Загружает карту и добавляет её в дерево; ждёт, пока тела попадут в физический мир.
func _spawn_map() -> GameMap:
	var scene: PackedScene = load(MAP_PATH) as PackedScene
	if scene == null:
		assert_true(false, "%s загружается как PackedScene" % MAP_PATH)
		return null
	var root: Node = scene.instantiate()
	var map: GameMap = root as GameMap
	if map == null:
		assert_true(false, "корень %s — GameMap" % MAP_PATH)
		root.free()
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(map)
	for frame: int in SETTLE_FRAMES:
		await tree.physics_frame
	return map


func _free_map(map: GameMap) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	map.queue_free()
	await tree.process_frame


func _markers(map: GameMap, parent_name: String) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	var parent: Node = map.get_node_or_null(NodePath(parent_name))
	if parent == null:
		assert_true(false, "на карте есть узел %s" % parent_name)
		return markers
	for child: Node in parent.get_children():
		var marker: Marker3D = child as Marker3D
		if marker != null:
			markers.append(marker)
	return markers


## Экземпляры игрового префаба scenes/items/<имя>.tscn на карте.
func _instances_of(map: GameMap, scene_name: String) -> Array[Node3D]:
	return _instances_at(map, "%s%s.tscn" % [ITEMS_DIR, scene_name])


func _instances_at(map: GameMap, scene_path: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node in map.find_children("*", "Node3D", true, false):
		if node.scene_file_path == scene_path:
			result.append(node as Node3D)
	return result


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _space(map: GameMap) -> PhysicsDirectSpaceState3D:
	return map.get_world_3d().direct_space_state


## Под точкой (ступни игрока) близко есть пол.
func _stands_on_floor(map: GameMap, feet: Vector3) -> bool:
	var from: Vector3 = feet + Vector3.UP * MAX_FLOOR_GAP
	var to: Vector3 = feet + Vector3.DOWN * MAX_FLOOR_GAP
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return not _space(map).intersect_ray(query).is_empty()


func _capsule_query(feet: Vector3) -> PhysicsShapeQueryParameters3D:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = WORLD_MASK
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (PLAYER_HEIGHT * 0.5 + FLOOR_LIFT))
	return query


## Игрок, стоящий в точке, ни во что не упирается.
func _capsule_is_free(map: GameMap, feet: Vector3) -> bool:
	return _space(map).intersect_shape(_capsule_query(feet), 1).is_empty()


## Игрок проходит по прямой от точки до точки.
func _capsule_can_move(map: GameMap, from: Vector3, to: Vector3) -> bool:
	var query: PhysicsShapeQueryParameters3D = _capsule_query(from)
	query.motion = to - from
	var fractions: PackedFloat32Array = _space(map).cast_motion(query)
	return fractions.size() == 2 and is_equal_approx(fractions[0], 1.0)


## То же правило, что в PlayerInteractor: стены и реквизит закрывают точку предмета.
## Собственные тела предмета не считаются — их учитывает сам префаб своей точкой фокуса.
func _has_line_of_sight(map: GameMap, from: Vector3, to: Vector3, target: Interactable) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var own_bodies: Array[RID] = []
	for node: Node in target.find_children("*", "CollisionObject3D", true, false):
		own_bodies.append((node as CollisionObject3D).get_rid())
	query.exclude = own_bodies
	var hit: Dictionary = _space(map).intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_position: Vector3 = hit["position"]
	return from.distance_to(hit_position) >= from.distance_to(to) - SIGHT_MARGIN
