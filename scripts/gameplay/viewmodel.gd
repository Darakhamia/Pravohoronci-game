class_name Viewmodel
extends Node3D
## Вид от первого лица: варежка с предплечьем и предмет в правом нижнем углу экрана.
## Кладётся ребёнком в Camera3D своего игрока: начало координат — камера, взгляд по -Z.
##
## Пустые руки не показываются; кулак появляется только на время удара. Без правой руки
## предмет переезжает в левую, без обеих не видно ничего.
##
## Вся оснастка уменьшена и во столько же раз придвинута к камере (RIG_SCALE): на экране она
## выглядит так же, но не выходит за радиус капсулы игрока и поэтому не проходит сквозь стены.
## Размеры и смещения ниже заданы в «настоящих» метрах, до этого масштаба.
##
## Без окна (сервер, боты, тесты) ничего не анимируется.

const HEADLESS_DISPLAY: String = "headless"
const LEFT: float = -1.0
const RIGHT: float = 1.0
const SIDES: Array[float] = [LEFT, RIGHT]
const RIG_SCALE: float = 0.45
## Длинный кадр не должен «выстрелить» рукой.
const MAX_STEP_SEC: float = 0.1

# --- Положение руки в кадре (для правой; у левой X и повороты вокруг Y/Z зеркальны) ---
const HOLD_POSITION: Vector3 = Vector3(0.27, -0.25, -0.6)
const HOLD_ROTATION: Vector3 = Vector3(0.03, 0.12, -0.07)
## Оружие ближнего боя держат клинком вверх-внутрь, чтобы его было видно сбоку.
const MELEE_HOLD_POSITION: Vector3 = Vector3(0.3, -0.29, -0.56)
const MELEE_HOLD_ROTATION: Vector3 = Vector3(0.5, 0.5, -0.45)
## Убранная рука: ниже края экрана.
const LOWERED_OFFSET: Vector3 = Vector3(0.04, -0.34, 0.1)
const LOWERED_PITCH: float = -0.7
const RAISE_RATE: float = 9.0
const LOWER_RATE: float = 14.0
## Ниже этого веса рука не рисуется вовсе.
const HIDDEN_WEIGHT: float = 0.02

# --- Покачивание при ходьбе ---
const RUN_SPEED: float = 5.0
const MOVE_BLEND_RATE: float = 10.0
## Полных циклов шага в секунду — как у тела (PlayerVisuals), чтобы шаги совпадали.
const CADENCE_WALK: float = 1.25
const CADENCE_RUN: float = 2.15
const BOB_SIDE: float = 0.014
const BOB_DOWN: float = 0.016
const BOB_ROLL: float = 0.02
const BREATH_RATE: float = 1.7
const BREATH_RISE: float = 0.003
## Прыжок и падение: рука отстаёт от камеры.
const AIR_LAG: float = 0.006
const AIR_LAG_LIMIT: float = 0.04
const AIR_BLEND_RATE: float = 8.0

# --- Удары ---
const ATTACK_DURATION: Dictionary[int, float] = {
	PlayerVisuals.Attack.RECOIL: 0.3,
	PlayerVisuals.Attack.STAB: 0.38,
	PlayerVisuals.Attack.PUNCH: 0.42,
}
## Доля длительности, на которой удар достигает цели.
const ATTACK_PEAK: Dictionary[int, float] = {
	PlayerVisuals.Attack.RECOIL: 0.12,
	PlayerVisuals.Attack.STAB: 0.4,
	PlayerVisuals.Attack.PUNCH: 0.4,
}
## Замах занимает эту долю времени в начале удара и достигает пика на своей середине.
const WINDUP_SHARE: float = 0.34
const WINDUP_PEAK: float = 0.5
const RECOIL_OFFSET: Vector3 = Vector3(0.0, 0.012, 0.075)
const RECOIL_PITCH: float = 0.24
const STAB_OFFSET: Vector3 = Vector3(-0.12, 0.05, -0.28)
const STAB_WINDUP_OFFSET: Vector3 = Vector3(0.03, 0.0, 0.09)
const STAB_YAW: float = 0.12
## В выпаде клинок опускается к горизонту и смотрит в цель.
const STAB_PITCH: float = -0.42
const PUNCH_OFFSET: Vector3 = Vector3(-0.15, 0.1, -0.2)
const PUNCH_WINDUP_OFFSET: Vector3 = Vector3(0.02, -0.03, 0.1)
const PUNCH_YAW: float = 0.25

var _is_set_up: bool = false
var _headless: bool = false
var _rig: Node3D = null
## Узел руки (он же ладонь: предмет кладётся в него ребёнком) по стороне.
var _arms: Dictionary[float, MeshInstance3D] = {}
var _suit_material: StandardMaterial3D = null

var _velocity: Vector3 = Vector3.ZERO
var _limbs_lost: int = 0
var _held_scene: PackedScene = null
var _held_node: Node3D = null
var _held_side: float = 0.0
var _held_melee: bool = false

var _time: float = 0.0
var _phase: float = 0.0
var _move: float = 0.0
var _air_lag: float = 0.0
## Насколько рука поднята в кадр: 0 — убрана, 1 — на месте.
var _raise: Dictionary[float, float] = {LEFT: 0.0, RIGHT: 0.0}
var _attack: PlayerVisuals.Attack = PlayerVisuals.Attack.NONE
var _attack_time: float = 0.0
var _attack_side: float = RIGHT


func _ready() -> void:
	_set_up()
	set_process(not _headless)
	_pose_arms()


func _process(delta: float) -> void:
	var step: float = minf(delta, MAX_STEP_SEC)
	_advance_state(step)
	_pose_arms()


## Предмет в руке (null — пустые руки). Сцена предмета: начало координат в точке хвата,
## ствол/клинок по -Z.
func set_held_item(model: PackedScene) -> void:
	_set_up()
	if model == _held_scene:
		return
	_held_scene = model
	_drop_held_node()
	_refresh_held_item()


func set_body_color(color: Color) -> void:
	_set_up()
	_suit_material.albedo_color = color


## Маска потерянных конечностей (биты BodyPart.bit): потерянная рука не показывается.
func set_limbs_lost(mask: int) -> void:
	_set_up()
	_limbs_lost = mask
	for side: float in SIDES:
		if _is_arm_lost(side):
			_raise[side] = 0.0
	_refresh_held_item()
	_pose_arms()


## Скорость игрока в мире, м/с: из неё получается покачивание руки при ходьбе.
func set_velocity(velocity: Vector3) -> void:
	_velocity = velocity if velocity.is_finite() else Vector3.ZERO


## Разовый удар: отдача (или выпад для ближнего боя) с предметом, тычок кулаком без него.
func play_attack() -> void:
	_set_up()
	var side: float = _free_side()
	if side == 0.0:
		return
	if _held_node == null:
		_attack = PlayerVisuals.Attack.PUNCH
	else:
		_attack = PlayerVisuals.Attack.STAB if _held_melee else PlayerVisuals.Attack.RECOIL
	_attack_side = side
	_attack_time = 0.0


## Вызывается из _ready и из каждого публичного метода: методы работают и до входа в дерево.
func _set_up() -> void:
	if _is_set_up:
		return
	_is_set_up = true
	_headless = DisplayServer.get_name() == HEADLESS_DISPLAY
	_rig = $Rig
	_rig.scale = Vector3.ONE * RIG_SCALE
	_arms[RIGHT] = $Rig/Arms/ArmRight as MeshInstance3D
	_arms[LEFT] = $Rig/Arms/ArmLeft as MeshInstance3D
	_suit_material = PlayerVisuals.make_suit_material(_rig)
	for side: float in SIDES:
		PlayerVisuals.apply_suit_material(_arms[side], _suit_material)
		_arms[side].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arms[side].visible = false


func _is_arm_lost(side: float) -> bool:
	return BodyPart.is_lost(_limbs_lost, BodyPart.Part.LEFT_ARM if side < 0.0 else BodyPart.Part.RIGHT_ARM)


## Сторона руки, которая держит предмет и бьёт: правая, без неё левая, без обеих — 0.
func _free_side() -> float:
	for side: float in [RIGHT, LEFT]:
		if not _is_arm_lost(side):
			return side
	return 0.0


func _drop_held_node() -> void:
	if _held_node != null:
		_held_node.get_parent().remove_child(_held_node)
		_held_node.queue_free()
	_held_node = null
	_held_side = 0.0
	_held_melee = false


## Кладёт предмет в подходящую руку: после смены предмета или потери/возврата руки.
func _refresh_held_item() -> void:
	var side: float = _free_side() if _held_scene != null else 0.0
	if side == _held_side:
		return
	if side == 0.0:
		_drop_held_node()
		return
	if _held_node == null:
		_held_node = _held_scene.instantiate() as Node3D
		if _held_node == null:
			push_warning("Viewmodel: корень сцены предмета должен быть Node3D")
			return
		_held_melee = PlayerVisuals.is_melee_item(_held_node)
		_disable_shadows(_held_node)
	else:
		_held_node.get_parent().remove_child(_held_node)
	_arms[side].add_child(_held_node)
	_held_side = side
	# Новый предмет «достаётся» снизу.
	_raise[side] = 0.0


## Тень от уменьшенной руки у самой камеры на мир падать не должна.
func _disable_shadows(node: Node) -> void:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry != null:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_shadows(child)


## 0 -> 1 к моменту peak -> 0 к концу, без изломов.
static func _pulse(progress: float, peak: float) -> float:
	if progress < peak:
		return smoothstep(0.0, peak, progress)
	return 1.0 - smoothstep(peak, 1.0, progress)


func _advance_state(delta: float) -> void:
	_time += delta
	var speed: float = Vector2(_velocity.x, _velocity.z).length()
	_move = lerpf(_move, clampf(speed / RUN_SPEED, 0.0, 1.0), 1.0 - exp(-MOVE_BLEND_RATE * delta))
	_phase = wrapf(_phase + TAU * lerpf(CADENCE_WALK, CADENCE_RUN, _move) * delta, 0.0, TAU)
	var lag: float = clampf(-_velocity.y * AIR_LAG, -AIR_LAG_LIMIT, AIR_LAG_LIMIT)
	_air_lag = lerpf(_air_lag, lag, 1.0 - exp(-AIR_BLEND_RATE * delta))
	if _attack != PlayerVisuals.Attack.NONE:
		_attack_time += delta
		if _attack_time >= ATTACK_DURATION[_attack]:
			_attack = PlayerVisuals.Attack.NONE
	for side: float in SIDES:
		var wanted: bool = _held_node != null and _held_side == side
		var rate: float = RAISE_RATE if wanted else LOWER_RATE
		_raise[side] = lerpf(_raise[side], 1.0 if wanted else 0.0, 1.0 - exp(-rate * delta))


func _pose_arms() -> void:
	var bob: Vector3 = Vector3(sin(_phase) * BOB_SIDE, -absf(cos(_phase)) * BOB_DOWN, 0.0) * _move
	bob.y += sin(_time * BREATH_RATE) * BREATH_RISE + _air_lag
	var roll: float = sin(_phase) * BOB_ROLL * _move
	for side: float in SIDES:
		var arm: MeshInstance3D = _arms[side]
		var shown: float = _raise[side]
		var offset: Vector3 = bob
		var turn: Vector3 = Vector3(0.0, 0.0, roll)
		if _attack != PlayerVisuals.Attack.NONE and _attack_side == side:
			var progress: float = _attack_time / ATTACK_DURATION[_attack]
			var hit: float = _pulse(progress, ATTACK_PEAK[_attack])
			var windup: float = _pulse(minf(progress / WINDUP_SHARE, 1.0), WINDUP_PEAK)
			match _attack:
				PlayerVisuals.Attack.RECOIL:
					offset += RECOIL_OFFSET * hit
					turn.x += RECOIL_PITCH * hit
				PlayerVisuals.Attack.STAB:
					offset += _mirror(STAB_OFFSET, side) * hit + _mirror(STAB_WINDUP_OFFSET, side) * windup
					turn.y += side * STAB_YAW * hit
					turn.x += STAB_PITCH * hit
				PlayerVisuals.Attack.PUNCH:
					offset += _mirror(PUNCH_OFFSET, side) * hit + _mirror(PUNCH_WINDUP_OFFSET, side) * windup
					turn.y += side * PUNCH_YAW * hit
					# Пустая рука убрана: на время удара кулак выныривает в кадр.
					shown = maxf(shown, maxf(hit, windup))
		arm.visible = shown > HIDDEN_WEIGHT and not _is_arm_lost(side)
		if not arm.visible:
			continue
		var lowered: float = 1.0 - shown
		var melee: bool = _held_melee and _held_side == side
		var hold_position: Vector3 = MELEE_HOLD_POSITION if melee else HOLD_POSITION
		var hold_rotation: Vector3 = MELEE_HOLD_ROTATION if melee else HOLD_ROTATION
		arm.position = _mirror(hold_position + LOWERED_OFFSET * lowered, side) + offset
		arm.rotation = Vector3(hold_rotation.x + LOWERED_PITCH * lowered, side * hold_rotation.y, side * hold_rotation.z) + turn


## Смещение, заданное для правой руки, — для руки с этой стороны.
func _mirror(value: Vector3, side: float) -> Vector3:
	return Vector3(value.x * side, value.y, value.z)
