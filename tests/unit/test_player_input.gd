extends TestCase
## PlayerInput: сервер получает ввод от клиента и обязан пережить любой мусор.

const HUGE: float = 1.0e30
const UNIT_TOLERANCE: float = 0.0001


func test_sanitize_direction_keeps_valid() -> void:
	assert_eq(PlayerInput.sanitize_direction(Vector2.ZERO), Vector2.ZERO, "нет ввода")
	assert_eq(PlayerInput.sanitize_direction(Vector2(0.0, -1.0)), Vector2(0.0, -1.0), "вперёд")
	assert_eq(PlayerInput.sanitize_direction(Vector2(0.5, 0.25)), Vector2(0.5, 0.25), "короче единицы не трогаем")


## Иначе клиент мог бы прислать (100, 0) и бегать в сто раз быстрее.
func test_sanitize_direction_limits_length() -> void:
	_assert_direction_near(PlayerInput.sanitize_direction(Vector2(3.0, 4.0)), Vector2(0.6, 0.8), "длинный вектор")
	_assert_direction_near(PlayerInput.sanitize_direction(Vector2(1.0, 1.0)), Vector2(1.0, 1.0).normalized(), "диагональ")
	_assert_direction_near(PlayerInput.sanitize_direction(Vector2(-100.0, 0.0)), Vector2(-1.0, 0.0), "спидхак")
	var huge: Vector2 = PlayerInput.sanitize_direction(Vector2(HUGE, -HUGE))
	assert_true(huge.is_finite(), "огромный вектор остаётся конечным")
	assert_true(huge.length() <= 1.0 + UNIT_TOLERANCE, "огромный вектор не длиннее единицы")


func test_sanitize_direction_rejects_non_finite() -> void:
	assert_eq(PlayerInput.sanitize_direction(Vector2(NAN, 0.0)), Vector2.ZERO, "NaN по x")
	assert_eq(PlayerInput.sanitize_direction(Vector2(0.5, NAN)), Vector2.ZERO, "NaN по y")
	assert_eq(PlayerInput.sanitize_direction(Vector2(INF, 0.0)), Vector2.ZERO, "inf")
	assert_eq(PlayerInput.sanitize_direction(Vector2(0.0, -INF)), Vector2.ZERO, "-inf")
	assert_eq(PlayerInput.sanitize_direction(Vector2(INF, NAN)), Vector2.ZERO, "inf и NaN")


func test_sanitize_yaw_keeps_range() -> void:
	assert_eq(PlayerInput.sanitize_yaw(0.0), 0.0, "ноль")
	assert_eq(PlayerInput.sanitize_yaw(1.5), 1.5, "внутри диапазона")
	assert_eq(PlayerInput.sanitize_yaw(-3.0), -3.0, "внутри диапазона, отрицательный")
	assert_eq(PlayerInput.sanitize_yaw(PI), PI, "граница PI")
	assert_eq(PlayerInput.sanitize_yaw(-PI), -PI, "граница -PI")


func test_sanitize_yaw_wraps() -> void:
	assert_near(PlayerInput.sanitize_yaw(PI + 0.5), -PI + 0.5, "чуть больше PI")
	assert_near(PlayerInput.sanitize_yaw(-PI - 0.5), PI - 0.5, "чуть меньше -PI")
	assert_near(PlayerInput.sanitize_yaw(TAU * 10.0 + 1.0), 1.0, "десять оборотов")
	assert_near(PlayerInput.sanitize_yaw(-TAU * 10.0 - 1.0), -1.0, "десять оборотов назад")
	for value: float in [1.0e6, -1.0e6, 1.0e18, -1.0e18, 1.0e300, -1.0e300]:
		var wrapped: float = PlayerInput.sanitize_yaw(value)
		assert_true(is_finite(wrapped) and absf(wrapped) <= PI, "sanitize_yaw(%s) = %s вне [-PI, PI]" % [value, wrapped])


func test_sanitize_yaw_rejects_non_finite() -> void:
	assert_eq(PlayerInput.sanitize_yaw(NAN), 0.0, "NaN")
	assert_eq(PlayerInput.sanitize_yaw(INF), 0.0, "inf")
	assert_eq(PlayerInput.sanitize_yaw(-INF), 0.0, "-inf")


func test_sanitize_pitch() -> void:
	assert_true(PlayerInput.MAX_PITCH > deg_to_rad(80.0) and PlayerInput.MAX_PITCH < PI / 2.0, "MAX_PITCH чуть меньше 90 градусов")
	assert_eq(PlayerInput.sanitize_pitch(0.0), 0.0, "ноль")
	assert_eq(PlayerInput.sanitize_pitch(-0.5), -0.5, "внутри диапазона")
	assert_eq(PlayerInput.sanitize_pitch(PlayerInput.MAX_PITCH), PlayerInput.MAX_PITCH, "граница")
	assert_eq(PlayerInput.sanitize_pitch(10.0), PlayerInput.MAX_PITCH, "выше границы")
	assert_eq(PlayerInput.sanitize_pitch(-10.0), -PlayerInput.MAX_PITCH, "ниже границы")
	assert_eq(PlayerInput.sanitize_pitch(HUGE), PlayerInput.MAX_PITCH, "огромное значение")
	assert_eq(PlayerInput.sanitize_pitch(NAN), 0.0, "NaN")
	assert_eq(PlayerInput.sanitize_pitch(INF), 0.0, "inf")
	assert_eq(PlayerInput.sanitize_pitch(-INF), 0.0, "-inf")


## Серверная сторона узла: то, что отдаётся симуляции, уже очищено.
func test_receive_stores_sanitized_input() -> void:
	var input := PlayerInput.new()
	assert_true(not input.has_input(), "до первого пакета ввода нет")
	assert_eq(input.get_move_direction(), Vector2.ZERO, "до первого пакета игрок стоит")
	input.receive(Vector2(0.0, -50.0), PI + 0.5, 10.0)
	assert_true(input.has_input(), "ввод принят")
	_assert_direction_near(input.get_move_direction(), Vector2(0.0, -1.0), "направление ограничено")
	assert_near(input.get_yaw(), -PI + 0.5, "yaw завёрнут")
	assert_eq(input.get_pitch(), PlayerInput.MAX_PITCH, "pitch зажат")
	input.receive(Vector2(NAN, INF), NAN, -INF)
	assert_eq(input.get_move_direction(), Vector2.ZERO, "мусор вместо направления")
	assert_eq(input.get_yaw(), 0.0, "мусор вместо yaw")
	assert_eq(input.get_pitch(), 0.0, "мусор вместо pitch")
	input.free()


func test_jump_is_consumed_once() -> void:
	var input := PlayerInput.new()
	assert_true(not input.consume_jump(), "прыжка в очереди нет")
	input.queue_jump()
	input.queue_jump()
	assert_true(input.consume_jump(), "прыжок в очереди")
	assert_true(not input.consume_jump(), "второй раз тот же прыжок не срабатывает")
	input.free()


func _assert_direction_near(actual: Vector2, expected: Vector2, message: String) -> void:
	assert_true(actual.is_equal_approx(expected), "%s: получено %s, ожидалось около %s" % [message, actual, expected])
