extends "res://tests/scenarios/combat_director.gd"
## Серверный помощник сценариев боя, в которых матч не кончается сам (никто не погибает
## или предателей нет): сторожит те же правила, что combat_director.gd, и возвращает всех
## в лобби, когда бот подаёт знак — живой игрок смотрит почти вертикально вверх
## (combat_base.gd: signal_finish()). В обычной игре сценария так высоко никто не смотрит.

## Взгляд выше этого угла — знак «сценарий закончен», рад.
const FINISH_PITCH: float = 1.2
## Сколько секунд после знака матч ещё идёт: боты успевают увидеть последние события.
const FINISH_DELAY_SEC: float = 2.0

var _is_finishing: bool = false
var _finish_left: float = 0.0


func _process(delta: float) -> void:
	super(delta)
	if _world == null or _world.current_map == null or Game.state != Game.State.MATCH:
		_is_finishing = false
		return
	if not _is_finishing:
		for player: Player in _world.current_map.get_players():
			if player.life == Player.Life.ALIVE and player.input.get_pitch() > FINISH_PITCH:
				print("[director] finish signal by=%s" % player.display_name)
				_is_finishing = true
				_finish_left = FINISH_DELAY_SEC
		return
	_finish_left -= delta
	if _finish_left <= 0.0:
		_is_finishing = false
		Game.end_match()
