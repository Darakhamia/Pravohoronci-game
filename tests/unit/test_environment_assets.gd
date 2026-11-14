extends TestCase
## Набор станции и реквизит: каждый префаб загружается и получает столкновения на слое мира,
## а модели игрового реквизита (их имена — договор с игровым кодом) лежат на месте и загружаются.
## Вид станции: у каждого материала env_* из моделей есть материал в библиотеке resources/materials,
## и импорт каждой модели подменяет им встроенный; префабы света и декалей загружаются; ключевой свет и
## солнце настроены по рецепту, стекло не затуманивает фон, тёмные тона не чернее настоящей краски.

const KIT_DIR: String = "res://scenes/maps/kit"
const PROPS_DIR: String = "res://scenes/maps/props"
const MODELS_DIR: String = "res://assets/models/props"
const KIT_MODELS_DIR: String = "res://assets/models/kit"
const ENVIRONMENT_PATH: String = "res://resources/maps/station_environment.tres"
const MATERIALS_DIR: String = "res://resources/materials"
const LIGHTS_DIR: String = "res://scenes/maps/lights"
const DECALS_DIR: String = "res://scenes/maps/decals"
const MATERIAL_PREFIX: String = "env_"
const MATERIAL_EXTENSION: String = "tres"
const IMPORT_SUFFIX: String = ".import"
## Смещение длины JSON-блока в заголовке .glb и начало самого блока.
const GLB_JSON_LENGTH_OFFSET: int = 12
const GLB_JSON_OFFSET: int = 20
## Имя узла-светильника внутри префаба ceiling_light: по нему игровой код гасит свет.
const CEILING_LIGHT_PREFAB: String = "res://scenes/maps/kit/ceiling_light.tscn"
const CEILING_LIGHT_NODE: String = "Light"
## Префабы света, без которых рецепт освещения не собрать.
const REQUIRED_LIGHTS: PackedStringArray = [
	"key_light", "accent_desk_lamp", "accent_strip_cool", "accent_emergency", "sun_light", "reflection_probe_room",
]
const KEY_LIGHT_PREFAB: String = "res://scenes/maps/lights/key_light.tscn"
const SUN_LIGHT_PREFAB: String = "res://scenes/maps/lights/sun_light.tscn"
## Солнце дальше этого расстояния теней не рисует: больше — и край солнечного пятна идёт лесенкой.
const MAX_SUN_SHADOW_DISTANCE: float = 20.0
## Тёмные тона стен и пола (sRGB): темнее этого не бывает ни краска, ни резина, и отскоку света
## нечего возвращать — низ комнаты, где лежат тела и ползают игроки, проваливается в черноту.
const DARK_TONES: PackedStringArray = ["env_deep", "env_panel", "env_line"]
const MIN_DARK_TONE_VALUE: float = 0.35
## Самый яркий допустимый цвет стекла при смешивании premultiplied alpha (там цвет прибавляется к фону).
const MAX_PREMULTIPLIED_ALBEDO: float = 0.02
const MIN_DECAL_PREFABS: int = 8
## Tonemap AgX: под него подобраны яркости ламп и свечения.
const TONEMAP_AGX: int = 4
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


func test_station_environment_is_realistic() -> void:
	var environment: Environment = load(ENVIRONMENT_PATH) as Environment
	if environment == null:
		assert_true(false, "%s загружается как Environment" % ENVIRONMENT_PATH)
		return
	assert_true(environment.tonemap_mode == TONEMAP_AGX, "тональная кривая окружения — AgX")
	assert_true(environment.sdfgi_enabled, "в окружении включён SDFGI: отражённый свет вместо ровного ambient")
	assert_true(environment.ssao_enabled, "в окружении включён SSAO")
	assert_true(environment.volumetric_fog_enabled, "в окружении включена объёмная дымка")
	assert_true(environment.sky != null and environment.sky.sky_material is ShaderMaterial, "у окружения есть небо-космос")


func test_model_materials_come_from_library() -> void:
	var model_dirs: PackedStringArray = [KIT_MODELS_DIR, MODELS_DIR]
	var checked: int = 0
	for dir_path: String in model_dirs:
		for file: String in DirAccess.get_files_at(dir_path):
			if file.get_extension() != MODEL_EXTENSION:
				continue
			var path: String = dir_path.path_join(file)
			var remap: Dictionary = _material_remap(path)
			for material_name: String in _glb_material_names(path):
				if not material_name.begins_with(MATERIAL_PREFIX):
					continue
				checked += 1
				var library_path: String = MATERIALS_DIR.path_join("%s.%s" % [material_name, MATERIAL_EXTENSION])
				assert_true(load(library_path) is BaseMaterial3D, "в библиотеке есть материал %s" % library_path)
				var target: String = remap.get(material_name, "")
				assert_true(target.begins_with(MATERIALS_DIR), "%s: импорт подменяет %s материалом библиотеки" % [path, material_name])
				if target != "":
					assert_true(load(target) is BaseMaterial3D, "%s: материал %s загружается" % [path, target])
			_check_imported_materials(path)
	assert_true(checked > 0, "в моделях набора и реквизита есть материалы %s*" % MATERIAL_PREFIX)


func test_light_prefabs_load() -> void:
	for light_name: String in REQUIRED_LIGHTS:
		var path: String = LIGHTS_DIR.path_join("%s.%s" % [light_name, SCENE_EXTENSION])
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			assert_true(false, "%s загружается как PackedScene" % path)
			continue
		var prefab: Node = scene.instantiate()
		var has_source: bool = prefab is Light3D or prefab is ReflectionProbe or not prefab.find_children("*", "Light3D", true, false).is_empty()
		assert_true(has_source, "в %s есть источник света или зонд отражений" % path)
		prefab.free()
	var ceiling_scene: PackedScene = load(CEILING_LIGHT_PREFAB) as PackedScene
	if ceiling_scene == null:
		assert_true(false, "%s загружается как PackedScene" % CEILING_LIGHT_PREFAB)
		return
	var ceiling_light: Node = ceiling_scene.instantiate()
	assert_true(ceiling_light.get_node_or_null(CEILING_LIGHT_NODE) is Light3D, "в ceiling_light есть светильник %s" % CEILING_LIGHT_NODE)
	ceiling_light.free()


func test_key_light_casts_shadows_and_highlights() -> void:
	var scene: PackedScene = load(KEY_LIGHT_PREFAB) as PackedScene
	if scene == null:
		assert_true(false, "%s загружается как PackedScene" % KEY_LIGHT_PREFAB)
		return
	var light: OmniLight3D = scene.instantiate() as OmniLight3D
	assert_true(light != null, "ключевой свет — OmniLight3D: он освещает стены и потолок, а не только пол")
	if light != null:
		assert_true(light.shadow_enabled, "ключевой свет отбрасывает тени: без них он светит сквозь стены")
		assert_true(light.light_specular > 0.0, "ключевой свет даёт блики: без них металл и пластик выглядят матовыми")
		light.free()


func test_sun_shadows_are_fine_grained() -> void:
	var scene: PackedScene = load(SUN_LIGHT_PREFAB) as PackedScene
	if scene == null:
		assert_true(false, "%s загружается как PackedScene" % SUN_LIGHT_PREFAB)
		return
	var prefab: Node = scene.instantiate()
	var suns: Array[Node] = prefab.find_children("*", "DirectionalLight3D", true, false)
	assert_true(suns.size() == 1, "в %s ровно одно солнце" % SUN_LIGHT_PREFAB)
	for node: Node in suns:
		var sun: DirectionalLight3D = node as DirectionalLight3D
		assert_true(sun.shadow_enabled, "солнце отбрасывает тени")
		assert_true(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "у теней солнца четыре каскада")
		assert_true(sun.directional_shadow_max_distance <= MAX_SUN_SHADOW_DISTANCE, "тени солнца не дальше %d м (сейчас %.1f)" % [int(MAX_SUN_SHADOW_DISTANCE), sun.directional_shadow_max_distance])
	prefab.free()


func test_transparent_materials_do_not_fog_the_background() -> void:
	var checked: int = 0
	for file: String in DirAccess.get_files_at(MATERIALS_DIR):
		if file.get_extension() != MATERIAL_EXTENSION:
			continue
		var material: BaseMaterial3D = load(MATERIALS_DIR.path_join(file)) as BaseMaterial3D
		if material == null or material.blend_mode != BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA:
			continue
		checked += 1
		var albedo: Color = material.albedo_color
		var brightest: float = maxf(albedo.r, maxf(albedo.g, albedo.b))
		assert_true(brightest <= MAX_PREMULTIPLIED_ALBEDO, "%s: при смешивании premultiplied цвет должен быть чёрным, иначе стекло светится молочной вуалью" % file)
	assert_true(checked > 0, "в библиотеке есть стекло со смешиванием premultiplied (env_glass)")


func test_dark_tones_still_bounce_light() -> void:
	for material_name: String in DARK_TONES:
		var path: String = MATERIALS_DIR.path_join("%s.%s" % [material_name, MATERIAL_EXTENSION])
		var material: BaseMaterial3D = load(path) as BaseMaterial3D
		if material == null:
			assert_true(false, "%s загружается" % path)
			continue
		var albedo: Color = material.albedo_color
		var brightest: float = maxf(albedo.r, maxf(albedo.g, albedo.b))
		assert_true(brightest >= MIN_DARK_TONE_VALUE, "%s не темнее %.2f (сейчас %.2f): иначе низ стен и пол проваливаются в черноту" % [material_name, MIN_DARK_TONE_VALUE, brightest])


func test_decal_prefabs_load() -> void:
	var count: int = 0
	for file: String in DirAccess.get_files_at(DECALS_DIR):
		if file.get_extension() != SCENE_EXTENSION:
			continue
		count += 1
		var path: String = DECALS_DIR.path_join(file)
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			assert_true(false, "%s загружается как PackedScene" % path)
			continue
		var decal: Decal = scene.instantiate() as Decal
		assert_true(decal != null, "корень %s — Decal" % path)
		if decal != null:
			assert_true(decal.texture_albedo != null, "у декали %s есть текстура" % path)
			decal.free()
	assert_true(count >= MIN_DECAL_PREFABS, "декалей не меньше %d (найдено %d)" % [MIN_DECAL_PREFABS, count])


## Имена материалов из JSON-блока файла .glb (в том виде, в каком их записал генератор моделей).
func _glb_material_names(path: String) -> PackedStringArray:
	var names: PackedStringArray = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		assert_true(false, "%s открывается для чтения" % path)
		return names
	file.seek(GLB_JSON_LENGTH_OFFSET)
	var length: int = file.get_32()
	file.seek(GLB_JSON_OFFSET)
	var document: Variant = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	file.close()
	if not document is Dictionary:
		assert_true(false, "в %s читается описание glTF" % path)
		return names
	var materials: Array = (document as Dictionary).get("materials", [])
	for material: Variant in materials:
		var material_name: String = (material as Dictionary).get("name", "")
		names.append(material_name)
	return names


## Замены материалов из файла .import модели: имя материала -> путь материала библиотеки.
func _material_remap(model_path: String) -> Dictionary:
	var result: Dictionary = {}
	var config: ConfigFile = ConfigFile.new()
	if config.load(model_path + IMPORT_SUFFIX) != OK:
		assert_true(false, "%s%s читается" % [model_path, IMPORT_SUFFIX])
		return result
	var subresources: Dictionary = config.get_value("params", "_subresources", {})
	var materials: Dictionary = subresources.get("materials", {})
	for material_name: String in materials:
		var settings: Dictionary = materials[material_name]
		if settings.get("use_external/enabled", false):
			result[material_name] = settings.get("use_external/path", "")
	return result


## Импортированная модель действительно использует материалы библиотеки (а не встроенные в .glb).
func _check_imported_materials(model_path: String) -> void:
	var scene: PackedScene = load(model_path) as PackedScene
	if scene == null:
		assert_true(false, "%s загружается как PackedScene" % model_path)
		return
	var model: Node = scene.instantiate()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(surface)
			var material_path: String = material.resource_path if material != null else ""
			assert_true(material_path.begins_with(MATERIALS_DIR), "%s: поверхность %d меша %s берёт материал из библиотеки (сейчас «%s»)" % [model_path, surface, node.name, material_path])
	model.free()


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
