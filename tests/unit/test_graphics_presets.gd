extends TestCase
## Уровни качества картинки: что выключается на каждом уровне, что авторское окружение не
## портится, и что кнопка главного меню перебирает уровни по кругу.

const STATION_ENVIRONMENT: String = "res://resources/maps/station_environment.tres"
const MENU_SCENE: PackedScene = preload("res://scenes/ui/main_menu.tscn")


func test_high_keeps_authored_environment() -> void:
	var authored: Environment = _make_authored()
	assert_true(GraphicsPresets.tune_environment(authored, GraphicsPresets.Quality.HIGH) == authored,
			"высокий уровень — само авторское окружение")
	assert_true(GraphicsPresets.tune_environment(null, GraphicsPresets.Quality.LOW) == null, "без окружения — null")


func test_medium_drops_screen_space_extras() -> void:
	var authored: Environment = _make_authored()
	var tuned: Environment = GraphicsPresets.tune_environment(authored, GraphicsPresets.Quality.MEDIUM)
	assert_true(tuned != authored, "средний уровень — копия")
	assert_true(not tuned.ssr_enabled and not tuned.ssil_enabled, "отражения и непрямой свет экрана выключены")
	assert_true(tuned.sdfgi_enabled and tuned.volumetric_fog_enabled and tuned.ssao_enabled,
			"отскоки света, дымка и затенение углов остаются")
	assert_near(tuned.ambient_light_energy, authored.ambient_light_energy, "ровный свет не меняется")
	assert_true(authored.ssr_enabled and authored.ssil_enabled, "авторское окружение не тронуто")


func test_low_drops_global_illumination() -> void:
	var authored: Environment = _make_authored()
	var tuned: Environment = GraphicsPresets.tune_environment(authored, GraphicsPresets.Quality.LOW)
	assert_true(not tuned.sdfgi_enabled and not tuned.volumetric_fog_enabled, "отскоки света и дымка выключены")
	assert_true(not tuned.ssr_enabled and not tuned.ssil_enabled, "экранные эффекты выключены")
	assert_near(tuned.ambient_light_energy, GraphicsPresets.LOW_AMBIENT_ENERGY,
			"без отскоков ровный свет поднят, чтобы углы не чернели")
	assert_eq(tuned.tonemap_mode, authored.tonemap_mode, "тональная кривая та же")
	assert_true(authored.sdfgi_enabled and authored.volumetric_fog_enabled, "авторское окружение не тронуто")
	assert_near(authored.ambient_light_energy, 0.3, "ровный свет авторского окружения не тронут")


func test_station_environment_has_what_presets_switch_off() -> void:
	var authored: Environment = load(STATION_ENVIRONMENT) as Environment
	assert_true(authored != null, "окружение станции загружается")
	if authored == null:
		return
	assert_true(authored.sdfgi_enabled, "на высоком уровне станция считает отскоки света")
	var low: Environment = GraphicsPresets.tune_environment(authored, GraphicsPresets.Quality.LOW)
	assert_true(not low.sdfgi_enabled and authored.sdfgi_enabled, "низкий уровень выключает их только в копии")
	assert_true(low.sky == authored.sky, "космос за окнами общий")


func test_levels_are_named_and_cycle() -> void:
	assert_eq(GraphicsPresets.NAMES.size(), GraphicsPresets.Quality.size(), "у каждого уровня есть название")
	assert_eq(GraphicsPresets.FLAG_VALUES.size(), GraphicsPresets.Quality.size(), "у каждого уровня есть значение флага")
	var quality: GraphicsPresets.Quality = GraphicsPresets.Quality.LOW
	var seen: Array[int] = []
	for step: int in GraphicsPresets.Quality.size():
		seen.append(quality)
		quality = GraphicsPresets.next(quality)
	assert_eq(seen.size(), GraphicsPresets.Quality.size(), "перебор обходит все уровни")
	assert_eq(quality, GraphicsPresets.Quality.LOW, "после последнего уровня снова первый")
	assert_eq(GraphicsPresets.sanitize(-1), GraphicsPresets.DEFAULT_QUALITY, "чужое число — уровень по умолчанию")
	assert_eq(GraphicsPresets.sanitize(99), GraphicsPresets.DEFAULT_QUALITY, "слишком большое число — тоже")
	assert_eq(GraphicsPresets.sanitize(0), GraphicsPresets.Quality.LOW, "своё число остаётся")


func test_cheaper_levels_cost_less() -> void:
	assert_eq(GraphicsPresets.get_msaa(GraphicsPresets.Quality.LOW), Viewport.MSAA_DISABLED, "низкий: без MSAA")
	assert_eq(GraphicsPresets.get_msaa(GraphicsPresets.Quality.MEDIUM), Viewport.MSAA_2X, "средний: MSAA 2x")
	assert_eq(GraphicsPresets.get_screen_space_aa(GraphicsPresets.Quality.LOW), Viewport.SCREEN_SPACE_AA_FXAA,
			"без MSAA края сглаживает FXAA")
	assert_true(GraphicsPresets.uses_half_resolution_gi(GraphicsPresets.Quality.MEDIUM), "средний: отскоки в полразрешения")
	assert_true(not GraphicsPresets.uses_half_resolution_gi(GraphicsPresets.Quality.HIGH), "высокий: в полном")
	assert_eq(GraphicsPresets.get_shadow_quality(GraphicsPresets.Quality.LOW, GraphicsPresets.POSITIONAL_SHADOW_SETTING),
			RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "низкий: самые дешёвые мягкие тени")


func test_settings_keep_quality_in_range() -> void:
	var before: GraphicsPresets.Quality = Settings.graphics_quality
	Settings.graphics_quality = GraphicsPresets.Quality.LOW
	assert_eq(Settings.graphics_quality, GraphicsPresets.Quality.LOW, "уровень запоминается")
	Settings.graphics_quality = GraphicsPresets.sanitize(42)
	assert_eq(Settings.graphics_quality, GraphicsPresets.DEFAULT_QUALITY, "мусор заменён уровнем по умолчанию")
	Settings.graphics_quality = before


func test_menu_button_cycles_quality() -> void:
	var before: GraphicsPresets.Quality = Settings.graphics_quality
	Settings.graphics_quality = GraphicsPresets.Quality.HIGH
	var menu: MainMenu = MENU_SCENE.instantiate() as MainMenu
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	# Кадр ожидания: в момент запуска тестов корень дерева ещё добавляет своих детей.
	await tree.process_frame
	tree.root.add_child(menu)
	await tree.process_frame
	var button: Button = menu.get_node(^"%GraphicsButton") as Button
	assert_eq(button.text, GraphicsPresets.quality_name(GraphicsPresets.Quality.HIGH), "кнопка показывает текущий уровень")
	button.pressed.emit()
	assert_eq(Settings.graphics_quality, GraphicsPresets.Quality.LOW, "после высокого идёт низкий")
	assert_eq(button.text, GraphicsPresets.quality_name(GraphicsPresets.Quality.LOW), "кнопка показывает новый уровень")
	button.pressed.emit()
	assert_eq(Settings.graphics_quality, GraphicsPresets.Quality.MEDIUM, "потом средний")
	menu.queue_free()
	await tree.process_frame
	Settings.graphics_quality = before


func test_fps_text() -> void:
	assert_eq(FpsCounter.format(60.0), "60 к/с · 16.7 мс", "кадры в секунду и время кадра")
	assert_eq(FpsCounter.format(143.6), "144 к/с · 7.0 мс", "округление")
	assert_eq(FpsCounter.format(0.0), "— к/с", "пока движок не измерил частоту")


func _make_authored() -> Environment:
	var environment: Environment = Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssr_enabled = true
	environment.ssil_enabled = true
	environment.ssao_enabled = true
	environment.sdfgi_enabled = true
	environment.volumetric_fog_enabled = true
	return environment
