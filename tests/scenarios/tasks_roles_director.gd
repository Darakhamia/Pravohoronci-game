extends Node
## Серверный помощник сценария tasks_roles. Знает то, чего не знает ни один клиент
## (чужие списки заданий), поэтому сам выбирает жертву, проверяет учёт на сервере и
## сообщает ботам этап через общее состояние предмета карты StageSwitch:
##   STAGE_FAKE_DONE     — предатель «выполнил» фальшивое задание;
##   STAGE_KILLED        — члена экипажа тихо убили: до собрания ни у кого ничего не меняется;
##   STAGE_HANDED + N    — началось собрание, несделанное задание убитого получил BotN;
##   STAGE_DROPPED       — началось собрание, а задание убитого взять некому.
## После убийства помощник ждёт, пока убитый выйдет из игры и вернётся зрителем (выход уже
## мёртвого игрока тоже ничего не меняет) и пока каждый живой бот знаком (взгляд круто
## вверх) подтвердит, что убедился: у него ничего не изменилось. Тогда помощник созывает
## собрание от имени живого игрока — и только теперь работа погибшего переходит к живым.
## В сценарии tasks_drop живой экипаж до знака успевает доделать свои задания: победы по
## заданиям при этом нет (задание погибшего ещё в счёте), а собрание её сразу приносит.
## Провал проверки — push_error: строку ERROR в логе сервера ловит run_scenario.sh.

const STAGE_FAKE_DONE: int = 1
const STAGE_KILLED: int = 10
const STAGE_HANDED: int = 20
const STAGE_DROPPED: int = 30
const TRAITOR_NAME: String = "Bot1"
const BOT_PREFIX: String = "Bot"
const KILL_DAMAGE: int = 100
const CREW_COUNT: int = 3
const TASKS_PER_PLAYER: int = 2
const TOTAL_TASKS: int = CREW_COUNT * TASKS_PER_PLAYER
## Тот же порог, что у ботов (tasks_roles.gd, SIGNAL_PITCH).
const SIGNAL_PITCH_THRESHOLD: float = 1.0

var _stage: int = 0
## peer_id -> станции, выданные на старте.
var _initial: Dictionary[int, PackedInt32Array] = {}
## Живой экипаж в момент убийства и сама жертва.
var _crew: Array[int] = []
var _victim: int = 0
var _victim_name: String = ""
## Несделанное задание жертвы и тот, кто должен получить его на собрании (0 — некому).
var _victim_station: int = 0
var _receiver: int = 0
## У кого задание жертвы ждало выполнения ещё до убийства (своё, а не работа коллеги).
var _had_pending: Dictionary[int, bool] = {}
var _is_victim_back: bool = false
var _is_meeting_called: bool = false


func _process(_delta: float) -> void:
	var map: GameMap = (get_tree().root.get_node(^"Main/World") as World).current_map
	if map == null:
		return
	if not Game.is_playing():
		return
	if _initial.is_empty():
		_snapshot(map)
	if _stage == 0 and _has_traitor_done_fake_task():
		# Фальшивое задание общий прогресс не двигает.
		_expect_progress(0, TOTAL_TASKS, "после фальшивого задания предателя")
		_set_stage(map, STAGE_FAKE_DONE)
	elif _stage == STAGE_FAKE_DONE and Game.tasks.done_count >= CREW_COUNT:
		_expect_progress(CREW_COUNT, TOTAL_TASKS, "после первых заданий экипажа")
		_kill_crew_member(map)
	elif _stage == STAGE_KILLED and not _is_meeting_called:
		_wait_and_call_meeting(map)


## Запомнить, кому что выдано, и проверить саму раздачу.
func _snapshot(map: GameMap) -> void:
	for peer_id: int in Game.participants:
		var stations: PackedInt32Array = []
		for interactable: Interactable in map.get_interactables():
			if interactable is TaskStation and Game.tasks.is_pending(peer_id, interactable.interact_id):
				stations.append(interactable.interact_id)
		_initial[peer_id] = stations
		if stations.size() != TASKS_PER_PLAYER:
			push_error("[director] игроку %s выдано заданий: %d" % [Net.get_player_name(peer_id), stations.size()])
	_expect_progress(0, TOTAL_TASKS, "на старте")


func _has_traitor_done_fake_task() -> bool:
	var traitor: int = _peer_named(TRAITOR_NAME)
	for station_id: int in _initial[traitor]:
		if not Game.tasks.is_pending(traitor, station_id):
			return true
	return false


## Убить члена экипажа, чьё несделанное задание кто-то из живых может взять. Если такой
## раздачи нет — убить первого (его задание на собрании пропадёт). Сразу после убийства
## для остальных ничего не меняется.
func _kill_crew_member(map: GameMap) -> void:
	_crew.clear()
	for peer_id: int in Game.participants:
		if Game.get_role(peer_id) != Game.Role.TRAITOR:
			_crew.append(peer_id)
	for candidate: int in _crew:
		var unfinished: int = _get_unfinished(candidate)
		# У всех живых осталось по одному заданию: при равенстве берёт первый по порядку лобби.
		for other: int in _crew:
			if other != candidate and not _initial[other].has(unfinished):
				_victim = candidate
				_victim_station = unfinished
				_receiver = other
				break
		if _victim != 0:
			break
	if _victim == 0:
		_victim = _crew[0]
		_victim_station = _get_unfinished(_victim)
	_victim_name = Net.get_player_name(_victim)
	for other: int in _crew:
		_had_pending[other] = Game.tasks.is_pending(other, _victim_station)
	map.get_player(_victim).body.server_apply_damage(BodyPart.Part.HEAD, KILL_DAMAGE)
	if Game.server_is_alive(_victim) or Game.tasks.is_pending(_victim, _victim_station):
		push_error("[director] жертва жива или её задание всё ещё ждёт её")
	if Game.phase != Game.Phase.PLAYING:
		push_error("[director] при одном предателе и двух живых членах экипажа матч закончился")
	_expect_untouched("сразу после убийства")
	_set_stage(map, STAGE_KILLED)


## Убитый выходит из игры и возвращается зрителем, живые подают знак — созываем собрание.
## Всё это время работа погибшего числится за ним.
func _wait_and_call_meeting(map: GameMap) -> void:
	if Net.players.has(_victim) or _peer_named(_victim_name) == 0:
		return
	if not _is_victim_back:
		_is_victim_back = true
		_expect_untouched("после выхода убитого из игры")
		print("[director] убитый вернулся зрителем")
	for peer_id: int in Game.server_get_alive():
		var player: Player = map.get_player(peer_id)
		if player == null or player.input.get_pitch() <= SIGNAL_PITCH_THRESHOLD:
			return
	_expect_untouched("перед собранием")
	var done_before: int = Game.tasks.done_count
	_is_meeting_called = true
	var caller: int = 0
	for peer_id: int in _crew:
		if peer_id != _victim:
			caller = peer_id
			break
	# Тело вышедшего убитого лежит до собрания: о нём и сообщаем.
	if not Game.meeting.server_call(caller, Meeting.Reason.BODY, _victim):
		push_error("[director] собрание не началось")
		return
	# Все подписчики Meeting.started уже отработали: работа погибшего передана или пропала.
	_check_hand_over(map, done_before)


## Собрание началось: работа погибшего передана (или пропала) именно сейчас.
func _check_hand_over(map: GameMap, done_before: int) -> void:
	if _receiver != 0:
		_expect_progress(done_before, TOTAL_TASKS, "после передачи задания погибшего")
		for other: int in _crew:
			if other == _victim:
				continue
			var is_expected: bool = other == _receiver or _had_pending[other]
			if Game.tasks.is_pending(other, _victim_station) != is_expected:
				push_error("[director] задание погибшего не у того игрока: %s" % Net.get_player_name(other))
		_set_stage(map, STAGE_HANDED + Net.get_player_name(_receiver).trim_prefix(BOT_PREFIX).to_int())
		return
	_expect_progress(done_before, TOTAL_TASKS - 1, "после пропажи задания погибшего")
	# Если живые к этому моменту всё доделали, пропавшее задание закрывает счёт: победа
	# экипажа прямо в начале собрания.
	var is_all_done: bool = done_before == TOTAL_TASKS - 1
	if is_all_done != (Game.phase == Game.Phase.ENDED):
		push_error("[director] после пропажи задания погибшего сделано %d из %d, а фаза матча %s" % [
				done_before, TOTAL_TASKS - 1, Game.Phase.find_key(Game.phase)])
	_set_stage(map, STAGE_DROPPED)


## О гибели ещё не объявлено: общий счёт заданий прежний, задание жертвы ни к кому не
## перешло, победы по заданиям нет — даже если живые доделали всё своё.
func _expect_untouched(moment: String) -> void:
	if Game.tasks.total_count != TOTAL_TASKS or Game.tasks.done_count < CREW_COUNT \
			or Game.tasks.done_count >= TOTAL_TASKS:
		push_error("[director] %s прогресс %d/%d, а всего ждали %d" % [
				moment, Game.tasks.done_count, Game.tasks.total_count, TOTAL_TASKS])
	if Game.phase != Game.Phase.PLAYING:
		push_error("[director] %s фаза матча %s" % [moment, Game.Phase.find_key(Game.phase)])
	for other: int in _crew:
		if other != _victim and Game.tasks.is_pending(other, _victim_station) and not _had_pending[other]:
			push_error("[director] %s задание погибшего уже у игрока %s" % [moment, Net.get_player_name(other)])


## Единственное несделанное задание игрока из выданных на старте; 0 — такого нет.
func _get_unfinished(peer_id: int) -> int:
	var pending: PackedInt32Array = []
	for station_id: int in _initial[peer_id]:
		if Game.tasks.is_pending(peer_id, station_id):
			pending.append(station_id)
	if pending.size() != 1:
		push_error("[director] у игрока %s несделанных заданий: %d" % [Net.get_player_name(peer_id), pending.size()])
	return pending[0] if not pending.is_empty() else 0


func _expect_progress(done: int, total: int, moment: String) -> void:
	if Game.tasks.done_count != done or Game.tasks.total_count != total:
		push_error("[director] %s прогресс %d/%d, а ждали %d/%d" % [
				moment, Game.tasks.done_count, Game.tasks.total_count, done, total])


func _set_stage(map: GameMap, stage: int) -> void:
	_stage = stage
	for interactable: Interactable in map.get_interactables():
		if interactable is TestSwitch:
			interactable.server_set_state(stage)
	print("[director] stage %d" % stage)


func _peer_named(player_name: String) -> int:
	for peer_id: int in Net.players:
		if Net.players[peer_id] == player_name:
			return peer_id
	return 0
