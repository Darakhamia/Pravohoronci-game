extends Node
## Серверный помощник сценария tasks_roles. Знает то, чего не знает ни один клиент
## (чужие списки заданий), поэтому сам выбирает жертву, проверяет учёт на сервере и
## сообщает ботам этап через общее состояние предмета карты StageSwitch:
##   STAGE_FAKE_DONE     — предатель «выполнил» фальшивое задание;
##   STAGE_HANDED + N    — члена экипажа убили, его несделанное задание получил BotN;
##   STAGE_DROPPED       — члена экипажа убили, а его задание взять некому (редкая раздача).
## Провал проверки — push_error: строку ERROR в логе сервера ловит run_scenario.sh.

const STAGE_FAKE_DONE: int = 1
const STAGE_HANDED: int = 20
const STAGE_DROPPED: int = 30
const TRAITOR_NAME: String = "Bot1"
const BOT_PREFIX: String = "Bot"
const KILL_DAMAGE: int = 100
const CREW_COUNT: int = 3
const TASKS_PER_PLAYER: int = 2
const TOTAL_TASKS: int = CREW_COUNT * TASKS_PER_PLAYER

var _stage: int = 0
## peer_id -> станции, выданные на старте.
var _initial: Dictionary[int, PackedInt32Array] = {}


func _process(_delta: float) -> void:
	if not Game.is_playing():
		return
	var map: GameMap = (get_tree().root.get_node(^"Main/World") as World).current_map
	if map == null:
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


## Убить члена экипажа, чьё несделанное задание кто-то из живых может взять, и проверить
## передачу. Если такой раздачи нет — убить первого и проверить, что задание пропало.
func _kill_crew_member(map: GameMap) -> void:
	var crew: Array[int] = []
	for peer_id: int in Game.participants:
		if Game.get_role(peer_id) != Game.Role.TRAITOR:
			crew.append(peer_id)
	var victim: int = 0
	var station_id: int = 0
	var receiver: int = 0
	for candidate: int in crew:
		var unfinished: int = _get_unfinished(candidate)
		# У всех живых осталось по одному заданию: при равенстве берёт первый по порядку лобби.
		for other: int in crew:
			if other != candidate and not _initial[other].has(unfinished):
				victim = candidate
				station_id = unfinished
				receiver = other
				break
		if victim != 0:
			break
	if victim == 0:
		victim = crew[0]
		station_id = _get_unfinished(victim)
	# У кого эта станция ждала выполнения ещё до убийства (своё задание, а не работа коллеги).
	var had_pending: Dictionary[int, bool] = {}
	for other: int in crew:
		had_pending[other] = Game.tasks.is_pending(other, station_id)
	map.get_player(victim).body.server_apply_damage(BodyPart.Part.HEAD, KILL_DAMAGE)
	if Game.server_is_alive(victim) or Game.tasks.is_pending(victim, station_id):
		push_error("[director] жертва жива или её задание всё ещё ждёт её")
	if Game.phase != Game.Phase.PLAYING:
		push_error("[director] при одном предателе и двух живых членах экипажа матч закончился")
	if receiver != 0:
		_expect_progress(CREW_COUNT, TOTAL_TASKS, "после передачи задания погибшего")
		for other: int in crew:
			if other != victim and Game.tasks.is_pending(other, station_id) != (other == receiver or had_pending[other]):
				push_error("[director] задание погибшего не у того игрока: %s" % Net.get_player_name(other))
		_set_stage(map, STAGE_HANDED + Net.get_player_name(receiver).trim_prefix(BOT_PREFIX).to_int())
	else:
		_expect_progress(CREW_COUNT, TOTAL_TASKS - 1, "после пропажи задания погибшего")
		_set_stage(map, STAGE_DROPPED)


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
