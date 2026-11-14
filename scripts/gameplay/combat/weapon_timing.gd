class_name WeaponTiming
extends RefCounted
## Сервер: когда оружием в руках можно атаковать и когда его можно убрать. Чистый счёт
## в физических тиках, без узлов: PlayerWeapons держит один такой объект на игрока.
## Три правила:
## - оружие достают: после draw() им нельзя атаковать, пока не пройдёт время доставания.
##   Иначе предатель доставал бы нож, бил и прятал его за два тика — никто бы не увидел;
## - после атаки (attack()) идёт пауза оружия: нельзя ни атаковать снова, ни убрать его;
## - общий запрет атак (lock_attacks()): в начале игры и после каждого собрания.

## Погрешность при переводе секунд в тики: 0.35 с на 60 тиках — ровно 21 тик.
const TICK_EPSILON: float = 0.001

## Тик, с которого оружие в руках достали до конца.
var _ready_tick: int = 0
## Тик, с которого кончается пауза после атаки.
var _free_tick: int = 0
## Тик, с которого снят общий запрет атак.
var _unlock_tick: int = 0


## Сколько физических тиков занимают seconds (с округлением вверх).
static func to_ticks(seconds: float, ticks_per_second: int) -> int:
	return maxi(ceili(maxf(seconds, 0.0) * ticks_per_second - TICK_EPSILON), 0)


## Начало раунда: всё можно сразу.
func reset() -> void:
	_ready_tick = 0
	_free_tick = 0
	_unlock_tick = 0


## В руках оказалось другое оружие: его достают draw_ticks тиков. Паузы прежнего оружия
## больше нет.
func draw(tick: int, draw_ticks: int) -> void:
	_ready_tick = tick + maxi(draw_ticks, 0)
	_free_tick = 0


## Можно ли атаковать на этом тике: оружие достали, пауза после прошлой атаки прошла,
## общего запрета нет.
func can_attack(tick: int) -> bool:
	return tick >= _ready_tick and tick >= _free_tick and tick >= _unlock_tick


## Атака состоялась: interval_ticks тиков нельзя ни атаковать, ни убрать оружие.
func attack(tick: int, interval_ticks: int) -> void:
	_free_tick = tick + maxi(interval_ticks, 0)


## Можно ли убрать оружие из рук (сменить, взять груз): после атаки — только когда
## пройдёт её пауза. Оружие, которым ещё не били, убирается сразу.
func can_put_away(tick: int) -> bool:
	return tick >= _free_tick


## Общий запрет атак на lock_ticks тиков.
func lock_attacks(tick: int, lock_ticks: int) -> void:
	_unlock_tick = tick + maxi(lock_ticks, 0)


## Сколько тиков осталось до конца общего запрета атак; 0 — запрета нет.
func get_lock_ticks_left(tick: int) -> int:
	return maxi(_unlock_tick - tick, 0)
