extends Node
## Серверный помощник сценария tasks_public. Знает списки всех игроков, поэтому сам
## проверяет учёт на сервере и сообщает ботам, чей список вырос, через общее состояние
## предмета карты StageSwitch:
##   STAGE_LEFT + 10 * A + B              — Bot3 вышел из игры живым; из его двух заданий
##                                           A получил Bot1 и B — Bot2 (остальные пропали);
##   STAGE_EJECTED + 10 * D + A           — Bot2 изгнан; A его заданий получил Bot1,
##                                           D пропали (Bot1 уже имел эти станции).
## Между этапами созывает собрание от имени Bot1 — когда оба живых бота знаком (взгляд
## круто вверх) подтвердят, что проверили первый этап. Заданий до конца никто не делает,
## поэтому «задание ждёт игрока» и «станция есть в его списке» здесь одно и то же.
## Провал проверки — push_error: строку ERROR в логе сервера ловит run_scenario.sh.

const STAGE_LEFT: int = 100
const STAGE_EJECTED: int = 200
const STAGE_STEP: int = 10
const LAST_NAME: String = "Bot1"
const EJECTED_NAME: String = "Bot2"
const LEAVER_NAME: String = "Bot3"
const CREW_COUNT: int = 3
const TASKS_PER_PLAYER: int = 2
const TOTAL_TASKS: int = CREW_COUNT * TASKS_PER_PLAYER
## Тот же порог, что у ботов (tasks_public.gd, SIGNAL_PITCH).
const SIGNAL_PITCH_THRESHOLD: float = 1.0

var _stage: int = 0
var _last: int = 0
var _ejected: int = 0
var _leaver: int = 0
## peer_id -> станции, которые ждут игрока (обновляется после каждой передачи).
var _lists: Dictionary[int, PackedInt32Array] = {}
var _total: int = TOTAL_TASKS
var _meetings_started: int = 0
var _is_meeting_called: bool = false


func _ready() -> void:
	Game.meeting.started.connect(func() -> void: _meetings_started += 1)


func _process(_delta: float) -> void:
	var map: GameMap = (get_tree().root.get_node(^"Main/World") as World).current_map
	if map == null or Game.phase == Game.Phase.NONE or Game.phase == Game.Phase.ENDED:
		return
	if _lists.is_empty():
		_snapshot(map)
	elif _stage == 0:
		if not Net.players.has(_leaver):
			_check_leaver(map)
	elif _stage < STAGE_EJECTED and not _is_meeting_called:
		if Game.is_playing() and _has_signal(map, _last) and _has_signal(map, _ejected):
			_is_meeting_called = true
			if not Game.meeting.server_call(_last, Meeting.Reason.BUTTON):
				push_error("[director] собрание не началось")
	elif _stage < STAGE_EJECTED and not Game.server_is_alive(_ejected):
		_check_ejected(map)


## Запомнить игроков и их списки; проверить саму раздачу.
func _snapshot(map: GameMap) -> void:
	_last = _peer_named(LAST_NAME)
	_ejected = _peer_named(EJECTED_NAME)
	_leaver = _peer_named(LEAVER_NAME)
	for peer_id: int in [_last, _ejected, _leaver]:
		_lists[peer_id] = _get_pending(map, peer_id)
		if _lists[peer_id].size() != TASKS_PER_PLAYER:
			push_error("[director] игроку %s выдано заданий: %d" % [Net.get_player_name(peer_id), _lists[peer_id].size()])
	_expect_total("на старте")


## Bot3 вышел из игры живым: его работа перешла к живым сразу, без собрания.
func _check_leaver(map: GameMap) -> void:
	if _meetings_started != 0 or not Game.is_playing():
		push_error("[director] к выходу игрока уже шло собрание или игра не идёт")
	var living: Array[int] = [_last, _ejected]
	var growth: Dictionary[int, int] = _check_hand_over(map, _leaver, living, "после выхода игрока")
	_set_stage(map, STAGE_LEFT + STAGE_STEP * growth[_last] + growth[_ejected])


## Bot2 изгнан голосованием: его работа перешла к последнему живому сразу, второго
## собрания для этого не понадобилось.
func _check_ejected(map: GameMap) -> void:
	if _meetings_started != 1:
		push_error("[director] собраний было %d, а ждали одно" % _meetings_started)
	var living: Array[int] = [_last]
	var total_before: int = _total
	var growth: Dictionary[int, int] = _check_hand_over(map, _ejected, living, "после изгнания")
	_set_stage(map, STAGE_EJECTED + STAGE_STEP * (total_before - _total) + growth[_last])


## Проверить, что несделанная работа выбывшего распределена среди живых: каждую станцию
## получил ровно один из тех, у кого её не было, а если она есть у всех — она пропала из
## общего счёта. Возвращает, на сколько вырос список каждого живого.
func _check_hand_over(map: GameMap, out_id: int, living: Array[int], moment: String) -> Dictionary[int, int]:
	var growth: Dictionary[int, int] = {}
	var new_lists: Dictionary[int, PackedInt32Array] = {}
	for peer_id: int in living:
		growth[peer_id] = 0
		new_lists[peer_id] = _get_pending(map, peer_id)
		for station_id: int in _lists[peer_id]:
			if not new_lists[peer_id].has(station_id):
				push_error("[director] %s у игрока %s пропало задание" % [moment, Net.get_player_name(peer_id)])
	for station_id: int in _lists[out_id]:
		if Game.tasks.is_pending(out_id, station_id):
			push_error("[director] %s задание всё ещё ждёт выбывшего" % moment)
		var takers: int = 0
		var could_take: bool = false
		for peer_id: int in living:
			if _lists[peer_id].has(station_id):
				continue
			could_take = true
			if new_lists[peer_id].has(station_id):
				takers += 1
				growth[peer_id] += 1
		if takers != (1 if could_take else 0):
			push_error("[director] %s задание выбывшего получили %d игроков" % [moment, takers])
		if not could_take:
			_total -= 1
	for peer_id: int in living:
		if new_lists[peer_id].size() != _lists[peer_id].size() + growth[peer_id]:
			push_error("[director] %s у игрока %s в списке лишние задания" % [moment, Net.get_player_name(peer_id)])
		_lists[peer_id] = new_lists[peer_id]
	_expect_total(moment)
	return growth


func _get_pending(map: GameMap, peer_id: int) -> PackedInt32Array:
	var stations: PackedInt32Array = []
	for interactable: Interactable in map.get_interactables():
		if interactable is TaskStation and Game.tasks.is_pending(peer_id, interactable.interact_id):
			stations.append(interactable.interact_id)
	return stations


func _expect_total(moment: String) -> void:
	if Game.tasks.done_count != 0 or Game.tasks.total_count != _total:
		push_error("[director] %s прогресс %d/%d, а ждали 0/%d" % [
				moment, Game.tasks.done_count, Game.tasks.total_count, _total])


## Подал ли игрок знак взглядом вверх.
func _has_signal(map: GameMap, peer_id: int) -> bool:
	var player: Player = map.get_player(peer_id)
	return player != null and player.input.get_pitch() > SIGNAL_PITCH_THRESHOLD


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
