class_name HudToast
extends PanelContainer
## Одно короткое уведомление HUD: значок и строка. Само гаснет, когда выходит время.
## Создаёт и переиспользует его HudToasts.

## Уведомление погасло и освободило место.
signal expired

enum Kind {
	## Получилось: задание выполнено.
	SUCCESS,
	## Не получилось, но не страшно: мимо зоны, нет патронов.
	WARNING,
	## Потеря: неверный код, оторванная конечность.
	DANGER,
}

const ICON_KIND: Dictionary[Kind, UiIcon.Kind] = {
	Kind.SUCCESS: UiIcon.Kind.CHECK,
	Kind.WARNING: UiIcon.Kind.ALERT,
	Kind.DANGER: UiIcon.Kind.ALERT,
}
const ICON_COLOR: Dictionary[Kind, Color] = {
	Kind.SUCCESS: UiTokens.SUCCESS,
	Kind.WARNING: UiTokens.WARNING,
	Kind.DANGER: UiTokens.DANGER,
}

@onready var _icon: UiIcon = %Icon
@onready var _text: Label = %Text
@onready var _life: Timer = %Life


func _ready() -> void:
	_life.timeout.connect(_on_life_timeout)


## Показывает уведомление на seconds секунд; повторный вызов начинает отсчёт заново.
func show_toast(text: String, kind: Kind, seconds: float) -> void:
	_text.text = text
	_icon.set_icon(ICON_KIND[kind], ICON_COLOR[kind])
	var was_visible: bool = visible
	visible = true
	if was_visible:
		UiMotion.stop(self)
	else:
		UiMotion.fade_in(self)
	_life.start(maxf(seconds, 0.1))


func hide_toast() -> void:
	_life.stop()
	UiMotion.stop(self)
	visible = false


func get_text() -> String:
	return _text.text


func _on_life_timeout() -> void:
	UiMotion.fade_out(self, _finish)


func _finish() -> void:
	visible = false
	modulate.a = 1.0
	expired.emit()
