class_name GhostCamera
extends Camera3D
## Призрак: свободная камера мёртвого игрока. Существует только на его клиенте — остальные
## призрака не видят, и на игру он не влияет. Летает сквозь стены в пределах карты.
## Взгляд берёт из PlayerInput своего аватара: мышь продолжает работать и после смерти.

## Скорость полёта, м/с.
const FLY_SPEED: float = 7.0

var _input: PlayerInput = null
var _bounds: AABB = AABB()


## Вызывает карта сразу после создания призрака.
func setup(input: PlayerInput, start_position: Vector3, bounds: AABB) -> void:
	_input = input
	_bounds = bounds
	position = start_position
	fov = Settings.fov
	make_current()


func _process(delta: float) -> void:
	if not is_instance_valid(_input):
		return
	rotation = Vector3(_input.pitch, _input.yaw, 0.0)
	if not _input.enabled:
		return
	var move: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	# Летим туда, куда смотрим; прыжок поднимает вверх.
	var direction: Vector3 = basis * Vector3(move.x, 0.0, move.y)
	if Input.is_action_pressed(&"jump"):
		direction += Vector3.UP
	position += direction.limit_length(1.0) * FLY_SPEED * delta
	position = position.clamp(_bounds.position, _bounds.end)
