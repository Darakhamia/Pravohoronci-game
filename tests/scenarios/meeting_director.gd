extends Node
## Серверный помощник сценария meeting: убивает Bot2 вскоре после начала игры и проверяет
## по часам сервера, что голосование закончилось досрочно — когда проголосовали все живые.
## О нарушении сообщает ошибкой в логе сервера: run_scenario.sh считает её провалом.

const VICTIM_NAME: String = "Bot2"
## Секунды с начала фазы PLAYING.
const KILL_AT_SEC: float = 1.0
const KILL_DAMAGE: int = 100
## Досрочное голосование должно закончиться хотя бы на столько секунд раньше срока.
const EARLY_MARGIN_SEC: float = 2.0
const MSEC_PER_SEC: float = 1000.0

var _elapsed: float = 0.0
var _is_victim_killed: bool = false
var _voting_started_msec: int = 0


func _ready() -> void:
	Game.meeting.stage_changed.connect(_on_stage_changed)


func _process(delta: float) -> void:
	if not Game.is_playing() or _is_victim_killed:
		return
	_elapsed += delta
	if _elapsed >= KILL_AT_SEC:
		_is_victim_killed = true
		_get_victim().body.server_apply_damage(BodyPart.Part.HEAD, KILL_DAMAGE)


func _on_stage_changed(new_stage: Meeting.Stage) -> void:
	if new_stage == Meeting.Stage.VOTING:
		_voting_started_msec = Time.get_ticks_msec()
	elif new_stage == Meeting.Stage.VERDICT:
		var voting_sec: float = (Time.get_ticks_msec() - _voting_started_msec) / MSEC_PER_SEC
		if voting_sec > Game.config.meeting_voting_seconds - EARLY_MARGIN_SEC:
			push_error("[director] голосование шло %.1f с и не закончилось досрочно" % voting_sec)


func _get_victim() -> Player:
	var world: World = get_tree().root.get_node(^"Main/World") as World
	for peer_id: int in Net.players:
		if Net.players[peer_id] == VICTIM_NAME:
			return world.current_map.get_player(peer_id)
	return null
