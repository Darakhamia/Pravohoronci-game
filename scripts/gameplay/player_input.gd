class_name PlayerInput
extends Node
## Ввод одного игрока. У владельца — опрос клавиш и мыши, на сервере — последний
## принятый ввод. Сам по сети ничего не шлёт: World слушает сигналы и передаёт их серверу.

## Клиент-владелец: раз в физический кадр.
signal sampled(direction: Vector2, yaw: float, pitch: float)
## Клиент-владелец: нажат прыжок.
signal jump_pressed

## Чуть меньше 90°, чтобы камера не переворачивалась через зенит.
const MAX_PITCH: float = deg_to_rad(89.0)
## Сервер: ввод старше этого считается отсутствующим (клиент завис или пропал).
const STALE_AFTER_MSEC: int = 300

## Углы взгляда. У владельца живые (камера берёт их сразу), на сервере — последние принятые.
var yaw: float = 0.0
var pitch: float = 0.0
## Владелец: false — игрок стоит, мышь и прыжок не действуют (пауза в HUD).
var enabled: bool = true

var _move_direction: Vector2 = Vector2.ZERO
var _jump_queued: bool = false
var _has_input: bool = false
var _received_msec: int = 0


func _ready() -> void:
	set_physics_process(false)
	set_process_input(false)


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	if enabled:
		direction = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	sampled.emit(direction, yaw, pitch)
	# Опрос, а не событие: Input.action_press() у ботов событий не создаёт.
	if enabled and Input.is_action_just_pressed(&"jump"):
		jump_pressed.emit()


## _input, а не _unhandled_input: при захваченной мыши события приходят в центр экрана,
## и любой элемент HUD с обычным mouse_filter молча съел бы обзор.
func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null or not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var turn: Vector2 = motion.screen_relative * Settings.mouse_sensitivity
	# Мышь вправо — поворот вправо (yaw убывает), мышь вверх — взгляд вверх.
	yaw = sanitize_yaw(yaw - turn.x)
	pitch = sanitize_pitch(pitch - turn.y)


## Вызывает Player на клиенте-владельце: включает опрос ввода.
func activate_local(initial_yaw: float) -> void:
	yaw = sanitize_yaw(initial_yaw)
	set_physics_process(true)
	set_process_input(true)


## Сервер: принять ввод клиента. Значения чистятся здесь, клиенту не доверяем.
func receive(direction: Vector2, new_yaw: float, new_pitch: float) -> void:
	_move_direction = sanitize_direction(direction)
	yaw = sanitize_yaw(new_yaw)
	pitch = sanitize_pitch(new_pitch)
	_received_msec = Time.get_ticks_msec()
	_has_input = true


## Сервер: клиент нажал прыжок.
func queue_jump() -> void:
	_jump_queued = true


## Сервер: ввод приходил хотя бы раз.
func has_input() -> bool:
	return _has_input


## Сервер: направление движения, ZERO если ввод устарел.
func get_move_direction() -> Vector2:
	if Time.get_ticks_msec() - _received_msec > STALE_AFTER_MSEC:
		return Vector2.ZERO
	return _move_direction


func get_yaw() -> float:
	return yaw


func get_pitch() -> float:
	return pitch


## Сервер: вернуть флаг прыжка и сбросить его.
func consume_jump() -> bool:
	var queued: bool = _jump_queued
	_jump_queued = false
	return queued


static func sanitize_direction(value: Vector2) -> Vector2:
	if not value.is_finite():
		return Vector2.ZERO
	return value.limit_length(1.0)


static func sanitize_yaw(value: float) -> float:
	if not is_finite(value):
		return 0.0
	if absf(value) <= PI:
		return value
	# fposmod, а не wrapf: wrapf теряет точность на огромных значениях от клиента.
	return fposmod(value + PI, TAU) - PI


static func sanitize_pitch(value: float) -> float:
	if not is_finite(value):
		return 0.0
	return clampf(value, -MAX_PITCH, MAX_PITCH)
