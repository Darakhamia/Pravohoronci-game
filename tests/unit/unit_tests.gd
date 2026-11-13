extends Node
## Запускает модульные тесты без плагинов:
##   godot --headless res://tests/unit/unit_tests.tscn
## Код выхода 0 — всё прошло, 1 — есть провалы.
## Ошибка скрипта обрывает тест без провала: её ловит tests/run_tests.sh по строке SCRIPT ERROR.

const TEST_PREFIX: String = "test_"
## Новый файл с тестами добавляется сюда.
const TEST_SCRIPTS: Array[GDScript] = [
	preload("res://tests/unit/test_cmd_args.gd"),
	preload("res://tests/unit/test_player_name.gd"),
	preload("res://tests/unit/test_player_input.gd"),
]


func _ready() -> void:
	var passed: int = 0
	var failed: int = 0
	for script: GDScript in TEST_SCRIPTS:
		var test_case: TestCase = script.new() as TestCase
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with(TEST_PREFIX):
				continue
			var failures_before: int = test_case.failures.size()
			test_case.current_test = method_name
			test_case.call(method_name)
			if test_case.failures.size() == failures_before:
				passed += 1
			else:
				failed += 1
		for failure: String in test_case.failures:
			print("FAIL %s::%s" % [script.resource_path.get_file(), failure])
	print("UNIT: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
