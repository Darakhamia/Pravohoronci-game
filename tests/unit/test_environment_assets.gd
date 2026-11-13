extends TestCase
## Набор станции и реквизит: каждый префаб загружается и получает столкновения на слое мира,
## а модели игрового реквизита (их имена — договор с игровым кодом) лежат на месте и загружаются.

const KIT_DIR: String = "res://scenes/maps/kit"
const PROPS_DIR: String = "res://scenes/maps/props"
const MODELS_DIR: String = "res://assets/models/props"
const ENVIRONMENT_PATH: String = "res://resources/maps/station_environment.tres"
const SCENE_EXTENSION: String = "tscn"
const MODEL_EXTENSION: String = "glb"
## Номер слоя «world» из настроек проекта (layer_names/3d_physics/layer_1).
const WORLD_LAYER: int = 1
## Без этих деталей карту не собрать.
const REQUIRED_KIT: PackedStringArray = [
	"floor", "wall", "wall_doorway", "wall_window", "pillar", "ceiling", "ceiling_light",
]
const MIN_DECOR_PREFABS: int = 14
## Модели, из которых игровой код сам собирает интерактивные объекты.
const GAMEPLAY_MODELS: PackedStringArray = [
	"task_panel", "task_keypad", "task_calibrator", "canister", "canister_rack", "canister_dock",
	"reactor_core", "reactor_panel", "emergency_button", "meeting_table", "weapon_pedestal",
]
## Подвижные части игровых моделей: модель -> имена узлов, которые игровой код ищет внутри.
const MOVING_PARTS: Dictionary[String, PackedStringArray] = {
	"task_calibrator": ["Needle", "Lever"],
	"reactor_core": ["Glow"],
	"reactor_panel": ["Wheel"],
	"emergency_button": ["Button", "Cover"],
}


func test_kit_prefabs_have_world_collision() -> void:
	var names: PackedStringArray = _check_prefabs(KIT_DIR)
	for required: String in REQUIRED_KIT:
		assert_true(names.has(required), "в наборе есть деталь %s" % required)


func test_prop_prefabs_have_world_collision() -> void:
	var names: PackedStringArray = _check_prefabs(PROPS_DIR)
	assert_true(names.size() >= MIN_DECOR_PREFABS, "декора не меньше %d префабов (найдено %d)" % [MIN_DECOR_PREFABS, names.size()])
	for prefab_name: String in names:
		assert_true(not GAMEPLAY_MODELS.has(prefab_name), "%s — игровой реквизит, его префаб собирает игровой код" % prefab_name)


func test_gameplay_models_load() -> void:
	for model_name: String in GAMEPLAY_MODELS:
		var path: String = MODELS_DIR.path_join("%s.%s" % [model_name, MODEL_EXTENSION])
		assert_true(ResourceLoader.exists(path), "%s существует" % path)
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			assert_true(false, "%s загружается как PackedScene" % path)
			continue
		var model: Node = scene.instantiate()
		assert_true(not model.find_children("*", "MeshInstance3D", true, false).is_empty(), "в %s есть меш" % path)
		var parts: PackedStringArray = MOVING_PARTS.get(model_name, PackedStringArray())
		for part: String in parts:
			assert_true(model.find_child(part, true, false) is Node3D, "в %s есть подвижная часть %s" % [path, part])
		model.free()


func test_decor_models_have_prefabs() -> void:
	for file: String in DirAccess.get_files_at(MODELS_DIR):
		if file.get_extension() != MODEL_EXTENSION or GAMEPLAY_MODELS.has(file.get_basename()):
			continue
		var prefab: String = PROPS_DIR.path_join("%s.%s" % [file.get_basename(), SCENE_EXTENSION])
		assert_true(ResourceLoader.exists(prefab), "у декора %s есть префаб %s" % [file, prefab])


func test_station_environment_loads() -> void:
	var environment: Environment = load(ENVIRONMENT_PATH) as Environment
	assert_true(environment != null, "%s загружается как Environment" % ENVIRONMENT_PATH)
	if environment != null:
		assert_true(environment.glow_enabled, "в окружении станции включён glow: на него рассчитаны светящиеся детали")


## Проверяет все префабы папки и возвращает их имена без расширения.
func _check_prefabs(dir_path: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() != SCENE_EXTENSION:
			continue
		names.append(file.get_basename())
		var path: String = dir_path.path_join(file)
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			assert_true(false, "%s загружается как PackedScene" % path)
			continue
		var prefab: Node = scene.instantiate()
		assert_true(prefab is Node3D, "корень %s — Node3D" % path)
		assert_true(not prefab.find_children("*", "MeshInstance3D", true, false).is_empty(), "в %s есть модель" % path)
		var bodies: Array[Node] = prefab.find_children("*", "StaticBody3D", true, false)
		assert_true(not bodies.is_empty(), "в %s есть StaticBody3D" % path)
		for node: Node in bodies:
			var body: StaticBody3D = node as StaticBody3D
			assert_true(body.get_collision_layer_value(WORLD_LAYER), "%s: тело %s лежит на слое мира" % [path, body.name])
			assert_true(_count_shapes(body) > 0, "%s: у тела %s есть хотя бы одна форма столкновений" % [path, body.name])
		prefab.free()
	assert_true(not names.is_empty(), "в %s есть префабы" % dir_path)
	return names


func _count_shapes(body: StaticBody3D) -> int:
	var count: int = 0
	for child: Node in body.get_children():
		var shape_node: CollisionShape3D = child as CollisionShape3D
		if shape_node != null and shape_node.shape != null:
			count += 1
	return count
