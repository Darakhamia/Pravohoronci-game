class_name SabotageAlarm
extends OmniLight3D
## Тревожная лампа — украшение карты: на клиентах пульсирует красным, пока идёт саботаж,
## в остальное время выключена. На сервере и без окна ничего не делает.

## Частота пульса, рад/с.
const PULSE_SPEED: float = 7.0
## Насколько лампа тускнеет между пиками (доля alert_energy).
const PULSE_FLOOR: float = 0.15

## Яркость на пике пульса.
@export_range(0.0, 16.0, 0.1) var alert_energy: float = 4.0

var _time: float = 0.0


func _ready() -> void:
	visible = false
	set_process(false)
	if Net.is_server() or DisplayServer.get_name() == "headless":
		return
	Game.sabotage.started.connect(_on_sabotage_changed)
	Game.sabotage.ended.connect(_on_sabotage_changed.unbind(1))
	# Опоздавший мог получить карту уже во время саботажа.
	_on_sabotage_changed()


func _process(delta: float) -> void:
	_time += delta
	var pulse: float = 0.5 + 0.5 * sin(_time * PULSE_SPEED)
	light_energy = alert_energy * lerpf(PULSE_FLOOR, 1.0, pulse)


func _on_sabotage_changed() -> void:
	var is_alert: bool = Game.sabotage.active
	visible = is_alert
	set_process(is_alert)
	_time = 0.0
