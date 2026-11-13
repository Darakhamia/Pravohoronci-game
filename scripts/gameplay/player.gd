class_name Player
extends CharacterBody3D
## Аватар игрока. Двигает его только сервер; клиенты получают sync_* через StateSync
## и плавно показывают. Узел называется по id владельца.
## Игроки проходят друг сквозь друга: слой players, в маске только world.
##
## Всем пирам реплицируется то, что видно в мире: где игрок, жив ли он, каких конечностей
## нет и что у него в руках. Личное (здоровье, патроны) сервер шлёт одному хозяину:
## части игрока вызывают send_private(), а сам пакет отправляет World.
## После смерти узел не удаляется до конца матча: он лежит телом (Life.CORPSE), а после
## собрания или изгнания становится невидимым (Life.GONE).

## Все пиры: игрок умер или его тело убрали.
signal life_changed(new_life: Life)
## Все пиры: изменился набор потерянных конечностей (биты BodyPart.bit()).
signal limbs_changed(mask: int)
## Все пиры: в руках другой предмет (номер в PlayerWeapons.ITEMS).
signal held_item_changed(item_id: int)
## Сервер: личное сообщение хозяину аватара — его отправляет World.
signal private_sent(kind: Private, data: Array)
## Сервер: событие, которое видят все игроки, — его рассылает World.
signal event_sent(kind: Event, data: Array)
## Клиенты: пришло событие этого аватара (эффекты выстрела и удара).
signal event_received(kind: Event, data: Array)

enum Life { ALIVE, CORPSE, GONE }
## Личные сообщения сервера хозяину аватара.
enum Private { VITALS, LOADOUT, LOOK }
## События аватара, которые видят все.
enum Event { ATTACK }

const MOVEMENT: PlayerMovementConfig = preload("res://resources/player/player_movement.tres")
## Клиент: скорость догона серверного поворота чужих игроков, 1/с (больше — резче).
const TURN_SMOOTHING_RATE: float = 20.0
## Клиент: скорость, с которой камера опускается и поднимается при смене позы, м/с.
const EYE_HEIGHT_SPEED: float = 3.0
## Клиент: сдвиг за кадр больше этого — телепорт, а не движение: анимацию бега не включаем.
const MAX_FRAME_STEP: float = 1.0

## Владелец аватара.
var peer_id: int = 0
## Карта, на которой стоит аватар. Ставит GameMap.
var map: GameMap = null
## Состояние, которое сервер рассылает клиентам. Клиенты его только читают.
var sync_position: Vector3 = Vector3.ZERO
var sync_yaw: float = 0.0
var sync_pitch: float = 0.0
## Физический тик сервера, к которому относится состояние.
var sync_tick: int = 0
var display_name: String = ""
## Жив, лежит телом или убран с карты. Меняет сервер через server_set_life().
var life: Life = Life.ALIVE:
	set(value):
		if value == life:
			return
		life = value
		life_changed.emit(life)
## Потерянные конечности: биты BodyPart.bit(). Меняет сервер (PlayerBody).
var limbs_lost: int = 0:
	set(value):
		if value == limbs_lost:
			return
		limbs_lost = value
		limbs_changed.emit(limbs_lost)
## Предмет в руках: номер в PlayerWeapons.ITEMS. Меняет сервер (PlayerWeapons).
var held_item: int = PlayerWeapons.EMPTY_HANDS:
	set(value):
		if value == held_item:
			return
		held_item = value
		held_item_changed.emit(held_item)

## Клиент: плавный показ позиции между снимками сервера.
var _interpolator: SnapshotInterpolator = SnapshotInterpolator.new()

@onready var input: PlayerInput = $Input
@onready var body: PlayerBody = $Body
@onready var weapons: PlayerWeapons = $Weapons
@onready var interactor: PlayerInteractor = $Interactor
## Тело игрока как предмет: рядом с ним можно созвать собрание.
@onready var corpse: Interactable = $Corpse
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
## Руки и предмет от первого лица; есть только у своего игрока.
@onready var _viewmodel: Viewmodel = $Head/Camera3D/Viewmodel
@onready var _visuals: PlayerVisuals = $Visuals
@onready var _state_sync: MultiplayerSynchronizer = $StateSync


func _enter_tree() -> void:
	# Имя узла приходит со спавном раньше остальных свойств.
	peer_id = name.to_int()


func _ready() -> void:
	var on_server: bool = Net.is_server()
	set_physics_process(on_server)
	set_process(not on_server)
	corpse.interact_id = -peer_id
	if on_server:
		display_name = Net.get_player_name(peer_id)
		sync_position = position
		sync_yaw = rotation.y
		Game.round_started.connect(_on_round_started)
		interactor.activate()
	else:
		# Состояние спавна уже применено: встаём сразу на место, без подплывания из нуля.
		position = sync_position
		rotation.y = sync_yaw
		_interpolator.reset(sync_position, sync_tick)
		_state_sync.synchronized.connect(_on_state_synchronized)
		_visuals.set_body_color(PlayerPalette.color(Net.get_player_color(peer_id)))
		# Опоздавший видит уже потерянные конечности без эффекта отлёта.
		_visuals.set_limbs_lost(limbs_lost, false)
		limbs_changed.connect(_visuals.set_limbs_lost)
		held_item_changed.connect(_show_held_item.unbind(1))
		life_changed.connect(_show_life.unbind(1))
		event_received.connect(_on_event_received)
	_visuals.set_display_name(display_name)
	if is_local():
		input.activate_local(sync_yaw)
		interactor.activate()
		_camera.fov = Settings.fov
		_camera.make_current()
		_viewmodel.set_body_color(PlayerPalette.color(Net.get_player_color(peer_id)))
		_viewmodel.set_limbs_lost(limbs_lost)
		limbs_changed.connect(_viewmodel.set_limbs_lost)
	else:
		# Камера нужна только своему игроку: чужая не должна перехватить вид,
		# когда текущая исчезнет. Вместе с ней уходят и руки от первого лица.
		_camera.queue_free()
		_camera = null
		_viewmodel = null
	if not on_server:
		_show_held_item()
		_show_life()


## Сервер: один шаг симуляции по последнему принятому вводу.
func _physics_process(delta: float) -> void:
	var is_alive: bool = life == Life.ALIVE
	var can_act: bool = is_alive and Game.is_playing()
	# Тело не поворачивается за мышью хозяина. Пока ввода не было, держим поворот спавна.
	var yaw: float = input.get_yaw() if is_alive and input.has_input() else rotation.y
	# Флаг снимаем каждый тик, чтобы нажатие в воздухе не сработало при приземлении.
	var jump: bool = input.consume_jump() and can_act and body.can_jump()
	var direction: Vector2 = Vector2.ZERO
	if can_act:
		direction = input.get_move_direction() * body.get_speed_factor()
	# Убранный аватар стоит на месте: ему незачем падать и толкаться о стены.
	if life != Life.GONE:
		_simulate(direction, yaw, jump, delta)
	sync_position = position
	sync_yaw = rotation.y
	if is_alive:
		sync_pitch = input.get_pitch()
	sync_tick = Engine.get_physics_frames()


## Клиент: показать то, что прислал сервер.
func _process(delta: float) -> void:
	var previous: Vector3 = position
	position = _interpolator.advance(delta, Engine.physics_ticks_per_second)
	var step: Vector3 = position - previous
	var shown_velocity: Vector3 = Vector3.ZERO
	if delta > 0.0 and step.length() < MAX_FRAME_STEP:
		shown_velocity = step / delta
	_visuals.set_velocity(shown_velocity)
	if _viewmodel != null:
		_viewmodel.set_velocity(shown_velocity)
	if is_local() and life == Life.ALIVE:
		# Свой взгляд применяем сразу, не дожидаясь ответа сервера.
		rotation.y = input.yaw
		_head.rotation.x = input.pitch
	else:
		# Экспоненциальное сглаживание, не зависит от частоты кадров.
		var weight: float = 1.0 - exp(-TURN_SMOOTHING_RATE * delta)
		rotation.y = lerp_angle(rotation.y, sync_yaw, weight)
		_visuals.set_look_pitch(sync_pitch)
	_head.position.y = move_toward(_head.position.y, body.get_eye_height(), EYE_HEIGHT_SPEED * delta)


func is_local() -> bool:
	return Net.is_joined() and peer_id == Net.local_id()


## Только для своего игрока: HUD выключает управление на время паузы.
func set_input_enabled(value: bool) -> void:
	if is_local():
		input.enabled = value


## Откуда игрок смотрит (и стреляет), в мировых координатах.
func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * body.get_eye_height()


## Куда игрок смотрит. На сервере и у хозяина — по вводу, у остальных — по снимку сервера.
func get_look_direction() -> Vector3:
	var is_input_fresh: bool = Net.is_server() or is_local()
	var yaw: float = input.yaw if is_input_fresh else sync_yaw
	var pitch: float = input.pitch if is_input_fresh else sync_pitch
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


## Только сервер: перенести игрока и погасить скорость. Если задан target_yaw, игрок
## ещё и поворачивается в эту сторону (хозяину аватара поворот уходит личным сообщением).
func teleport(target_position: Vector3, target_yaw: float = NAN) -> void:
	if not Net.is_server():
		return
	position = target_position
	velocity = Vector3.ZERO
	sync_position = position
	if is_finite(target_yaw):
		rotation.y = target_yaw
		sync_yaw = target_yaw
		input.yaw = target_yaw
		send_private(Private.LOOK, [target_yaw])


## Только сервер: игрок умер (CORPSE) или его убрали с карты (GONE). Назад дороги нет.
func server_set_life(new_life: Life) -> void:
	if not Net.is_server() or new_life <= life:
		return
	life = new_life
	velocity.x = 0.0
	velocity.z = 0.0
	Game.server_participant_out(peer_id)


## Сервер: отправить хозяину аватара личное сообщение.
func send_private(kind: Private, data: Array) -> void:
	if Net.is_server():
		private_sent.emit(kind, data)


## Сервер: разослать всем игрокам событие этого аватара.
func send_event(kind: Event, data: Array) -> void:
	if Net.is_server():
		event_sent.emit(kind, data)


## Клиент-владелец: личное сообщение с сервера. Вызывает World.
func receive_private(kind: int, data: Array) -> void:
	match kind:
		Private.VITALS:
			if data.size() == 2 and data[0] is int and data[1] is PackedInt32Array:
				body.apply_vitals(data[0] as int, data[1] as PackedInt32Array)
		Private.LOADOUT:
			weapons.apply_loadout(data)
		Private.LOOK:
			if data.size() == 1 and data[0] is float:
				input.yaw = PlayerInput.sanitize_yaw(data[0] as float)
				input.pitch = 0.0


## Клиенты: событие аватара с сервера. Вызывает World.
func receive_event(kind: int, data: Array) -> void:
	if Event.values().has(kind):
		event_received.emit(kind as Event, data)


## Клиент: пришёл новый снимок состояния.
func _on_state_synchronized() -> void:
	_interpolator.push(sync_position, sync_tick)


## Сервер: роли розданы — выдаём оружие по роли.
func _on_round_started() -> void:
	weapons.server_reset(Game.get_role(peer_id))


## Клиент: показать предмет в руках.
func _show_held_item() -> void:
	var item: ItemConfig = weapons.get_held_item()
	var model: PackedScene = item.model if item != null else null
	_visuals.set_held_item(model)
	if _viewmodel != null:
		_viewmodel.set_held_item(model)


## Клиент: показать, жив игрок, лежит телом или убран.
func _show_life() -> void:
	_visuals.visible = life != Life.GONE
	_visuals.set_dead(life == Life.CORPSE)
	# Своё живое тело в камере от первого лица не показываем; своё мёртвое — видим со стороны.
	_visuals.set_first_person(is_local() and life == Life.ALIVE)
	if _viewmodel != null:
		_viewmodel.visible = life == Life.ALIVE


## Клиент: атака своего игрока — отдача или взмах рук от первого лица.
## Анимацию тела и вспышки для всех показывает узел AttackEffects.
func _on_event_received(kind: Event, _data: Array) -> void:
	if kind == Event.ATTACK and _viewmodel != null:
		_viewmodel.play_attack()


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
