class_name PlayerInteractor
extends Node
## Взаимодействие игрока с предметами карты (клавиша E). Узел Interactor внутри Player.
## Клиент-владелец: ищет предмет под прицелом, ведёт полоску удержания и сообщает о
## нажатии сигналом press_requested — World передаёт его серверу.
## Сервер: проверяет дальность и видимость, отсчитывает удержание и вызывает предмет.

## Клиент-владелец: под прицелом другой предмет. null — ничего.
signal focus_changed(target: Interactable)
## Клиент-владелец: изменилась полоска удержания, 0..1.
signal hold_changed(fraction: float)
## Клиент-владелец: нажали (true) или отпустили (false) E на предмете.
signal press_requested(interact_id: int, pressed: bool)

## Насколько можно смотреть мимо точки предмета.
const MAX_FOCUS_ANGLE: float = deg_to_rad(30.0)
## Вблизи угол шире: точка предмета считается кругом такого радиуса.
const FOCUS_RADIUS: float = 0.6
## Сервер: запас по дальности на задержку сети.
const RANGE_TOLERANCE: float = 0.5
## Препятствие считается, только если оно заметно ближе самой точки предмета.
const SIGHT_MARGIN: float = 0.25
## Слой world: стены и пол закрывают предмет, игроки — нет.
const SIGHT_MASK: int = 1
## Сервер: больше запросов за один тик от клиента не принимаем.
const MAX_QUEUED_REQUESTS: int = 8
## Сервер: отпустил на столько секунд раньше конца — всё равно засчитываем. Сервер начинает
## отсчёт позже клиента на время пути пакета, а игрок отпускает клавишу по своей полоске.
const HOLD_GRACE_SEC: float = 0.2

## Клиент-владелец: предмет под прицелом.
var focus: Interactable = null
## Клиент-владелец: полоска удержания, 0..1.
var hold_fraction: float = 0.0

## Клиент-владелец: предмет, на котором сейчас зажата E.
var _pressed_target: Interactable = null
var _press_seconds: float = 0.0
var _is_key_down: bool = false

## Сервер: запросы клиента, ждут ближайшего физического тика: [interact_id, pressed].
var _requests: Array[Array] = []
## Сервер: предмет, который игрок сейчас удерживает.
var _held_target: Interactable = null
var _held_seconds: float = 0.0

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	set_physics_process(false)


## Вызывает Player: на сервере — у каждого аватара, на клиенте — только у своего.
func activate() -> void:
	set_physics_process(true)
	if not Net.is_server():
		_player.input.interact_changed.connect(_on_interact_changed)


func _physics_process(delta: float) -> void:
	if Net.is_server():
		_server_step(delta)
	else:
		_client_step(delta)


# --- Клиент-владелец ---


func _client_step(delta: float) -> void:
	_set_focus(_find_focus())
	if _pressed_target == null:
		return
	if focus != _pressed_target or not _is_key_down:
		_stop_press()
		return
	_press_seconds += delta
	_set_hold_fraction(_press_seconds / _pressed_target.hold_seconds)


func _on_interact_changed(pressed: bool) -> void:
	_is_key_down = pressed
	if not pressed:
		_stop_press()
		return
	if focus == null:
		return
	press_requested.emit(focus.interact_id, true)
	# Мгновенному предмету удержание не нужно: сервер уже всё сделал по нажатию.
	if focus.hold_seconds > 0.0:
		_pressed_target = focus
		_press_seconds = 0.0


func _stop_press() -> void:
	if _pressed_target == null:
		return
	press_requested.emit(_pressed_target.interact_id, false)
	_pressed_target = null
	_set_hold_fraction(0.0)


func _find_focus() -> Interactable:
	if _player.map == null or not _can_act():
		return null
	var eye: Vector3 = _player.get_eye_position()
	var look: Vector3 = _player.get_look_direction()
	var best: Interactable = null
	var best_angle: float = INF
	for candidate: Interactable in _player.map.get_focus_candidates():
		if not candidate.can_interact(_player):
			continue
		var to_target: Vector3 = candidate.get_focus_position() - eye
		var distance: float = to_target.length()
		if distance > candidate.interact_range:
			continue
		var angle: float = look.angle_to(to_target) if distance > 0.0 else 0.0
		if angle > maxf(MAX_FOCUS_ANGLE, atan2(FOCUS_RADIUS, distance)) or angle >= best_angle:
			continue
		if not _has_line_of_sight(eye, candidate.get_focus_position()):
			continue
		best = candidate
		best_angle = angle
	return best


func _set_focus(target: Interactable) -> void:
	if target == focus:
		return
	focus = target
	focus_changed.emit(focus)


func _set_hold_fraction(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, hold_fraction):
		return
	hold_fraction = clamped
	hold_changed.emit(hold_fraction)


# --- Сервер ---


## Сервер: клиент нажал или отпустил E на предмете. Проверка — в ближайшем физическом тике.
func server_request(interact_id: int, pressed: bool) -> void:
	if _requests.size() < MAX_QUEUED_REQUESTS:
		_requests.append([interact_id, pressed])


func _server_step(delta: float) -> void:
	for request: Array in _requests:
		var interact_id: int = request[0]
		var pressed: bool = request[1]
		_server_release()
		if pressed:
			_server_press(interact_id)
	_requests.clear()
	if _held_target == null:
		return
	# Отошёл, умер, началось собрание — удержание срывается.
	if not is_instance_valid(_held_target) or not _server_can_use(_held_target):
		_server_release()
		return
	_held_seconds += delta
	if _held_seconds >= _held_target.hold_seconds:
		var target: Interactable = _held_target
		_held_target = null
		target.server_interact(_player)


func _server_press(interact_id: int) -> void:
	var target: Interactable = _player.map.get_interactable(interact_id) if _player.map != null else null
	if target == null or not _server_can_use(target):
		return
	if target.hold_seconds <= 0.0:
		target.server_interact(_player)
		return
	_held_target = target
	_held_seconds = 0.0


func _server_release() -> void:
	if _held_target == null:
		return
	var target: Interactable = _held_target
	_held_target = null
	if not is_instance_valid(target):
		return
	if _held_seconds + HOLD_GRACE_SEC >= target.hold_seconds and _server_can_use(target):
		target.server_interact(_player)
	else:
		target.server_release(_player, _held_seconds)


func _server_can_use(target: Interactable) -> bool:
	if not _can_act() or not target.can_interact(_player):
		return false
	var eye: Vector3 = _player.get_eye_position()
	var point: Vector3 = target.get_focus_position()
	if eye.distance_to(point) > target.interact_range + RANGE_TOLERANCE:
		return false
	return _has_line_of_sight(eye, point)


# --- Общее ---


func _can_act() -> bool:
	return _player.life == Player.Life.ALIVE and Game.is_playing()


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, SIGHT_MASK)
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_position: Vector3 = hit["position"]
	return from.distance_to(hit_position) >= from.distance_to(to) - SIGHT_MARGIN
