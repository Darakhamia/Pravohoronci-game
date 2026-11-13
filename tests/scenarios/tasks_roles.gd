extends TaskScenarioBot
## Сценарий tasks_roles: Bot1 — предатель, Bot2..Bot4 — экипаж; шесть станций, по два
## задания на игрока. Этапы объявляет серверный помощник (tasks_roles_director.gd)
## через общее состояние предмета StageSwitch.
## 1) Предатель пробует чужую станцию (ничего) и «выполняет» своё фальшивое задание:
##    у него оно отмечено, общий прогресс у всех — ноль.
## 2) Экипаж делает по одному заданию (Bot2 и Bot3 сначала пробуют чужую станцию).
## 3) Помощник убивает члена экипажа: его несделанное задание появляется в списке
##    живого коллеги, общее число заданий не меняется; мёртвый список видит, но
##    выполнять не может.
## 4) Убитый выходит и заходит снова — уже зрителем: общий прогресс он получает, списка нет.
## 5) Живой экипаж доделывает всё, включая работу коллеги: победа экипажа по заданиям.
## Тот же бот играет сценарий tasks_drop (карта с двумя станциями): там у всех одинаковые
## списки, работу погибшего взять некому, и она пропадает из общего счёта.

const TRAITOR_NAME: String = "Bot1"
const TASKS_PER_PLAYER: int = 2
const CREW_COUNT: int = 3
const TOTAL_TASKS: int = TASKS_PER_PLAYER * CREW_COUNT
const STAGE_DEADLINE_SEC: float = 45.0
const COMPLETE_DEADLINE_SEC: float = 8.0
## Бот, который на первом этапе ничего не делает и следит за общим прогрессом.
const IDLE_WATCHER: int = 4

var _stations: Dictionary[int, TaskStation] = {}
var _stage_switch: Interactable = null
var _feedback: Array[Array] = []
## Наш список на старте.
var _initial_tasks: PackedInt32Array = []


func _run() -> void:
	if not _scan_map():
		return
	Game.tasks.task_feedback.connect(func(station_id: int, success: bool) -> void:
		_feedback.append([station_id, success]))
	if not await _check_start():
		return
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	var is_traitor: bool = bot_name == TRAITOR_NAME
	if is_traitor:
		if not await _do_fake_task():
			return
	elif bot_number != IDLE_WATCHER:
		if not await _try_foreign_station(false):
			return
	if not await _expect_stage(DirectorStages.FAKE_DONE):
		return
	# Тот, кто всё это время стоял без дела, увидел этап сразу: прогресс не сдвинулся.
	if (is_traitor or bot_number == IDLE_WATCHER) and not check(
			Game.tasks.done_count == 0 and Game.tasks.total_count == TOTAL_TASKS,
			"после фальшивого задания предателя прогресс %d/%d" % [Game.tasks.done_count, Game.tasks.total_count]):
		return
	if not is_traitor and not await _complete(_initial_tasks[0]):
		return
	if not await expect(func() -> bool: return Game.tasks.done_count >= CREW_COUNT, STAGE_DEADLINE_SEC,
			"экипаж не сделал по одному заданию: прогресс %d" % Game.tasks.done_count):
		return
	if not await _expect_stage(DirectorStages.HANDED):
		return
	var stage: int = _stage_switch.state
	var expected_total: int = TOTAL_TASKS - 1 if stage == DirectorStages.DROPPED else TOTAL_TASKS
	if not check(Game.tasks.total_count == expected_total and Game.tasks.done_count >= CREW_COUNT,
			"после гибели коллеги прогресс %d/%d, а всего ждали %d" % [
			Game.tasks.done_count, Game.tasks.total_count, expected_total]):
		return
	# Смерть приходит репликацией аватара, а этап — отдельным сообщением: порядок не задан.
	if not await expect(func() -> bool: return not _find_victim_name().is_empty(), REPLY_DEADLINE_SEC,
			"после убийства все аватары экипажа живы"):
		return
	if me().life != Player.Life.ALIVE:
		if not await _check_dead() or not await _rejoin_as_spectator(expected_total):
			return
	elif is_traitor:
		if not check(Game.tasks.get_local_tasks() == _initial_tasks, "работа экипажа досталась предателю"):
			return
	else:
		# Убитый выходит и заходит снова зрителем; доделываем задания, когда он вернулся,
		# чтобы он точно застал матч.
		if not await _wait_victim_rejoined():
			return
		if not await _finish_crew_tasks(stage == DirectorStages.HANDED + bot_number):
			return
	if not await expect_result(Game.Winner.CREW, Game.EndReason.TASKS_DONE, STAGE_DEADLINE_SEC):
		return
	if not check(Game.tasks.done_count == expected_total and Game.tasks.total_count == expected_total,
			"в конце матча прогресс %d/%d" % [Game.tasks.done_count, Game.tasks.total_count]):
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


## Все: по два своих задания, общий счёт — только задания экипажа, метки — только над своими.
func _check_start() -> bool:
	if not await expect(func() -> bool: return Game.tasks.get_local_tasks().size() == TASKS_PER_PLAYER,
			4.0, "сервер не прислал список заданий"):
		return false
	_initial_tasks = Game.tasks.get_local_tasks()
	if not check(Game.tasks.total_count == TOTAL_TASKS and Game.tasks.done_count == 0,
			"общий прогресс на старте %d/%d" % [Game.tasks.done_count, Game.tasks.total_count]):
		return false
	if not check(_initial_tasks[0] != _initial_tasks[1], "в списке одна и та же станция дважды"):
		return false
	for station_id: int in _stations:
		var is_mine: bool = _initial_tasks.has(station_id)
		if not check(_stations[station_id].is_marked() == is_mine
				and Game.tasks.is_pending(Net.local_id(), station_id) == is_mine,
				"станция %s: метка или ожидание не совпадают со списком" % _stations[station_id].name):
			return false
	return true


## Предатель: чужая станция не даётся, своё фальшивое задание «выполняется» только для него.
func _do_fake_task() -> bool:
	if not await _try_foreign_station(true):
		return false
	step("фальшивое задание предателя")
	if not await _complete(_initial_tasks[0]):
		return false
	return check(Game.tasks.done_count == 0 and Game.tasks.total_count == TOTAL_TASKS,
			"фальшивое задание сдвинуло общий прогресс: %d/%d" % [Game.tasks.done_count, Game.tasks.total_count])


## Станция не из нашего списка: клиент её не предлагает, а сервер не засчитывает, даже
## если клиент настаивает. check_progress — когда больше никто заданий не делает.
func _try_foreign_station(check_progress: bool) -> bool:
	var foreign: TaskStation = null
	for station_id: int in _stations:
		if not _initial_tasks.has(station_id):
			foreign = _stations[station_id]
			break
	# На карте сценария tasks_drop станций всего две, и обе — свои.
	if foreign == null:
		return true
	step("чужая станция %s" % foreign.name)
	if not await approach(foreign) or not await expect_no_focus(foreign):
		return false
	await tap(&"interact")
	var feedback_before: int = _feedback.size()
	if not await force_hold(foreign, foreign.hold_seconds + NOTHING_SEC):
		return false
	if not check(Game.tasks.get_local_tasks() == _initial_tasks and not Game.tasks.is_local_done(foreign.interact_id)
			and _feedback.size() == feedback_before, "чужая станция что-то изменила в списке игрока"):
		return false
	return not check_progress or check(Game.tasks.done_count == 0 and Game.tasks.total_count == TOTAL_TASKS,
			"чужая станция сдвинула общий прогресс: %d/%d" % [Game.tasks.done_count, Game.tasks.total_count])


## Подойти к своей станции и удержать E до конца.
func _complete(station_id: int) -> bool:
	var station: TaskStation = _stations[station_id]
	if not await approach_and_press(station):
		return false
	var is_done: bool = await expect(func() -> bool: return Game.tasks.is_local_done(station_id),
			COMPLETE_DEADLINE_SEC, "задание %s не засчитано" % station.name)
	release(&"interact")
	if not is_done:
		return false
	if not await expect(func() -> bool: return not _feedback.is_empty() and _feedback.back() == [station_id, true],
			2.0, "после %s нет сообщения об успехе" % station.name):
		return false
	return check(not station.is_marked() and not Game.tasks.is_pending(Net.local_id(), station_id),
			"сделанное задание %s всё ещё ждёт или отмечено меткой" % station.name)


## Дождаться этапа от серверного помощника.
func _expect_stage(stage: int) -> bool:
	return await expect(func() -> bool: return _stage_switch.state >= stage, STAGE_DEADLINE_SEC,
			"серверный помощник не объявил этап %d (сейчас %d)" % [stage, _stage_switch.state])


## Убитый: список виден как был, но заданий «в работе» у него нет, и сервер их не принимает.
func _check_dead() -> bool:
	step("убит: проверяем, что список остался, а выполнять нельзя")
	var unfinished: int = _initial_tasks[1]
	if not check(Game.tasks.get_local_tasks() == _initial_tasks and Game.tasks.is_local_done(_initial_tasks[0])
			and not Game.tasks.is_local_done(unfinished), "список убитого изменился"):
		return false
	if not check(not Game.tasks.is_pending(Net.local_id(), unfinished) and not _stations[unfinished].is_marked(),
			"у убитого задание всё ещё в работе или отмечено меткой"):
		return false
	if not await force_hold(_stations[unfinished], _stations[unfinished].hold_seconds + NOTHING_SEC):
		return false
	return check(not Game.tasks.is_local_done(unfinished), "убитый выполнил задание")


## Убитый выходит и заходит снова — теперь он зритель, вошедший посреди матча: общий
## прогресс ему присылают, а списка заданий, меток и роли у него нет.
func _rejoin_as_spectator(expected_total: int) -> bool:
	step("выходим и заходим снова зрителем")
	if not await rejoin() or not _scan_map():
		return false
	if not await expect(func() -> bool: return Game.tasks.total_count == expected_total, REPLY_DEADLINE_SEC,
			"опоздавший не получил общий прогресс: %d/%d" % [Game.tasks.done_count, Game.tasks.total_count]):
		return false
	if not check(Game.tasks.done_count >= CREW_COUNT and Game.tasks.done_count <= expected_total,
			"у опоздавшего сделано %d" % Game.tasks.done_count):
		return false
	if not check(Game.tasks.get_local_tasks().is_empty() and Game.local_role == Game.Role.NONE and me() == null,
			"у зрителя есть список заданий, роль или аватар"):
		return false
	for station_id: int in _stations:
		if not check(not _stations[station_id].is_marked() and not Game.tasks.is_pending(Net.local_id(), station_id),
				"у зрителя отмечена станция %s" % _stations[station_id].name):
			return false
	return true


## Живой экипаж: ждём, пока убитый коллега вернётся на сервер зрителем (без аватара).
func _wait_victim_rejoined() -> bool:
	var victim_name: String = _find_victim_name()
	return await expect(func() -> bool: return peer_named(victim_name) != 0 and avatar_named(victim_name) == null,
			STAGE_DEADLINE_SEC, "убитый %s не вернулся на сервер зрителем" % victim_name)


## Имя члена экипажа, чей аватар мёртв или уже исчез (убитый перезашёл); пусто — все живы.
func _find_victim_name() -> String:
	for number: int in range(2, expected_players + 1):
		var candidate: String = "Bot%d" % number
		var body: Player = avatar_named(candidate)
		if body == null or body.life != Player.Life.ALIVE:
			return candidate
	return ""


## Живой экипаж: тот, кому помощник назначил работу коллеги, видит её в списке; все
## доделывают всё, что у них осталось.
func _finish_crew_tasks(is_receiver: bool) -> bool:
	var tasks: PackedInt32Array = Game.tasks.get_local_tasks()
	if is_receiver:
		step("получил работу погибшего коллеги")
		if not check(tasks.size() == TASKS_PER_PLAYER + 1 and tasks.slice(0, TASKS_PER_PLAYER) == _initial_tasks,
				"список получателя: %s (был %s)" % [tasks, _initial_tasks]):
			return false
		var handed: int = tasks[TASKS_PER_PLAYER]
		if not check(not _initial_tasks.has(handed) and Game.tasks.is_pending(Net.local_id(), handed)
				and _stations[handed].is_marked(), "работа коллеги не ждёт получателя или не отмечена меткой"):
			return false
	elif not check(tasks == _initial_tasks, "список изменился, хотя работу коллеги получил не этот бот: %s" % tasks):
		return false
	for station_id: int in tasks:
		if Game.tasks.is_pending(Net.local_id(), station_id) and not await _complete(station_id):
			return false
	return true


## Этапы серверного помощника (см. tasks_roles_director.gd).
class DirectorStages:
	const FAKE_DONE: int = 1
	const HANDED: int = 20
	const DROPPED: int = 30
