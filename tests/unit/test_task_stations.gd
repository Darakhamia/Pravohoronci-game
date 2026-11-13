extends TestCase
## Чистые правила станций заданий: зелёная зона калибровки и код терминала.

const FILL_SEC: float = 3.0
const ZONE_START: float = 0.55
const ZONE_END: float = 0.8
const TOLERANCE_SEC: float = 0.1
const SEED: int = 777


func test_release_inside_the_zone_counts() -> void:
	assert_true(_in_zone(1.65), "начало зоны")
	assert_true(_in_zone(2.0), "середина зоны")
	assert_true(_in_zone(2.4), "конец зоны")


func test_release_within_tolerance_of_the_zone_counts() -> void:
	assert_true(_in_zone(1.56), "чуть раньше зоны — в пределах запаса")
	assert_true(_in_zone(2.49), "чуть позже зоны — в пределах запаса")


func test_release_outside_the_zone_fails() -> void:
	assert_true(not _in_zone(0.0), "сразу отпустил")
	assert_true(not _in_zone(0.5), "слишком рано")
	assert_true(not _in_zone(1.5), "раньше зоны и запаса")
	assert_true(not _in_zone(2.55), "позже зоны и запаса")
	assert_true(not _in_zone(FILL_SEC), "додержал до конца")
	assert_true(not _in_zone(-1.0), "отрицательное время")


func test_zone_without_tolerance_is_exact() -> void:
	assert_true(not TaskCalibrator.is_in_zone(1.6, FILL_SEC, ZONE_START, ZONE_END, 0.0), "без запаса: раньше зоны")
	assert_true(TaskCalibrator.is_in_zone(1.7, FILL_SEC, ZONE_START, ZONE_END, 0.0), "без запаса: внутри зоны")
	assert_true(not TaskCalibrator.is_in_zone(2.45, FILL_SEC, ZONE_START, ZONE_END, 0.0), "без запаса: позже зоны")


func test_broken_zone_never_counts() -> void:
	assert_true(not TaskCalibrator.is_in_zone(1.0, 0.0, ZONE_START, ZONE_END, TOLERANCE_SEC), "шкала без длительности")
	assert_true(not TaskCalibrator.is_in_zone(2.0, FILL_SEC, ZONE_END, ZONE_START, TOLERANCE_SEC), "конец зоны раньше начала")


func test_default_zone_ends_before_the_hold_grace_window() -> void:
	# Отпускание в последние HOLD_GRACE_SEC считается удержанием до конца, то есть переливом:
	# зона вместе с запасом должна заканчиваться раньше.
	var scene: PackedScene = load("res://scenes/items/task_calibrator.tscn") as PackedScene
	var calibrator: TaskCalibrator = scene.instantiate() as TaskCalibrator
	assert_true(calibrator != null, "сцена калибратора — TaskCalibrator")
	if calibrator == null:
		return
	var zone_end_sec: float = calibrator.zone_end * calibrator.hold_seconds + TaskCalibrator.RELEASE_TOLERANCE_SEC
	assert_true(zone_end_sec < calibrator.hold_seconds - PlayerInteractor.HOLD_GRACE_SEC,
			"зона калибратора кончается до окна «додержал до конца»")
	assert_true(calibrator.zone_start < calibrator.zone_end, "зона не пустая")
	assert_true(calibrator.zone_start * calibrator.hold_seconds - TaskCalibrator.RELEASE_TOLERANCE_SEC > 0.5,
			"случайное короткое нажатие в зону не попадает")
	calibrator.free()


func test_code_has_four_digits() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var seen: Dictionary[String, bool] = {}
	for attempt: int in 200:
		var code: String = TaskKeypad.make_code(rng)
		assert_eq(code.length(), TaskKeypad.CODE_LENGTH, "длина кода \"%s\"" % code)
		assert_true(code.is_valid_int() and not code.begins_with("-") and not code.begins_with("+"),
				"код \"%s\" состоит из цифр" % code)
		seen[code] = true
	assert_true(seen.size() > 150, "коды разные: %d из 200" % seen.size())


func test_code_is_deterministic_for_the_same_seed() -> void:
	var first: RandomNumberGenerator = RandomNumberGenerator.new()
	first.seed = SEED
	var second: RandomNumberGenerator = RandomNumberGenerator.new()
	second.seed = SEED
	assert_eq(TaskKeypad.make_code(first), TaskKeypad.make_code(second), "тот же seed — тот же код")


func test_prefabs_have_the_expected_classes() -> void:
	var expected: Dictionary[String, String] = {
		"res://scenes/items/task_wiring.tscn": "TaskWiring",
		"res://scenes/items/task_keypad.tscn": "TaskKeypad",
		"res://scenes/items/task_calibrator.tscn": "TaskCalibrator",
		"res://scenes/items/task_fuel_dock.tscn": "TaskFuelDock",
		"res://scenes/items/canister_rack.tscn": "CanisterRack",
		"res://scenes/items/reactor_panel.tscn": "ReactorPanel",
		"res://scenes/items/reactor_core.tscn": "ReactorCore",
		"res://scenes/items/sabotage_alarm.tscn": "SabotageAlarm",
	}
	for path: String in expected:
		var scene: PackedScene = load(path) as PackedScene
		assert_true(scene != null, "%s загружается" % path)
		if scene == null:
			continue
		var node: Node = scene.instantiate()
		var script: Script = node.get_script() as Script
		assert_eq(String(script.get_global_name()) if script != null else "", expected[path], "класс корня %s" % path)
		var station: TaskStation = node as TaskStation
		if station != null:
			assert_true(not station.title.is_empty(), "у станции %s есть название" % path)
		var interactable: Interactable = node as Interactable
		if interactable != null:
			assert_true(not interactable.prompt.is_empty(), "у предмета %s есть подсказка" % path)
			assert_true(interactable.get_node_or_null(^"Marker") is TaskMarker, "у предмета %s есть метка" % path)
		node.free()


func test_canister_is_a_carried_item_with_a_model() -> void:
	var canister: ItemConfig = TaskFuelDock.CANISTER
	assert_true(canister.model != null, "у канистры есть модель")
	assert_true(PlayerWeapons.ITEMS.index_of(canister) > PlayerWeapons.EMPTY_HANDS, "канистра есть в наборе предметов")


func _in_zone(held_seconds: float) -> bool:
	return TaskCalibrator.is_in_zone(held_seconds, FILL_SEC, ZONE_START, ZONE_END, TOLERANCE_SEC)
