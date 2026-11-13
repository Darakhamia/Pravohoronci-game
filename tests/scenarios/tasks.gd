extends TaskScenarioBot
## Сценарий tasks: два члена экипажа без предателей выполняют все четыре вида заданий.
## Работают по очереди — сначала Bot1, потом Bot2, — чтобы оба в каждый момент точно
## знали, каким должен быть общий прогресс: тот, кто работает, сверяет его после каждого
## своего шага, а второй в это время смотрит со стороны и проверяет, что чужие личные
## данные (список, код, исход попыток) до него не доходят.
## Заодно — отказы сервера: неверный код, код издалека и без открытия, поток ответов,
## калибровка мимо зоны и с переливом, порт без канистры, вторая канистра, повтор
## сделанного задания.

const TASKS_PER_PLAYER: int = 4
const PLAYERS: int = 2
const TOTAL_TASKS: int = TASKS_PER_PLAYER * PLAYERS
## Сколько ждать, пока второй бот сделает все свои задания.
const OTHER_BOT_DEADLINE_SEC: float = 110.0
const COMPLETE_DEADLINE_SEC: float = 8.0
## Доля шкалы калибратора, на которой бот отпускает клавишу заведомо рано.
const EARLY_RELEASE_FRACTION: float = 0.12
const CALIBRATION_ATTEMPTS: int = 6
## Чуть больше секунды: окно, в котором сервер считает ответы игрока.
const ANSWER_WINDOW_SEC: float = 1.2
const ANSWER_BURST: int = 12
## На сколько метров бот отходит от терминала, чтобы ответить «издалека».
const FAR_DISTANCE: float = 6.0

var _wiring: TaskWiring = null
var _keypad: TaskKeypad = null
var _calibrator: TaskCalibrator = null
var _dock: TaskFuelDock = null
var _rack: CanisterRack = null
var _canister_index: int = PlayerWeapons.ITEMS.index_of(TaskFuelDock.CANISTER)

## Что сервер прислал нам лично: [station_id, data] и [station_id, success].
var _opened: Array[Array] = []
var _feedback: Array[Array] = []
## Значения done_count, которые мы видели, по порядку.
var _progress_log: PackedInt32Array = []
var _saw_other_with_canister: bool = false


func _run() -> void:
	if not _find_stations():
		return
	Game.tasks.task_opened.connect(func(station_id: int, data: Dictionary) -> void:
		_opened.append([station_id, data]))
	Game.tasks.task_feedback.connect(func(station_id: int, success: bool) -> void:
		_feedback.append([station_id, success]))
	var other: Player = avatar_named("Bot2" if bot_number == 1 else "Bot1")
	other.held_item_changed.connect(func(item_id: int) -> void:
		if item_id == _canister_index:
			_saw_other_with_canister = true)
	if not await _check_start():
		return
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	if bot_number == 1:
		if not await _do_all_tasks(0) or not await _watch_other(TOTAL_TASKS):
			return
	else:
		if not await _watch_other(TASKS_PER_PLAYER) or not await _do_all_tasks(TASKS_PER_PLAYER):
			return
	if not await expect_result(Game.Winner.CREW, Game.EndReason.TASKS_DONE, 5.0):
		return
	if not _check_progress_log():
		return
	if not await expect_lobby(10.0):
		return
	check(Game.tasks.total_count == 0 and Game.tasks.done_count == 0 and Game.tasks.get_local_tasks().is_empty(),
			"после матча задания не сброшены: %d/%d, список %s" % [
			Game.tasks.done_count, Game.tasks.total_count, Game.tasks.get_local_tasks()])


func _find_stations() -> bool:
	for candidate: Interactable in map().get_interactables():
		if candidate is TaskWiring:
			_wiring = candidate as TaskWiring
		elif candidate is TaskKeypad:
			_keypad = candidate as TaskKeypad
		elif candidate is TaskCalibrator:
			_calibrator = candidate as TaskCalibrator
		elif candidate is TaskFuelDock:
			_dock = candidate as TaskFuelDock
		elif candidate is CanisterRack:
			_rack = candidate as CanisterRack
	return check(_wiring != null and _keypad != null and _calibrator != null and _dock != null and _rack != null,
			"на карте нет всех станций")


## Оба: у каждого все четыре станции, общий счёт — восемь, метки горят.
func _check_start() -> bool:
	if not await expect(func() -> bool: return Game.tasks.get_local_tasks().size() == TASKS_PER_PLAYER,
			4.0, "сервер не прислал список заданий"):
		return false
	if not check(Game.tasks.total_count == TOTAL_TASKS and Game.tasks.done_count == 0,
			"общий прогресс на старте %d/%d" % [Game.tasks.done_count, Game.tasks.total_count]):
		return false
	# Стартовый счёт сервер шлёт раньше списка: с этого места видим каждое изменение.
	Game.tasks.progress_changed.connect(func() -> void:
		_progress_log.append(Game.tasks.done_count))
	for station: TaskStation in _stations():
		if not check(Game.tasks.get_local_tasks().has(station.interact_id), "станции %s нет в списке" % station.name):
			return false
		if not check(Game.tasks.is_pending(Net.local_id(), station.interact_id)
				and not Game.tasks.is_local_done(station.interact_id), "задание %s не ждёт игрока" % station.name):
			return false
		if not check(station.is_marked(), "над своей станцией %s не горит метка" % station.name):
			return false
		if not check(not station.title.is_empty() and not station.location.is_empty(),
				"у станции %s нет названия или места" % station.name):
			return false
	if not check(_rack.is_marked(), "над стеллажом не горит метка, хотя нужна доставка"):
		return false
	# Клиент знает задания только про себя.
	var other_id: int = peer_named("Bot2" if bot_number == 1 else "Bot1")
	return check(not Game.tasks.is_pending(other_id, _wiring.interact_id), "клиент «знает» чужое задание")


func _stations() -> Array[TaskStation]:
	return [_wiring, _keypad, _calibrator, _dock]


## Второй бот работает, мы смотрим: общий прогресс растёт, а личное до нас не доходит.
func _watch_other(target_done: int) -> bool:
	step("ждём, пока второй бот доведёт прогресс до %d" % target_done)
	var opened_before: int = _opened.size()
	var feedback_before: int = _feedback.size()
	var local_before: PackedInt32Array = Game.tasks.get_local_tasks()
	var pending_before: int = _count_pending()
	if not await expect(func() -> bool: return Game.tasks.done_count >= target_done,
			OTHER_BOT_DEADLINE_SEC, "второй бот не выполнил свои задания: прогресс %d" % Game.tasks.done_count):
		return false
	if not check(Game.tasks.done_count == target_done and Game.tasks.total_count == TOTAL_TASKS,
			"прогресс %d/%d, а ждали %d/%d" % [Game.tasks.done_count, Game.tasks.total_count, target_done, TOTAL_TASKS]):
		return false
	if not check(_opened.size() == opened_before and _feedback.size() == feedback_before,
			"до наблюдателя дошли чужой код или исход чужой попытки"):
		return false
	if not check(Game.tasks.get_local_tasks() == local_before and _count_pending() == pending_before,
			"чужие задания изменили наш список"):
		return false
	return check(_saw_other_with_canister, "наблюдатель не видел канистру в руках второго бота")


func _count_pending() -> int:
	var count: int = 0
	for station_id: int in Game.tasks.get_local_tasks():
		if Game.tasks.is_pending(Net.local_id(), station_id):
			count += 1
	return count


func _do_all_tasks(done_before: int) -> bool:
	if not await _do_wiring(done_before + 1):
		return false
	if not await _do_keypad(done_before + 2):
		return false
	if not await _do_calibrator(done_before + 3):
		return false
	return await _do_fuel(done_before + 4)


## Задание сделано: у нас оно отмечено, метка погасла, общий прогресс — ровно такой.
func _expect_completed(station: TaskStation, expected_done: int) -> bool:
	if not await expect(func() -> bool: return Game.tasks.is_local_done(station.interact_id),
			COMPLETE_DEADLINE_SEC, "задание %s не засчитано" % station.name):
		return false
	if not await expect(func() -> bool: return Game.tasks.done_count == expected_done, 2.0,
			"после %s прогресс %d, а ждали %d" % [station.name, Game.tasks.done_count, expected_done]):
		return false
	if not await expect(func() -> bool: return _last_feedback() == [station.interact_id, true], 2.0,
			"после %s нет сообщения об успехе" % station.name):
		return false
	if not check(not Game.tasks.is_pending(Net.local_id(), station.interact_id) and not station.is_marked(),
			"сделанное задание %s всё ещё ждёт или отмечено меткой" % station.name):
		return false
	return check(Game.tasks.total_count == TOTAL_TASKS and Game.tasks.get_local_tasks().size() == TASKS_PER_PLAYER,
			"после %s изменилось число заданий" % station.name)


## Ничего не произошло: прогресс и число сообщений сервера прежние.
func _expect_unchanged(expected_done: int, feedback_count: int, what: String) -> bool:
	return check(Game.tasks.done_count == expected_done and _feedback.size() == feedback_count,
			"%s: прогресс %d (ждали %d), сообщений %d (ждали %d)" % [
			what, Game.tasks.done_count, expected_done, _feedback.size(), feedback_count])


func _last_feedback() -> Array:
	return _feedback.back() if not _feedback.is_empty() else []


# --- Проводка: удержать E ---


func _do_wiring(expected_done: int) -> bool:
	step("проводка")
	if not await approach_and_press(_wiring):
		return false
	var is_done: bool = await _expect_completed(_wiring, expected_done)
	release(&"interact")
	if not is_done:
		return false
	# Сделанное задание второй раз не засчитывается, даже если клиент настаивает.
	if not await expect_no_focus(_wiring):
		return false
	var feedback_count: int = _feedback.size()
	if not await force_hold(_wiring, _wiring.hold_seconds + NOTHING_SEC):
		return false
	return _expect_unchanged(expected_done, feedback_count, "повтор сделанной проводки")


# --- Терминал: ввести код ---


func _do_keypad(expected_done: int) -> bool:
	step("терминал")
	var done_before: int = expected_done - 1
	var keypad_id: int = _keypad.interact_id
	if not await approach(_keypad) or not await aim(_keypad):
		return false
	# Ответ до того, как терминал открыт, сервер не рассматривает.
	var feedback_count: int = _feedback.size()
	Game.tasks.request_answer(keypad_id, "0000")
	if not await wait_seconds(NOTHING_SEC):
		return false
	if not _expect_unchanged(done_before, feedback_count, "ответ без открытия терминала"):
		return false
	if not check(_opened.is_empty(), "код пришёл до открытия терминала"):
		return false
	await tap(&"interact")
	if not await expect(func() -> bool: return _opened.size() == 1, REPLY_DEADLINE_SEC, "сервер не прислал код"):
		return false
	var opened_id: int = _opened[0][0]
	var data: Dictionary = _opened[0][1]
	var code: String = data.get(TaskKeypad.CODE_KEY, "")
	if not check(opened_id == keypad_id and code.length() == TaskKeypad.CODE_LENGTH and code.is_valid_int(),
			"открыта станция %d с данными %s" % [opened_id, data]):
		return false
	var wrong: String = "0000" if code != "0000" else "1111"
	# Неверный код: отказ, задание остаётся.
	if not await wait_seconds(ANSWER_WINDOW_SEC):
		return false
	feedback_count = _feedback.size()
	Game.tasks.request_answer(keypad_id, wrong)
	if not await expect(func() -> bool: return _feedback.size() == feedback_count + 1, REPLY_DEADLINE_SEC,
			"сервер не ответил на неверный код"):
		return false
	if not check(_last_feedback() == [keypad_id, false] and Game.tasks.is_pending(Net.local_id(), keypad_id)
			and Game.tasks.done_count == done_before, "неверный код принят"):
		return false
	# Ответ на станцию другого вида сервер не рассматривает.
	Game.tasks.request_answer(_calibrator.interact_id, code)
	# Поток ответов: сервер разбирает не больше нескольких в секунду.
	if not await wait_seconds(ANSWER_WINDOW_SEC):
		return false
	feedback_count = _feedback.size()
	for index: int in ANSWER_BURST:
		Game.tasks.request_answer(keypad_id, wrong)
	if not await wait_seconds(ANSWER_WINDOW_SEC):
		return false
	var replies: int = _feedback.size() - feedback_count
	if not check(replies >= 1 and replies <= TaskBoard.MAX_ANSWERS_PER_SECOND,
			"на %d ответов подряд сервер ответил %d раз" % [ANSWER_BURST, replies]):
		return false
	# Верный код издалека не считается.
	if not await _answer_from_far(code, done_before):
		return false
	# Верный код у терминала.
	if not await approach(_keypad) or not await aim(_keypad):
		return false
	Game.tasks.request_answer(keypad_id, code)
	if not await _expect_completed(_keypad, expected_done):
		return false
	# После успеха тот же код больше ничего не даёт.
	feedback_count = _feedback.size()
	if not await wait_seconds(ANSWER_WINDOW_SEC):
		return false
	Game.tasks.request_answer(keypad_id, code)
	if not await wait_seconds(NOTHING_SEC):
		return false
	return _expect_unchanged(expected_done, feedback_count, "повтор кода после успеха")


func _answer_from_far(code: String, done_before: int) -> bool:
	var far_point: Vector3 = _keypad.to_global(Vector3(0.0, 0.0, -FAR_DISTANCE))
	if not check(await walk_to(far_point, STOP_DISTANCE, WALK_DEADLINE_SEC), "бот не отошёл от терминала"):
		return false
	if not await wait_seconds(SETTLE_SEC):
		return false
	var feedback_count: int = _feedback.size()
	Game.tasks.request_answer(_keypad.interact_id, code)
	if not await expect(func() -> bool: return _feedback.size() == feedback_count + 1, REPLY_DEADLINE_SEC,
			"сервер не ответил на код издалека"):
		return false
	return check(_last_feedback() == [_keypad.interact_id, false]
			and Game.tasks.is_pending(Net.local_id(), _keypad.interact_id)
			and Game.tasks.done_count == done_before, "код издалека принят")


# --- Калибратор: отпустить в зелёной зоне ---


func _do_calibrator(expected_done: int) -> bool:
	step("калибратор")
	var done_before: int = expected_done - 1
	var calibrator_id: int = _calibrator.interact_id
	if not await approach(_calibrator) or not await aim(_calibrator):
		return false
	# Отпустил слишком рано — мимо.
	var feedback_count: int = _feedback.size()
	if not await _hold_until_fraction(EARLY_RELEASE_FRACTION):
		return false
	if not await expect(func() -> bool: return _feedback.size() == feedback_count + 1, REPLY_DEADLINE_SEC,
			"сервер не ответил на раннее отпускание"):
		return false
	if not check(_last_feedback() == [calibrator_id, false] and Game.tasks.is_pending(Net.local_id(), calibrator_id)
			and Game.tasks.done_count == done_before, "раннее отпускание засчитано"):
		return false
	# Додержал до конца — перелив. Проверяет один бот: это лишние секунды.
	if bot_number == 2:
		feedback_count = _feedback.size()
		if not await aim(_calibrator):
			return false
		press(&"interact")
		var is_answered: bool = await expect(func() -> bool: return _feedback.size() == feedback_count + 1,
				_calibrator.hold_seconds + REPLY_DEADLINE_SEC, "сервер не ответил на перелив")
		release(&"interact")
		# Игра опрашивает клавишу раз в физический тик: отпускание должно успеть дойти.
		if not is_answered or not await wait_seconds(SETTLE_SEC):
			return false
		if not check(_last_feedback() == [calibrator_id, false] and Game.tasks.is_pending(Net.local_id(), calibrator_id)
				and Game.tasks.done_count == done_before, "перелив засчитан"):
			return false
	# В зелёной зоне. На загруженной машине бот может промахнуться — пробует ещё, как игрок.
	var target_fraction: float = (_calibrator.zone_start + _calibrator.zone_end) * 0.5
	for attempt: int in CALIBRATION_ATTEMPTS:
		feedback_count = _feedback.size()
		if not await aim(_calibrator) or not await _hold_until_fraction(target_fraction):
			return false
		if not await expect(func() -> bool: return _feedback.size() == feedback_count + 1, REPLY_DEADLINE_SEC,
				"сервер не ответил на отпускание в зоне"):
			return false
		if _last_feedback() == [calibrator_id, true]:
			return await _expect_completed(_calibrator, expected_done)
		step("калибровка мимо зоны, попытка %d" % (attempt + 1))
	return check(false, "бот не попал в зелёную зону за %d попыток" % CALIBRATION_ATTEMPTS)


## Зажать E и отпустить, когда полоска удержания дойдёт до fraction.
func _hold_until_fraction(fraction: float) -> bool:
	press(&"interact")
	var is_reached: bool = await expect(func() -> bool: return me().interactor.hold_fraction >= fraction,
			_calibrator.hold_seconds + REPLY_DEADLINE_SEC, "полоска удержания не дошла до %.2f" % fraction)
	release(&"interact")
	# Игра опрашивает клавишу раз в физический тик: отпускание должно успеть дойти.
	return is_reached and await wait_seconds(TAP_SEC)


# --- Доставка: канистра со стеллажа в порт ---


func _do_fuel(expected_done: int) -> bool:
	step("доставка")
	var done_before: int = expected_done - 1
	# Без канистры порт не работает — ни у клиента, ни на сервере.
	if not await approach(_dock) or not await expect_no_focus(_dock):
		return false
	var feedback_count: int = _feedback.size()
	if not await force_hold(_dock, _dock.hold_seconds + NOTHING_SEC):
		return false
	if not _expect_unchanged(done_before, feedback_count, "порт без канистры"):
		return false
	# Берём канистру; вторую в те же руки стеллаж не даёт.
	if not await _take_canister():
		return false
	if not await expect_no_focus(_rack):
		return false
	if not await force_hold(_rack, NOTHING_SEC):
		return false
	if not check(me().held_item == _canister_index, "после второй попытки взять канистру в руках %d" % me().held_item):
		return false
	# Q — бросить: канистра пропадает, за новой можно вернуться.
	await tap(&"switch_weapon")
	if not await expect(func() -> bool: return me().held_item == PlayerWeapons.EMPTY_HANDS, REPLY_DEADLINE_SEC,
			"канистра не брошена по Q"):
		return false
	if not await _take_canister():
		return false
	# Доставка.
	if not await approach_and_press(_dock):
		return false
	var is_done: bool = await _expect_completed(_dock, expected_done)
	release(&"interact")
	if not is_done:
		return false
	if not await expect(func() -> bool: return me().held_item == PlayerWeapons.EMPTY_HANDS, REPLY_DEADLINE_SEC,
			"после доставки канистра осталась в руках"):
		return false
	# Доставка сделана — стеллаж больше не выдаёт.
	if not check(not _rack.is_marked(), "над стеллажом горит метка, хотя доставка сделана"):
		return false
	# У второго бота это последнее задание матча: игра уже закончилась, ходить нельзя.
	if bot_number != 1:
		return true
	if not await approach(_rack) or not await expect_no_focus(_rack):
		return false
	if not await force_hold(_rack, NOTHING_SEC):
		return false
	return check(me().held_item == PlayerWeapons.EMPTY_HANDS, "стеллаж выдал канистру без задания")


func _take_canister() -> bool:
	if not await approach(_rack) or not await aim(_rack):
		return false
	await tap(&"interact")
	if not await expect(func() -> bool: return me().weapons.is_carrying(TaskFuelDock.CANISTER), REPLY_DEADLINE_SEC,
			"стеллаж не выдал канистру"):
		return false
	return check(me().held_item == _canister_index, "в руках предмет %d, а не канистра" % me().held_item)


## Оба: прогресс рос по единице от нуля до восьми — одна и та же картина на обоих клиентах.
func _check_progress_log() -> bool:
	var expected: PackedInt32Array = []
	for value: int in TOTAL_TASKS:
		expected.append(value + 1)
	return check(_progress_log == expected, "прогресс менялся так: %s, а ждали %s" % [_progress_log, expected])
