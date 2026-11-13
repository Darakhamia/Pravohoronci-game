class_name Player
extends CharacterBody3D
## Аватар игрока. Двигает его только сервер; клиенты получают sync_* через StateSync
## и плавно показывают. Узел называется по id владельца.
## Игроки проходят друг сквозь друга: слой players, в маске только world.

const MOVEMENT: PlayerMovementConfig = preload("res://resources/player/player_movement.tres")
## Клиент: скорость догона серверного поворота чужих игроков, 1/с (больше — резче).
const TURN_SMOOTHING_RATE: float = 20.0

## Владелец аватара.
var peer_id: int = 0
## Состояние, которое сервер рассылает клиентам. Клиенты его только читают.
var sync_position: Vector3 = Vector3.ZERO
var sync_yaw: float = 0.0
var sync_pitch: float = 0.0
## Физический тик сервера, к которому относится состояние.
var sync_tick: int = 0
var display_name: String = ""

## Клиент: плавный показ позиции между снимками сервера.
var _interpolator: SnapshotInterpolator = SnapshotInterpolator.new()

@onready var input: PlayerInput = $Input
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _visuals: PlayerVisuals = $Visuals
@onready var _state_sync: MultiplayerSynchronizer = $StateSync


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
		_interpolator.reset(sync_position, sync_tick)
		_state_sync.synchronized.connect(_on_state_synchronized)
	_visuals.set_display_name(display_name)
	if is_local():
		input.activate_local(sync_yaw)
		_camera.fov = Settings.fov
		_camera.make_current()
		# Своё тело в камере от первого лица не показываем.
		_visuals.visible = false
	else:
		# Камера нужна только своему игроку: чужая не должна перехватить вид,
		# когда текущая исчезнет.
		_camera.queue_free()
		_camera = null


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
	sync_tick = Engine.get_physics_frames()


## Клиент: показать то, что прислал сервер.
func _process(delta: float) -> void:
	position = _interpolator.advance(delta, Engine.physics_ticks_per_second)
	if is_local():
		# Свой взгляд применяем сразу, не дожидаясь ответа сервера.
		rotation.y = input.yaw
		_head.rotation.x = input.pitch
	else:
		# Экспоненциальное сглаживание, не зависит от частоты кадров.
		var weight: float = 1.0 - exp(-TURN_SMOOTHING_RATE * delta)
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


## Клиент: пришёл новый снимок состояния.
func _on_state_synchronized() -> void:
	_interpolator.push(sync_position, sync_tick)


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
