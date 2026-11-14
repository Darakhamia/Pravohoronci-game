class_name TaskWiring
extends TaskStation
## Задание «проводка»: удержать E до конца (hold_seconds) — и готово.


## Сервер: игрок додержал E до конца.
func server_interact(player: Player) -> void:
	_server_succeed(player)
