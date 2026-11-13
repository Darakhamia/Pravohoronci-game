extends TestCase
## SnapshotInterpolator: показанное движение должно быть ровным при любой частоте кадров
## клиента и не ломаться от потерь, пачек и повторов снимков.

const TICKS_PER_SECOND: float = 60.0
const TICK_SEC: float = 1.0 / TICKS_PER_SECOND
## Скорость игрока, м/с.
const SPEED: float = 5.0
const STEP: Vector3 = Vector3(SPEED * TICK_SEC, 0.0, 0.0)
## Допуск на равномерность, м/с: остаётся только погрешность 32-битных координат.
const SPEED_TOLERANCE: float = 0.002


func test_uniform_motion_is_smooth_at_any_frame_rate() -> void:
	for fps: float in [20.0, 30.0, 60.0, 100.0, 144.0, 240.0]:
		var worst: float = _worst_speed_error(fps, func(_tick: int) -> bool: return true)
		assert_true(worst < SPEED_TOLERANCE, "%d кадров/с: скорость кадра отличается на %f м/с" % [int(fps), worst])


func test_lost_snapshot_causes_no_jerk() -> void:
	# Каждый седьмой снимок теряется: следующий приходит с разрывом в два тика.
	var worst: float = _worst_speed_error(144.0, func(tick: int) -> bool: return tick % 7 != 0)
	assert_true(worst < SPEED_TOLERANCE, "потеря снимка: скорость кадра отличается на %f м/с" % worst)


func test_shown_position_stays_close_to_latest_snapshot() -> void:
	# Ровное движение при 144 кадрах/с: показ не обгоняет настоящую позицию
	# и отстаёт от неё меньше чем на два тика.
	var interpolator := _started_at(Vector3.ZERO, 0)
	var frame_sec: float = 1.0 / 144.0
	var sent_tick: int = 0
	for frame: int in range(1, 600):
		var now: float = frame * frame_sec
		while (sent_tick + 1) * TICK_SEC <= now:
			sent_tick += 1
			interpolator.push(STEP * sent_tick, sent_tick)
		var shown: Vector3 = interpolator.advance(frame_sec, TICKS_PER_SECOND)
		var behind_ticks: float = (SPEED * now - shown.x) / STEP.x
		assert_true(behind_ticks > -0.01 and behind_ticks < 2.01, "кадр %d: отставание %f тиков" % [frame, behind_ticks])


func test_duplicate_and_stale_snapshots_are_ignored() -> void:
	var interpolator := _started_at(Vector3.ZERO, 10)
	interpolator.push(STEP, 11)
	var before: Vector3 = interpolator.advance(TICK_SEC, TICKS_PER_SECOND)
	# Тот же тик с другой позицией и более старый тик: оба игнорируются.
	interpolator.push(STEP * 50.0, 11)
	interpolator.push(STEP * -50.0, 5)
	var after: Vector3 = interpolator.advance(0.0, TICKS_PER_SECOND)
	assert_true(before.is_equal_approx(after), "повтор и старый пакет не сдвигают позицию")


func test_standing_still_stays_put() -> void:
	var spot := Vector3(3.0, 0.0, -2.0)
	var interpolator := _started_at(spot, 100)
	for tick: int in range(101, 200):
		interpolator.push(spot, tick)
		var shown: Vector3 = interpolator.advance(TICK_SEC * 0.4, TICKS_PER_SECOND)
		assert_true(shown.is_equal_approx(spot), "тик %d: стоящий игрок не двигается" % tick)


func test_teleport_snaps() -> void:
	var interpolator := _started_at(Vector3.ZERO, 1)
	interpolator.push(STEP, 2)
	interpolator.advance(TICK_SEC, TICKS_PER_SECOND)
	var far := Vector3(0.0, 0.0, SnapshotInterpolator.SNAP_DISTANCE + 1.0)
	interpolator.push(far, 3)
	var shown: Vector3 = interpolator.advance(TICK_SEC * 0.5, TICKS_PER_SECOND)
	assert_true(shown.is_equal_approx(far), "телепорт показывается сразу, без подплывания")


func test_late_snapshot_extrapolates_within_limit() -> void:
	var interpolator := _started_at(Vector3.ZERO, 1)
	interpolator.push(STEP, 2)
	# Снимков нет полсекунды: движение продолжается по прямой, но не дальше лимита.
	var shown: Vector3 = interpolator.advance(0.5, TICKS_PER_SECOND)
	var limit: float = STEP.x * (1.0 + SnapshotInterpolator.MAX_EXTRAPOLATION_TICKS)
	assert_true(shown.x > STEP.x * 2.5 and shown.x <= limit + 0.0001, "экстраполяция ограничена: %f при лимите %f" % [shown.x, limit])


func test_burst_after_hitch_catches_up() -> void:
	var interpolator := _started_at(Vector3.ZERO, 0)
	# Кадр подвис на полсекунды, потом все накопившиеся снимки пришли разом.
	interpolator.advance(0.5, TICKS_PER_SECOND)
	for tick: int in range(1, 31):
		interpolator.push(STEP * tick, tick)
	var shown: Vector3 = interpolator.advance(TICK_SEC, TICKS_PER_SECOND)
	var behind_ticks: float = (STEP.x * 30.0 - shown.x) / STEP.x
	assert_true(behind_ticks >= 0.0 and behind_ticks <= SnapshotInterpolator.MAX_LAG_TICKS,
			"после пачки показ рядом с последним снимком, отставание %f тиков" % behind_ticks)


## Интерполятор после спавна: кадр, в котором пришёл первый снимок, уже отрисован.
func _started_at(position: Vector3, tick: int) -> SnapshotInterpolator:
	var interpolator := SnapshotInterpolator.new()
	interpolator.reset(position, tick)
	interpolator.advance(TICK_SEC, TICKS_PER_SECOND)
	return interpolator


## Игрок идёт с постоянной скоростью, сервер шлёт снимок каждый тик (кроме тех, что отбросил
## фильтр), клиент рисует кадры с частотой fps. Возвращает наибольшее отклонение скорости
## показанного движения от настоящей.
func _worst_speed_error(fps: float, is_delivered: Callable) -> float:
	var interpolator := _started_at(Vector3.ZERO, 0)
	var frame_sec: float = 1.0 / fps
	var worst: float = 0.0
	var sent_tick: int = 0
	var previous: Vector3 = Vector3.ZERO
	for frame: int in range(1, int(fps * 4.0)):
		var now: float = frame * frame_sec
		# Снимки приходят в начале кадра, как при опросе сети перед _process.
		while (sent_tick + 1) * TICK_SEC <= now:
			sent_tick += 1
			var delivered: bool = is_delivered.call(sent_tick)
			if delivered:
				interpolator.push(STEP * sent_tick, sent_tick)
		var shown: Vector3 = interpolator.advance(frame_sec, TICKS_PER_SECOND)
		# Первые полсекунды — разгон с места: первый снимок с движением ещё не пришёл.
		if now > 0.5:
			worst = maxf(worst, absf((shown.x - previous.x) / frame_sec - SPEED))
		previous = shown
	return worst
