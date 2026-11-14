extends "res://tests/scenarios/combat_finish_director.gd"
## Серверный помощник сценария combat_sight: через секунду после начала игры убивает Bot4 —
## дальше тот смотрит матч призраком. Остальное делают боты; общие правила боя сторожит
## combat_director.gd, матч заканчивает combat_finish_director.gd.

const GHOST_NAME: String = "Bot4"
const KILL_AT_SEC: float = 1.0
const KILL_DAMAGE: int = 100

var _playing_sec: float = 0.0
var _is_killed: bool = false


func _process(delta: float) -> void:
	super(delta)
	if _is_killed or _world == null or _world.current_map == null or not Game.is_playing():
		return
	_playing_sec += delta
	if _playing_sec < KILL_AT_SEC:
		return
	_is_killed = true
	for player: Player in _world.current_map.get_players():
		if player.display_name == GHOST_NAME:
			player.body.server_apply_damage(BodyPart.Part.HEAD, KILL_DAMAGE)
			print("[director] ghost made of %s" % GHOST_NAME)
