class_name Viewmodel
extends Node3D
## Вид от первого лица: руки скафандра и предмет в руке.
## Кладётся ребёнком в Camera3D своего игрока: начало координат — камера, взгляд по -Z.
##
## Каждая рука — три жёстких звена из crewmate_arm.glb: кисть (узел ArmRight/ArmLeft, в него же
## кладётся предмет), предплечье и плечо. Скрипт ставит кисть в позу её роли, а локоть находит
## обратной кинематикой от плеча за кадром: предплечье входит из нижнего угла экрана, при ударе
## рука сгибается и распрямляется в локте.
##
## Пистолет держат двумя руками: оружие справа-внизу, вторая кисть обнимает первую под рукоятью.
## Нож — одной, вторая рука остаётся кулаком у нижнего края кадра. С пустыми руками видны оба
## кулака. Без правой руки предмет переезжает в левую, без обеих не видно ничего.
##
## Вся оснастка уменьшена и во столько же раз придвинута к камере (RIG_SCALE): на экране она
## выглядит так же, но не выходит за радиус капсулы игрока и поэтому не проходит сквозь стены.
## Размеры и смещения ниже заданы в «настоящих» метрах, до этого масштаба.
##
## Руки сняты «своим объективом» (VIEW_FOV_DEG), более узким, чем у камеры игрока: оснастка
## растягивается поперёк взгляда ровно настолько, чтобы на экране выглядеть так, как выглядела
## бы в камере с этим углом (то же самое, что сплющить её вдоль взгляда). Так рукава у самой
## камеры не раздуваются на полкадра, а вид рук не зависит от угла обзора в настройках.
## Позы ниже заданы для этого объектива.
##
## Меши рук и предмета лежат на слое отрисовки VIEW_RENDER_LAYER и не отбрасывают теней: зонды
## отражений и чужие камеры могут исключить этот слой своей маской.
##
## Без окна (сервер, боты, тесты) ничего не анимируется.

## Что делает рука.
enum Role { GONE, IDLE, HOLD, SUPPORT, MELEE, GUARD }

const HEADLESS_DISPLAY: String = "headless"
const LEFT: float = -1.0
const RIGHT: float = 1.0
const SIDES: Array[float] = [LEFT, RIGHT]
const RIG_SCALE: float = 0.38
## Угол обзора (по вертикали), под который поставлены руки.
const VIEW_FOV_DEG: float = 54.0
## Слой отрисовки рук от первого лица (20-й): его видит камера игрока, остальным он не нужен.
const VIEW_RENDER_LAYER: int = 1 << 19
## Длинный кадр не должен «выстрелить» рукой.
const MAX_STEP_SEC: float = 0.1
const EPSILON: float = 0.0001

# --- Звенья руки (в осях узла кисти: -Z — вдоль пальцев, +Y — к большому пальцу) ---
## Центр запястья относительно точки хвата.
const WRIST_OFFSET: Vector3 = Vector3(0.0, 0.0, 0.067)
const FOREARM_LENGTH: float = 0.223
const UPPER_LENGTH: float = 0.3
## Плечо за кадром (для правой руки) и направление, куда смотрит локоть: вниз и наружу.
const SHOULDER: Vector3 = Vector3(0.47, -0.26, -0.14)
## Вторая рука на пистолете приходит снизу: в кадре остаются только кисть и запястье.
const SUPPORT_SHOULDER: Vector3 = Vector3(-0.06, -0.62, -0.38)
const ELBOW_POLE: Vector3 = Vector3(1.0, -0.35, 0.1)
## Рука не выпрямляется до щелчка: так локоть не «прыгает».
const REACH_LIMIT: float = 0.985

# --- Поза кисти по ролям (для правой руки; левая зеркальна): положение точки хвата в осях камеры
# и углы Эйлера. Предплечье и плечо дорисовывает обратная кинематика. ---
const POSE_POSITION: Dictionary[int, Vector3] = {
	Role.GONE: Vector3(0.36, -0.7, -0.4),
	Role.IDLE: Vector3(0.235, -0.205, -0.56),
	## Пистолет: справа-внизу, ствол смотрит в центр экрана.
	Role.HOLD: Vector3(0.125, -0.16, -0.52),
	Role.MELEE: Vector3(0.2, -0.15, -0.5),
	## Свободная рука при ноже: кулак у нижнего края кадра.
	Role.GUARD: Vector3(0.25, -0.25, -0.52),
}
const POSE_ROTATION: Dictionary[int, Vector3] = {
	Role.GONE: Vector3(-0.4, 0.2, 0.0),
	Role.IDLE: Vector3(0.75, 0.5, 0.35),
	Role.HOLD: Vector3(0.03, 0.05, 0.05),
	Role.MELEE: Vector3(0.2, 0.5, 0.55),
	Role.GUARD: Vector3(0.8, 0.55, 0.3),
}
## Вторая рука на пистолете — относительно кисти с оружием (в её осях): ладонь ложится на
## рукоять слева, пальцы обнимают пальцы первой руки, запястье уходит вниз.
const SUPPORT_OFFSET: Vector3 = Vector3(-0.008, -0.022, -0.012)
const SUPPORT_ROTATION: Vector3 = Vector3(0.5, -0.3, -0.2)
## Поворот кисти вокруг её собственной оси «к большому пальцу» (вдоль рукояти): нож повёрнут
## плоскостью клинка к игроку.
const POSE_TWIST: Dictionary[int, float] = {
	Role.MELEE: 0.6,
}
## Как быстро рука переходит из позы в позу, 1/с.
const POSE_RATE: float = 10.0
## Новый предмет «достаётся» снизу: рука на миг ныряет под кадр.
const DRAW_DIP: Vector3 = Vector3(0.03, -0.3, 0.08)
const DRAW_RATE: float = 7.0
## Оружие ближнего боя лежит в кулаке «молотком» (как у PlayerVisuals), в стойке клинок чуть
## наклонён вперёд, от себя.
const MELEE_GRIP_ROTATION: Vector3 = Vector3(PI * 0.5, 0.0, 0.0)
const MELEE_READY_PITCH: float = 1.2
## Формы кисти (см. PlayerVisuals.HAND_GRIP_SHAPE) и насколько сжат пустой кулак.
const HAND_SHAPE_RATE: float = 16.0
const IDLE_FIST: float = 0.9

# --- Покачивание при ходьбе ---
const RUN_SPEED: float = 5.0
const MOVE_BLEND_RATE: float = 10.0
## Полных циклов шага в секунду — как у тела (PlayerVisuals), чтобы шаги совпадали.
const CADENCE_WALK: float = 1.1
const CADENCE_RUN: float = 1.55
const BOB_SIDE: float = 0.01
const BOB_DOWN: float = 0.013
const BOB_ROLL: float = 0.02
## Пустые руки на бегу машут сильнее и в противофазе.
const IDLE_SWING: float = 0.05
const BREATH_RATE: float = 1.5
const BREATH_RISE: float = 0.003
## Прыжок и падение: рука отстаёт от камеры.
const AIR_LAG: float = 0.006
const AIR_LAG_LIMIT: float = 0.04
const AIR_BLEND_RATE: float = 8.0

# --- Удары ---
const ATTACK_DURATION: Dictionary[int, float] = {
	PlayerVisuals.Attack.RECOIL: 0.3,
	PlayerVisuals.Attack.STAB: 0.42,
	PlayerVisuals.Attack.PUNCH: 0.42,
}
## Доля длительности, на которой удар достигает цели.
const ATTACK_PEAK: Dictionary[int, float] = {
	PlayerVisuals.Attack.RECOIL: 0.12,
	PlayerVisuals.Attack.STAB: 0.42,
	PlayerVisuals.Attack.PUNCH: 0.4,
}
## Замах занимает эту долю времени в начале удара и достигает пика на своей середине.
const WINDUP_SHARE: float = 0.36
const WINDUP_PEAK: float = 0.5
const RECOIL_OFFSET: Vector3 = Vector3(0.0, 0.016, 0.06)
const RECOIL_PITCH: float = 0.2
## Выпад ножом: кисть идёт к центру кадра, клинок ложится вдоль предплечья и смотрит в цель.
const STAB_POSITION: Vector3 = Vector3(0.05, -0.08, -0.78)
const STAB_ROTATION: Vector3 = Vector3(0.1, 0.2, 0.9)
const STAB_WINDUP_OFFSET: Vector3 = Vector3(0.06, -0.05, 0.14)
const STAB_BLADE_PITCH: float = 0.4
## Удар кулаком: костяшки вперёд, тыльная сторона кисти вверх, рука распрямляется в локте.
const PUNCH_POSITION: Vector3 = Vector3(0.04, -0.1, -0.82)
const PUNCH_ROTATION: Vector3 = Vector3(0.12, 0.16, 1.3)
const PUNCH_WINDUP_OFFSET: Vector3 = Vector3(0.05, -0.03, 0.16)

var _is_set_up: bool = false
var _headless: bool = false
var _rig: Node3D = null
## Узел кисти (он же ладонь: предмет кладётся в него ребёнком), предплечье и плечо по стороне.
var _arms: Dictionary[float, MeshInstance3D] = {}
var _forearms: Dictionary[float, MeshInstance3D] = {}
var _uppers: Dictionary[float, MeshInstance3D] = {}
var _suit_material: StandardMaterial3D = null
var _grip_shape_index: Dictionary[float, int] = {}
var _trigger_shape_index: Dictionary[float, int] = {}

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
## Текущая поза каждой кисти в осях камеры (без покачивания и ударов): плавно идёт к позе роли.
var _base: Dictionary[float, Transform3D] = {}
## Насколько рука сейчас «нырнула» за новым предметом: 1 — внизу, 0 — на месте.
var _draw: Dictionary[float, float] = {LEFT: 0.0, RIGHT: 0.0}
var _grip_shape: Dictionary[float, float] = {LEFT: 0.0, RIGHT: 0.0}
var _trigger_shape: Dictionary[float, float] = {LEFT: 0.0, RIGHT: 0.0}
var _attack: PlayerVisuals.Attack = PlayerVisuals.Attack.NONE
var _attack_time: float = 0.0
var _attack_side: float = RIGHT


func _ready() -> void:
	_set_up()
	set_process(not _headless)
	_snap_to_roles()
	_pose_arms()


func _process(delta: float) -> void:
	var step: float = minf(delta, MAX_STEP_SEC)
	_fit_lens()
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


## Перекрашивает рукава в цвет игрока (та же краска, что у тела: PlayerVisuals.suit_paint_color).
func set_body_color(color: Color) -> void:
	_set_up()
	_suit_material.albedo_color = PlayerVisuals.suit_paint_color(color)


## Маска потерянных конечностей (биты BodyPart.bit): потерянная рука не показывается.
func set_limbs_lost(mask: int) -> void:
	_set_up()
	_limbs_lost = mask
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
	_forearms[RIGHT] = $Rig/Arms/ForearmRight as MeshInstance3D
	_forearms[LEFT] = $Rig/Arms/ForearmLeft as MeshInstance3D
	_uppers[RIGHT] = $Rig/Arms/UpperRight as MeshInstance3D
	_uppers[LEFT] = $Rig/Arms/UpperLeft as MeshInstance3D
	_suit_material = PlayerVisuals.make_suit_material(_rig)
	for side: float in SIDES:
		for link: MeshInstance3D in _links(side):
			PlayerVisuals.apply_suit_material(link, _suit_material)
			_set_view_rendering(link)
		_grip_shape_index[side] = _arms[side].find_blend_shape_by_name(PlayerVisuals.HAND_GRIP_SHAPE)
		_trigger_shape_index[side] = _arms[side].find_blend_shape_by_name(PlayerVisuals.HAND_TRIGGER_SHAPE)
		_base[side] = _mirror(_role_pose(Role.GONE), side)


## Растягивает оснастку поперёк взгляда под угол обзора камеры (см. VIEW_FOV_DEG).
func _fit_lens() -> void:
	var camera: Camera3D = get_parent() as Camera3D
	var stretch: float = 1.0
	if camera != null and camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		stretch = maxf(tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(VIEW_FOV_DEG) * 0.5), 1.0)
	_rig.scale = Vector3(stretch, stretch, 1.0) * RIG_SCALE


func _links(side: float) -> Array[MeshInstance3D]:
	return [_arms[side], _forearms[side], _uppers[side]]


func _is_arm_lost(side: float) -> bool:
	return BodyPart.is_lost(_limbs_lost, BodyPart.Part.LEFT_ARM if side < 0.0 else BodyPart.Part.RIGHT_ARM)


## Сторона руки, которая держит предмет и бьёт: правая, без неё левая, без обеих — 0.
func _free_side() -> float:
	for side: float in [RIGHT, LEFT]:
		if not _is_arm_lost(side):
			return side
	return 0.0


## Что сейчас делает рука side.
func _role(side: float) -> Role:
	if _is_arm_lost(side):
		return Role.GONE
	if _held_node == null:
		return Role.IDLE
	if _held_side == side:
		return Role.MELEE if _held_melee else Role.HOLD
	return Role.GUARD if _held_melee else Role.SUPPORT


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
		if _held_melee:
			_held_node.rotation = MELEE_GRIP_ROTATION
		_set_view_rendering(_held_node)
	else:
		_held_node.get_parent().remove_child(_held_node)
	_arms[side].add_child(_held_node)
	_held_side = side
	# Новый предмет «достаётся» снизу.
	_draw[side] = 1.0


## Руки и предмет у самой камеры: без теней на мир, вне освещения сцены от подвижных тел,
## на своём слое отрисовки.
func _set_view_rendering(node: Node) -> void:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry != null:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geometry.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		geometry.layers = VIEW_RENDER_LAYER
	for child: Node in node.get_children():
		_set_view_rendering(child)


## 0 -> 1 к моменту peak -> 0 к концу, без изломов.
static func _pulse(progress: float, peak: float) -> float:
	if progress < peak:
		return smoothstep(0.0, peak, progress)
	return 1.0 - smoothstep(peak, 1.0, progress)


static func _pose(position_in_view: Vector3, euler: Vector3, twist: float = 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(euler) * Basis(Vector3.UP, twist), position_in_view)


## Поза кисти правой руки для роли (без SUPPORT: та считается от кисти с оружием).
func _role_pose(role: Role) -> Transform3D:
	return _pose(POSE_POSITION[role], POSE_ROTATION[role], POSE_TWIST.get(role, 0.0))


## Поза, заданная для правой руки, — для руки с этой стороны (отражение относительно плоскости X = 0).
static func _mirror(pose: Transform3D, side: float) -> Transform3D:
	if side > 0.0:
		return pose
	var flip: Basis = Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	return Transform3D(flip * pose.basis * flip, Vector3(-pose.origin.x, pose.origin.y, pose.origin.z))


## Куда стремится кисть side: поза её роли.
func _target(side: float) -> Transform3D:
	var role: Role = _role(side)
	if role == Role.SUPPORT:
		return _mirror(_role_pose(Role.HOLD), -side) * _mirror(_pose(SUPPORT_OFFSET, SUPPORT_ROTATION), -side)
	return _mirror(_role_pose(role), side)


## Ставит кисти сразу в позы ролей, без плавного перехода (первый кадр).
func _snap_to_roles() -> void:
	for side: float in SIDES:
		_base[side] = _target(side)


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
	var blend: float = 1.0 - exp(-POSE_RATE * delta)
	var shape_blend: float = 1.0 - exp(-HAND_SHAPE_RATE * delta)
	for side: float in SIDES:
		if _is_arm_lost(side):
			# Потерянная рука ждёт внизу: вернётся — поднимется оттуда.
			_base[side] = _mirror(_role_pose(Role.GONE), side)
		else:
			_base[side] = _base[side].interpolate_with(_target(side), blend)
		_draw[side] = lerpf(_draw[side], 0.0, 1.0 - exp(-DRAW_RATE * delta))
		var role: Role = _role(side)
		var trigger: float = 1.0 if role == Role.HOLD else 0.0
		var grip: float = 0.0
		if role == Role.MELEE or role == Role.SUPPORT:
			grip = 1.0
		elif role == Role.IDLE or role == Role.GUARD:
			grip = 1.0 if _attack == PlayerVisuals.Attack.PUNCH and _attack_side == side else IDLE_FIST
		_grip_shape[side] = lerpf(_grip_shape[side], grip, shape_blend)
		_trigger_shape[side] = lerpf(_trigger_shape[side], trigger, shape_blend)


func _pose_arms() -> void:
	var bob: Vector3 = Vector3(sin(_phase) * BOB_SIDE, -absf(cos(_phase)) * BOB_DOWN, 0.0) * _move
	bob.y += sin(_time * BREATH_RATE) * BREATH_RISE + _air_lag
	var roll: float = sin(_phase) * BOB_ROLL * _move
	var hit: float = 0.0
	var windup: float = 0.0
	if _attack != PlayerVisuals.Attack.NONE:
		var progress: float = _attack_time / ATTACK_DURATION[_attack]
		hit = _pulse(progress, ATTACK_PEAK[_attack])
		windup = _pulse(minf(progress / WINDUP_SHARE, 1.0), WINDUP_PEAK) * (1.0 - hit)
	for side: float in SIDES:
		var visible_now: bool = not _is_arm_lost(side)
		for link: MeshInstance3D in _links(side):
			link.visible = visible_now
		if not visible_now:
			continue
		var role: Role = _role(side)
		var hand: Transform3D = _base[side]
		var offset: Vector3 = bob + DRAW_DIP * _draw[side]
		if role == Role.IDLE:
			# Пустые кулаки на бегу ходят вперёд-назад, как руки бегуна.
			offset += Vector3(0.0, 0.0, side * sin(_phase) * IDLE_SWING * _move)
		if side == _attack_side:
			match _attack:
				PlayerVisuals.Attack.STAB:
					hand = hand.interpolate_with(_mirror(_pose(STAB_POSITION, STAB_ROTATION), side), hit)
					offset += _mirror_offset(STAB_WINDUP_OFFSET, side) * windup
				PlayerVisuals.Attack.PUNCH:
					hand = hand.interpolate_with(_mirror(_pose(PUNCH_POSITION, PUNCH_ROTATION), side), hit)
					offset += _mirror_offset(PUNCH_WINDUP_OFFSET, side) * windup
		if _attack == PlayerVisuals.Attack.RECOIL and (role == Role.HOLD or role == Role.SUPPORT):
			# Обе руки на пистолете подбрасывает вместе: вторая повторяет движение первой.
			var holder: Transform3D = _base[_held_side]
			var kick: Transform3D = Transform3D(Basis(holder.basis.x.normalized(), RECOIL_PITCH * hit), RECOIL_OFFSET * hit)
			hand = Transform3D(Basis.IDENTITY, holder.origin) * kick * Transform3D(Basis.IDENTITY, -holder.origin) * hand
		hand.origin += offset
		hand.basis = Basis(Vector3.BACK, side * roll) * hand.basis
		_place_arm(side, hand)
		if _grip_shape_index[side] != -1:
			_arms[side].set_blend_shape_value(_grip_shape_index[side], _grip_shape[side])
		if _trigger_shape_index[side] != -1:
			_arms[side].set_blend_shape_value(_trigger_shape_index[side], _trigger_shape[side])
	if _held_node != null and _held_melee:
		var thrust: float = hit if _attack == PlayerVisuals.Attack.STAB else 0.0
		_held_node.rotation.x = lerpf(MELEE_READY_PITCH, STAB_BLADE_PITCH, thrust)


## Смещение, заданное для правой руки, — для руки с этой стороны.
func _mirror_offset(value: Vector3, side: float) -> Vector3:
	return Vector3(value.x * side, value.y, value.z)


## Ставит кисть в позу hand (оси камеры), а предплечье и плечо — обратной кинематикой двух
## звеньев от плеча за кадром до запястья. Если рука не дотягивается, плечо подаётся за ней.
func _place_arm(side: float, hand: Transform3D) -> void:
	_arms[side].transform = hand
	var wrist: Vector3 = hand * WRIST_OFFSET
	var shoulder: Vector3 = _mirror_offset(SUPPORT_SHOULDER if _role(side) == Role.SUPPORT else SHOULDER, side)
	var to_shoulder: Vector3 = shoulder - wrist
	var reach: float = to_shoulder.length()
	var direction: Vector3 = to_shoulder / reach if reach > EPSILON else Vector3.BACK
	var limit: float = (FOREARM_LENGTH + UPPER_LENGTH) * REACH_LIMIT
	reach = clampf(reach, absf(UPPER_LENGTH - FOREARM_LENGTH) + EPSILON, limit)
	shoulder = wrist + direction * reach
	# Локоть лежит на окружности вокруг линии «запястье — плечо»: берём точку ниже и снаружи.
	var along: float = (FOREARM_LENGTH * FOREARM_LENGTH - UPPER_LENGTH * UPPER_LENGTH + reach * reach) / (2.0 * reach)
	var away: float = sqrt(maxf(FOREARM_LENGTH * FOREARM_LENGTH - along * along, 0.0))
	var pole: Vector3 = _mirror_offset(ELBOW_POLE, side)
	var sideways: Vector3 = pole - direction * pole.dot(direction)
	sideways = sideways.normalized() if sideways.length() > EPSILON else Vector3.DOWN
	var elbow: Vector3 = wrist + direction * along + sideways * away
	var forearm_basis: Basis = _link_basis(elbow - wrist, hand.basis.y, hand.basis.x)
	_forearms[side].transform = Transform3D(forearm_basis, wrist)
	_uppers[side].transform = Transform3D(_link_basis(shoulder - elbow, forearm_basis.y, forearm_basis.x), elbow)


## Оси звена: +Z — вдоль звена (к следующему суставу), +Y — как можно ближе к up.
static func _link_basis(along: Vector3, up: Vector3, fallback: Vector3) -> Basis:
	var z_axis: Vector3 = along.normalized() if along.length() > EPSILON else Vector3.BACK
	var y_axis: Vector3 = up - z_axis * up.dot(z_axis)
	if y_axis.length() < 0.05:
		y_axis = fallback - z_axis * fallback.dot(z_axis)
	y_axis = y_axis.normalized()
	return Basis(y_axis.cross(z_axis), y_axis, z_axis)
