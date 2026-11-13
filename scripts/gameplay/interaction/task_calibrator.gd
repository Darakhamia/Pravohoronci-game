class_name TaskCalibrator
extends TaskStation
## Задание «калибровка»: держать E, пока шкала заполняется (hold_seconds — время до конца
## шкалы), и ОТПУСТИТЬ в зелёной зоне. Отпустил мимо или додержал до конца (перелив) —
## попытка не засчитана, можно пробовать снова. HUD рисует шкалу по
## PlayerInteractor.hold_fraction и зоне zone_start..zone_end этой станции.

## Сервер: запас на дрожание сети с каждой стороны зоны, с.
const RELEASE_TOLERANCE_SEC: float = 0.1

## Зелёная зона — доли шкалы. Конец держи ниже 1 - HOLD_GRACE_SEC / hold_seconds:
## отпускание в самом конце PlayerInteractor считает удержанием до конца.
@export_range(0.0, 1.0, 0.01) var zone_start: float = 0.55
@export_range(0.0, 1.0, 0.01) var zone_end: float = 0.8


## Сервер: игрок отпустил E раньше конца шкалы — попал ли он в зелёную зону.
func server_release(player: Player, held_seconds: float) -> void:
	# Удержание сорвалось само (умер, началось собрание, отошёл) — это не попытка.
	if not can_interact(player) or not _server_is_in_reach(player):
		return
	if is_in_zone(held_seconds, hold_seconds, zone_start, zone_end, RELEASE_TOLERANCE_SEC):
		_server_succeed(player)
	else:
		_server_fail(player)


## Сервер: игрок додержал до конца шкалы — перелив.
func server_interact(player: Player) -> void:
	_server_fail(player)


## Попадает ли отпускание через held_seconds в зону (доли от fill_seconds) с запасом
## tolerance_sec с каждой стороны.
static func is_in_zone(held_seconds: float, fill_seconds: float, start_fraction: float,
		end_fraction: float, tolerance_sec: float) -> bool:
	if fill_seconds <= 0.0 or end_fraction < start_fraction:
		return false
	return (held_seconds >= start_fraction * fill_seconds - tolerance_sec
			and held_seconds <= end_fraction * fill_seconds + tolerance_sec)
