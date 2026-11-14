extends Node
## Серверный помощник сценария core: по расписанию наносит урон, «созывает» собрание
## (сам сигнал, без модуля собраний) и убивает игрока. Боты проверяют, что они увидели.

## Секунды с начала фазы PLAYING.
const LIMB_LOSS_AT_SEC: float = 3.0
const MEETING_AT_SEC: float = 8.0
const KILL_AT_SEC: float = 10.0
const VICTIM_NAME: String = "Bot2"
const LIMB_DAMAGE: int = 40
const KILL_DAMAGE: int = 100

var _elapsed: float = 0.0
var _done_steps: int = 0


func _process(delta: float) -> void:
	if not Game.is_playing():
		return
	_elapsed += delta
	if _done_steps == 0 and _elapsed >= LIMB_LOSS_AT_SEC:
		_done_steps = 1
		_get_victim().body.server_apply_damage(BodyPart.Part.LEFT_LEG, LIMB_DAMAGE)
	elif _done_steps == 1 and _elapsed >= MEETING_AT_SEC:
		_done_steps = 2
		Game.meeting.started.emit()
	elif _done_steps == 2 and _elapsed >= KILL_AT_SEC:
		_done_steps = 3
		_get_victim().body.server_apply_damage(BodyPart.Part.HEAD, KILL_DAMAGE)


func _get_victim() -> Player:
	var world: World = get_tree().root.get_node(^"Main/World") as World
	for peer_id: int in Net.players:
		if Net.players[peer_id] == VICTIM_NAME:
			return world.current_map.get_player(peer_id)
	return null
