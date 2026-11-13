class_name SnapshotInterpolator
extends RefCounted
## Плавный показ позиции, которую сервер присылает снимками.
## Клиент рисует кадры чаще, чем приходят снимки, поэтому позицию ведём по своим часам
## вдоль последнего отрезка между снимками. Номер серверного тика в снимке говорит, сколько
## времени их разделяет: потерянный пакет или два тика за один кадр сервера не дают рывка.
## Порядок вызовов в кадре: сначала push() для пришедших снимков, потом один advance().

## При большем расхождении (телепорт, респаун) не плывём, а переносим сразу.
const SNAP_DISTANCE: float = 3.0
## На сколько тиков можно продолжить движение по прямой, если снимок опаздывает.
const MAX_EXTRAPOLATION_TICKS: float = 2.0
## На сколько тиков показ может отстать от последнего снимка. Пачку снимков после
## подвисшего кадра не доигрываем, а сразу встаём рядом с последним.
const MAX_LAG_TICKS: float = 3.0
## В кадре, когда пришёл снимок, показ обычно отстаёт от него не больше чем на тик.
## Если он вышел за эти границы (разошлись часы, подвис кадр), понемногу возвращаем.
const MIN_LEAD_TICKS: float = -1.25
const MAX_LEAD_TICKS: float = 0.25
## Шаг возврата за один снимок: достаточно мал, чтобы не быть заметным.
const LEAD_CORRECTION_TICKS: float = 0.02

## Последний снимок.
var _position: Vector3 = Vector3.ZERO
var _tick: int = 0
## Смещение за один тик на последнем отрезке.
var _step: Vector3 = Vector3.ZERO
## На сколько тиков показ опережает последний снимок. Меньше нуля — ещё не дошли до него.
var _lead_ticks: float = -1.0
var _is_reset: bool = true
var _has_new_snapshot: bool = false


## Встать точно в позицию: первый снимок после спавна.
func reset(position: Vector3, tick: int) -> void:
	_position = position
	_tick = tick
	_step = Vector3.ZERO
	_lead_ticks = -1.0
	_is_reset = true
	_has_new_snapshot = false


## Пришёл снимок состояния с сервера.
func push(position: Vector3, tick: int) -> void:
	var ticks: int = tick - _tick
	# Тот же тик (сервер не успел шагнуть между кадрами) или опоздавший старый пакет.
	if ticks <= 0:
		return
	if _position.distance_to(position) > SNAP_DISTANCE:
		reset(position, tick)
		return
	_step = (position - _position) / ticks
	_position = position
	_tick = tick
	_lead_ticks = maxf(_lead_ticks - ticks, -MAX_LAG_TICKS)
	_has_new_snapshot = true


## Продвигает показ на время кадра и возвращает позицию.
func advance(delta: float, ticks_per_second: float) -> Vector3:
	if _is_reset:
		# Снимок пришёл в этом же кадре: время кадра прошло до него, а не после.
		_is_reset = false
	else:
		_lead_ticks = minf(_lead_ticks + delta * ticks_per_second, MAX_EXTRAPOLATION_TICKS)
	if _has_new_snapshot:
		_has_new_snapshot = false
		if _lead_ticks > MAX_LEAD_TICKS:
			_lead_ticks -= LEAD_CORRECTION_TICKS
		elif _lead_ticks < MIN_LEAD_TICKS:
			_lead_ticks += LEAD_CORRECTION_TICKS
	return _position + _step * _lead_ticks
