extends TaskScenarioBot
## Сценарий tasks_public: работа того, кто выбыл у всех на глазах, переходит к живым сразу,
## не дожидаясь собрания (в отличие от тихо убитого — см. tasks_roles). Предателей нет,
## три члена экипажа, шесть станций, по два задания. Этапы объявляет серверный помощник
## (tasks_public_director.gd) через общее состояние предмета StageSwitch.
## 1) Bot3 выходит из игры живым и возвращается зрителем. Список лобби изменился у всех,
##    и его два задания сразу оказываются у Bot1 и Bot2 (или пропадают из общего счёта,
##    если станция уже есть у обоих) — собрания при этом не было.
## 2) Помощник созывает собрание. Bot1 и Bot2 голосуют за Bot2: он изгнан, и его несделанная
##    работа сразу у Bot1 — к моменту, когда игра продолжилась, второго собрания не нужно.
## 3) Bot1 доделывает всё, что у него накопилось: победа экипажа по заданиям.

const LAST_NAME: String = "Bot1"
const EJECTED_NAME: String = "Bot2"
const LEAVER_NAME: String = "Bot3"
const TASKS_PER_PLAYER: int = 2
const CREW_COUNT: int = 3
const TOTAL_TASKS: int = TASKS_PER_PLAYER * CREW_COUNT
const STAGE_DEADLINE_SEC: float = 45.0
const COMPLETE_DEADLINE_SEC: float = 8.0
## Взгляд круто вверх — знак серверному помощнику: «первый этап проверен».
const SIGNAL_PITCH: float = 1.3

var _stations: Dictionary[int, TaskStation] = {}
var _stage_switch: Interactable = null
## Наш список на старте.
var _initial_tasks: PackedInt32Array = []
## Сколько собраний началось на наших глазах.
var _meetings_started: int = 0


func _run() -> void:
	if not _scan_map():
		return
	Game.meeting.started.connect(func() -> void: _meetings_started += 1)
	if not await expect(func() -> bool: return Game.tasks.get_local_tasks().size() == TASKS_PER_PLAYER,
			4.0, "сервер не прислал список заданий"):
		return
	_initial_tasks = Game.tasks.get_local_tasks()
	if not check(Game.tasks.total_count == TOTAL_TASKS and Game.tasks.done_count == 0,
			"общий прогресс на старте %d/%d" % [Game.tasks.done_count, Game.tasks.total_count]):
		return
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	if bot_name == LEAVER_NAME:
		await _run_leaver()
		return
	var is_ejected: bool = bot_name == EJECTED_NAME
	var is_last: bool = bot_name == LAST_NAME

	# 1) Работа вышедшего перешла сразу.
	if not await _expect_stage(DirectorStages.LEFT):
		return
	var left_code: int = _stage_switch.state - DirectorStages.LEFT
	@warning_ignore("integer_division")
	var growth_last: int = left_code / DirectorStages.STEP
	var growth_ejected: int = left_code % DirectorStages.STEP
	var total_after_leave: int = TOTAL_TASKS - (TASKS_PER_PLAYER - growth_last - growth_ejected)
	if not await expect(func() -> bool: return Game.tasks.total_count == total_after_leave, REPLY_DEADLINE_SEC,
			"после выхода игрока всего заданий %d, а ждали %d" % [Game.tasks.total_count, total_after_leave]):
		return
	var own_size: int = TASKS_PER_PLAYER + (growth_last if is_last else growth_ejected)
	if not await _expect_list(own_size, "после выхода игрока"):
		return
	# Помощник созовёт собрание только после нашего знака: до сих пор его не было.
	if not check(_meetings_started == 0 and Game.is_playing() and not Game.meeting.is_active(),
			"работа вышедшего перешла не сразу: уже шло собрание"):
		return
	me().input.pitch = SIGNAL_PITCH

	# 2) Собрание: изгоняем Bot2, его работа сразу у Bot1.
	if not await expect(func() -> bool: return Game.meeting.stage == Meeting.Stage.VOTING, STAGE_DEADLINE_SEC,
			"голосование не началось"):
		return
	Game.meeting.request_vote(peer_named(EJECTED_NAME))
	if not await _expect_stage(DirectorStages.EJECTED):
		return
	var ejected_code: int = _stage_switch.state - DirectorStages.EJECTED
	@warning_ignore("integer_division")
	var dropped: int = ejected_code / DirectorStages.STEP
	var growth_after_eject: int = ejected_code % DirectorStages.STEP
	var total_after_eject: int = total_after_leave - dropped
	if not await expect(func() -> bool: return Game.tasks.total_count == total_after_eject, REPLY_DEADLINE_SEC,
			"после изгнания всего заданий %d, а ждали %d" % [Game.tasks.total_count, total_after_eject]):
		return
	if not check(Game.meeting.ejected_id == peer_named(EJECTED_NAME), "изгнан не тот игрок"):
		return
	if is_last and not await _expect_list(own_size + growth_after_eject, "после изгнания"):
		return
	if is_ejected and not await _check_ejected_self(own_size):
		return
	if not await expect(Game.is_playing, 10.0, "после собрания игра не продолжилась"):
		return
	if not check(_meetings_started == 1, "собраний было %d: работа изгнанного ждала ещё одного" % _meetings_started):
		return

	# 3) Последний живой доделывает всё.
	if is_last:
		for station_id: int in Game.tasks.get_local_tasks():
			if not await _complete(station_id):
				return
	if not await expect_result(Game.Winner.CREW, Game.EndReason.TASKS_DONE, STAGE_DEADLINE_SEC):
		return
	if not check(Game.tasks.done_count == total_after_eject and Game.tasks.total_count == total_after_eject,
			"в конце матча прогресс %d/%d" % [Game.tasks.done_count, Game.tasks.total_count]):
		return
	await expect_lobby(10.0)


## Bot3: выйти из игры живым и вернуться зрителем. Вернуться он может в любой момент —
## и до собрания, и посреди него, — поэтому сам сверяет только то, что от времени не
## зависит: списка и аватара у него нет, а в конце общий счёт закрыт. Сколько именно
## заданий осталось в счёте, проверяют живые боты и помощник.
func _run_leaver() -> void:
	step("выходим из игры живым и возвращаемся зрителем")
	if not await rejoin() or not _scan_map():
		return
	if not check(Game.tasks.get_local_tasks().is_empty() and me() == null, "у зрителя есть список заданий или аватар"):
		return
	if not await expect_result(Game.Winner.CREW, Game.EndReason.TASKS_DONE, STAGE_DEADLINE_SEC * 2.0):
		return
	if not check(Game.tasks.total_count > 0 and Game.tasks.total_count <= TOTAL_TASKS
			and Game.tasks.done_count == Game.tasks.total_count,
			"в конце матча у зрителя прогресс %d/%d" % [Game.tasks.done_count, Game.tasks.total_count]):
		return
	await expect_lobby(10.0)


## Найти на карте станции и семафор этапов.
func _scan_map() -> bool:
	_stations.clear()
	_stage_switch = null
	for candidate: Interactable in map().get_interactables():
		if candidate is TaskStation:
			_stations[candidate.interact_id] = candidate as TaskStation
		elif candidate is TestSwitch:
			_stage_switch = candidate
	return check(_stations.size() >= TASKS_PER_PLAYER and _stage_switch != null, "на карте нет станций или семафора")


## Дождаться этапа от серверного помощника.
func _expect_stage(stage: int) -> bool:
	return await expect(func() -> bool: return _stage_switch.state >= stage, STAGE_DEADLINE_SEC,
			"серверный помощник не объявил этап %d (сейчас %d)" % [stage, _stage_switch.state])


## Наш список вырос до size: прежние задания на своих местах, новые — в конце, ждут нас
## и отмечены метками.
func _expect_list(size: int, moment: String) -> bool:
	if not await expect(func() -> bool: return Game.tasks.get_local_tasks().size() == size, REPLY_DEADLINE_SEC,
			"%s в списке %d заданий, а ждали %d" % [moment, Game.tasks.get_local_tasks().size(), size]):
		return false
	var tasks: PackedInt32Array = Game.tasks.get_local_tasks()
	if not check(tasks.slice(0, TASKS_PER_PLAYER) == _initial_tasks, "%s список: %s (был %s)" % [moment, tasks, _initial_tasks]):
		return false
	for station_id: int in tasks:
		if not check(Game.tasks.is_pending(Net.local_id(), station_id) and _stations[station_id].is_marked(),
				"%s задание %s не ждёт игрока или не отмечено меткой" % [moment, _stations[station_id].name]):
			return false
	return true


## Изгнанный: аватар убран, список виден как был, но в работе у него ничего нет.
func _check_ejected_self(size: int) -> bool:
	if not await expect(func() -> bool: return me() != null and me().life == Player.Life.GONE, REPLY_DEADLINE_SEC,
			"аватар изгнанного не убран"):
		return false
	if not await expect(func() -> bool: return not Game.tasks.is_pending(Net.local_id(), _initial_tasks[0]),
			REPLY_DEADLINE_SEC, "у изгнанного задание всё ещё в работе"):
		return false
	if not check(Game.tasks.get_local_tasks().size() == size, "список изгнанного изменился: %s" % Game.tasks.get_local_tasks()):
		return false
	for station_id: int in Game.tasks.get_local_tasks():
		if not check(not Game.tasks.is_pending(Net.local_id(), station_id) and not _stations[station_id].is_marked(),
				"у изгнанного отмечена станция %s" % _stations[station_id].name):
			return false
	return true


## Подойти к своей станции и удержать E до конца.
func _complete(station_id: int) -> bool:
	var station: TaskStation = _stations[station_id]
	if not await approach_and_press(station):
		return false
	var is_done: bool = await expect(func() -> bool: return Game.tasks.is_local_done(station_id),
			COMPLETE_DEADLINE_SEC, "задание %s не засчитано" % station.name)
	release(&"interact")
	return is_done


## Этапы серверного помощника (см. tasks_public_director.gd).
class DirectorStages:
	const LEFT: int = 100
	const EJECTED: int = 200
	const STEP: int = 10
