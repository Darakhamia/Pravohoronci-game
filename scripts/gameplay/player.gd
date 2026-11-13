class_name Player
extends CharacterBody3D
## Аватар игрока. Двигает его только сервер; клиенты получают sync_* через StateSync
## и плавно показывают. Узел называется по id владельца.

const MOVEMENT: PlayerMovementConfig = preload("res://resources/player/player_movement.tres")
## Клиент: скорость догона серверного состояния, 1/с (больше — резче).
const SMOOTHING_RATE: float = 20.0
## Клиент: при большем расхождении (телепорт, респаун) не плывём, а переносим сразу.
const SNAP_DISTANCE: float = 3.0

## Владелец аватара.
var peer_id: int = 0
## Состояние, которое сервер рассылает клиентам. Клиенты его только читают.
var sync_position: Vector3 = Vector3.ZERO
var sync_yaw: float = 0.0
var sync_pitch: float = 0.0
var display_name: String = ""

@onready var input: PlayerInput = $Input
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _visuals: PlayerVisuals = $Visuals


func _enter_tree() -> void:
	# Имя узла приходит со спавном раньше остальных свойств.
	peer_id = name.to_int()


func _ready() -> void:
	var on_server: bool = Net.is_server()
	set_physics_process(on_server)
	set_process(not on_server)
	if on_server:
		display_name = Net.get_player_name(peer_id)
		sync_position = position
		sync_yaw = rotation.y
	else:
		# Состояние спавна уже применено: встаём сразу на место, без подплывания из нуля.
		position = sync_position
		rotation.y = sync_yaw
	_visuals.set_display_name(display_name)
	if is_local():
		input.activate_local(sync_yaw)
		_camera.fov = Settings.fov
		_camera.make_current()
		# Своё тело в камере от первого лица не показываем.
		_visuals.visible = false


## Сервер: один шаг симуляции по последнему принятому вводу.
func _physics_process(delta: float) -> void:
	# Пока ввода не было, держим поворот, заданный точкой спавна.
	var yaw: float = input.get_yaw() if input.has_input() else rotation.y
	# Флаг снимаем каждый тик, чтобы нажатие в воздухе не сработало при приземлении.
	var jump: bool = input.consume_jump()
	_simulate(input.get_move_direction(), yaw, jump, delta)
	sync_position = position
	sync_yaw = rotation.y
	sync_pitch = input.get_pitch()


## Клиент: показать то, что прислал сервер.
func _process(delta: float) -> void:
	# Экспоненциальное сглаживание, не зависит от частоты кадров.
	var weight: float = 1.0 - exp(-SMOOTHING_RATE * delta)
	if position.distance_to(sync_position) > SNAP_DISTANCE:
		position = sync_position
	else:
		position = position.lerp(sync_position, weight)
	if is_local():
		# Свой взгляд применяем сразу, не дожидаясь ответа сервера.
		rotation.y = input.yaw
		_head.rotation.x = input.pitch
	else:
		rotation.y = lerp_angle(rotation.y, sync_yaw, weight)
		_visuals.set_look_pitch(sync_pitch)


func is_local() -> bool:
	return Net.is_joined() and peer_id == Net.local_id()


## Только для своего игрока: HUD выключает управление на время паузы.
func set_input_enabled(value: bool) -> void:
	if is_local():
		input.enabled = value


## Только сервер: перенести игрока и погасить скорость.
func teleport(target_position: Vector3) -> void:
	if not Net.is_server():
		return
	position = target_position
	velocity = Vector3.ZERO
	sync_position = position


## Шаг движения. Собран в одной функции, чтобы позже клиент мог повторять его
## для предсказания.
func _simulate(direction: Vector2, yaw: float, jump: bool, delta: float) -> void:
	rotation.y = yaw
	var on_floor: bool = is_on_floor()
	# direction: x — вправо, y — назад; вперёд у тела смотрит -Z.
	var target: Vector3 = basis * Vector3(direction.x, 0.0, direction.y) * MOVEMENT.move_speed
	var acceleration: float = MOVEMENT.ground_acceleration if on_floor else MOVEMENT.air_acceleration
	var horizontal: Vector2 = Vector2(velocity.x, velocity.z).move_toward(
			Vector2(target.x, target.z), acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if not on_floor:
		velocity.y -= MOVEMENT.gravity * delta
	elif jump:
		velocity.y = MOVEMENT.jump_velocity
	move_and_slide()
