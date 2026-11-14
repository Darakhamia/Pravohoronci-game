extends Node
## Запускает модульные тесты без плагинов:
##   godot --headless res://tests/unit/unit_tests.tscn
## Тесты — все файлы test_*.gd в этой папке: класс наследует TestCase, методы test_* без
## параметров (можно с await). Код выхода 0 — всё прошло, 1 — есть провалы или тестов нет.
## Ошибка скрипта обрывает тест без провала: её ловит tests/run_tests.sh по строке SCRIPT ERROR.

const TEST_DIR: String = "res://tests/unit"
const TEST_PREFIX: String = "test_"
const SCRIPT_EXTENSION: String = "gd"
## База для тестов лежит рядом и тоже начинается с test_.
const BASE_FILE: String = "test_case.gd"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	for file: String in _find_test_files():
		await _run_file(file)
	if _passed + _failed == 0:
		_report_failure(TEST_DIR, "не найдено ни одного теста")
	print("UNIT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _find_test_files() -> PackedStringArray:
	var files: PackedStringArray = []
	for file: String in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with(TEST_PREFIX) and file.get_extension() == SCRIPT_EXTENSION and file != BASE_FILE:
			files.append(file)
	files.sort()
	return files


func _run_file(file: String) -> void:
	# Грузим здесь, а не через preload: файл с ошибкой не должен ронять весь запуск.
	var script: GDScript = load(TEST_DIR.path_join(file)) as GDScript
	var test_case: TestCase = null
	if script != null and script.can_instantiate():
		test_case = script.new() as TestCase
	if test_case == null:
		_report_failure(file, "файл не загрузился или не наследует TestCase")
		return
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with(TEST_PREFIX):
			continue
		var arguments: Array = method["args"]
		if not arguments.is_empty():
			_report_failure(file, "%s: у теста не должно быть параметров" % method_name)
			continue
		var failures_before: int = test_case.failures.size()
		test_case.current_test = method_name
		# await нужен тестам-корутинам; для обычных методов он ничего не меняет.
		await test_case.call(method_name)
		if test_case.failures.size() == failures_before:
			_passed += 1
		else:
			_failed += 1
	for failure: String in test_case.failures:
		print("FAIL %s::%s" % [file, failure])


func _report_failure(file: String, message: String) -> void:
	_failed += 1
	print("FAIL %s: %s" % [file, message])
