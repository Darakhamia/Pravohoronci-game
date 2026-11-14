class_name UiMotion
extends RefCounted
## Короткие появления экранов и подсказок. Без окна (сервер, боты, тесты) анимаций нет:
## контрол сразу получает конечное состояние, поэтому логика от них не зависит.

const HEADLESS_DISPLAY: String = "headless"
const TWEEN_META: StringName = &"ui_motion_tween"

## Скриншотные тесты выключают анимации, чтобы снимать конечное состояние.
static var enabled: bool = DisplayServer.get_name() != HEADLESS_DISPLAY


## Плавно проявляет контрол из прозрачности.
static func fade_in(control: CanvasItem) -> void:
	_stop(control)
	if not enabled or not control.is_inside_tree():
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	var tween: Tween = control.create_tween()
	tween.tween_property(control, ^"modulate:a", 1.0, UiTokens.FADE_SEC)
	control.set_meta(TWEEN_META, tween)


## Медленное «дыхание» прозрачности между low и 1.0, пока не вызван stop().
static func pulse(control: CanvasItem, low: float, period_sec: float) -> void:
	_stop(control)
	control.modulate.a = 1.0
	if not enabled or not control.is_inside_tree():
		return
	var tween: Tween = control.create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, ^"modulate:a", low, period_sec / 2.0)
	tween.tween_property(control, ^"modulate:a", 1.0, period_sec / 2.0)
	control.set_meta(TWEEN_META, tween)


## Плавно гасит контрол и по окончании вызывает done (например, чтобы спрятать его).
## Без анимаций done вызывается сразу.
static func fade_out(control: CanvasItem, done: Callable) -> void:
	_stop(control)
	if not enabled or not control.is_inside_tree():
		control.modulate.a = 1.0
		done.call()
		return
	var tween: Tween = control.create_tween()
	tween.tween_property(control, ^"modulate:a", 0.0, UiTokens.FADE_SEC)
	tween.tween_callback(done)
	control.set_meta(TWEEN_META, tween)


## Короткая встряска по горизонтали вокруг rest_x: «не то». Контрол не должен лежать
## в контейнере (тот вернул бы его на место посреди анимации).
static func shake(control: Control, rest_x: float) -> void:
	_stop(control)
	control.position.x = rest_x
	if not enabled or not control.is_inside_tree():
		return
	var tween: Tween = control.create_tween()
	var step_sec: float = UiTokens.SHAKE_SEC / (UiTokens.SHAKE_SWINGS + 1)
	for swing: int in UiTokens.SHAKE_SWINGS:
		var side: float = 1.0 if swing % 2 == 0 else -1.0
		# Каждое качание слабее предыдущего.
		var reach: float = UiTokens.SHAKE_PX * (1.0 - float(swing) / UiTokens.SHAKE_SWINGS)
		tween.tween_property(control, ^"position:x", rest_x + side * reach, step_sec)
	tween.tween_property(control, ^"position:x", rest_x, step_sec)
	control.set_meta(TWEEN_META, tween)


## Останавливает анимацию контрола и возвращает ему полную непрозрачность.
static func stop(control: CanvasItem) -> void:
	_stop(control)
	control.modulate.a = 1.0


static func _stop(control: CanvasItem) -> void:
	if not control.has_meta(TWEEN_META):
		return
	var tween: Tween = control.get_meta(TWEEN_META) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	control.remove_meta(TWEEN_META)
