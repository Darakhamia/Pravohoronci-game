class_name TestCase
extends RefCounted
## База для модульных тестов: наследник объявляет методы test_*, запускает их unit_tests.gd.

## Имя выполняемого метода — попадает в текст ошибки. Ставит запускающий скрипт.
var current_test: String = ""
## Накопленные сообщения о провалах.
var failures: PackedStringArray = []


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


## Типы тоже должны совпасть: 1 и 1.0 — разные значения.
func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("%s: получено %s, ожидалось %s" % [message, var_to_str(actual), var_to_str(expected)])


## Для дробных чисел, где точное сравнение ломается на погрешности.
func assert_near(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_fail("%s: получено %s, ожидалось около %s" % [message, var_to_str(actual), var_to_str(expected)])


func _fail(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])
