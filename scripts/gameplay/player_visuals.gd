class_name PlayerVisuals
extends Node3D
## Внешний вид игрока: модель crewmate.glb, ник над головой и процедурная анимация.
##
## Геймплей сообщает состояние (скорость, взгляд, потерянные конечности, предмет в руке,
## смерть) — анимация сама собирает позу из этих входов каждый кадр, без AnimationPlayer.
## Модель генерирует tools/assets/character.py; сцену в player.tscn менять не нужно.
##
## Позы заданы углами Эйлера в осях МОДЕЛИ, а не кости: X — вправо, Y — вверх, -Z — вперёд.
## Для висящей вниз конечности «+X» — мах вперёд, «+Z» — отведение к правому боку (+X).
## Так позы не зависят от того, как кости повёрнуты в покое, и подойдут другой модели
## с теми же именами костей.
##
## Без окна (сервер, боты, тесты) ничего не анимируется и детали не разлетаются: остаются
## только скрытие потерянных конечностей и предмет в руке.

enum Bone {
	HIPS, SPINE, CHEST, NECK, HEAD,
	L_UPPER_ARM, L_LOWER_ARM, L_HAND,
	R_UPPER_ARM, R_LOWER_ARM, R_HAND,
	L_UPPER_LEG, L_LOWER_LEG, L_FOOT,
	R_UPPER_LEG, R_LOWER_LEG, R_FOOT,
}
enum Hand { NONE, RIGHT, LEFT }
enum Attack { NONE, RECOIL, STAB, PUNCH, KICK, BUTT }

## Имена костей в том же порядке, что и Bone (профиль Godot Humanoid).
const BONE_NAMES: PackedStringArray = [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
]
## Материал модели, который перекрашивается под игрока.
const SUIT_MATERIAL_NAME: String = "Suit"
## Метка узла предмета «оружие ближнего боя»: выпад вместо отдачи. Ставится либо прямо
## метаданными узла (melee = true), либо свойством в Blender — тогда Godot кладёт его в extras.
const MELEE_META: StringName = &"melee"
const GLTF_EXTRAS_META: StringName = &"extras"
const HEADLESS_DISPLAY: String = "headless"
const LEFT: float = -1.0
const RIGHT: float = 1.0
const SIDES: Array[float] = [LEFT, RIGHT]
const LEG_COUNT: int = 2
## Кости конечности идут в Bone подряд: верхняя, нижняя (LOWER), кисть или стопа (TIP).
const LOWER: int = 1
const TIP: int = 2
const EPSILON: float = 0.001

# --- Ник над головой ---
## Ник держится над головой и опускается вместе с ней, когда игрок ползёт.
const LABEL_ABOVE_HEAD: float = 0.56
const LABEL_FOLLOW_RATE: float = 8.0
## До этого расстояния ник обычного размера, дальше растёт, чтобы читаться с 15 м.
const LABEL_NEAR_DISTANCE: float = 5.0
const LABEL_MAX_SCALE: float = 2.6

# --- Взгляд ---
## Дальше голова выглядит сломанной: шлем уходит в воротник и ранец.
const MAX_LOOK_PITCH: float = deg_to_rad(50.0)
const LOOK_HEAD_SHARE: float = 0.6
const LOOK_NECK_SHARE: float = 0.18
const LOOK_CHEST_SHARE: float = 0.14

# --- Точка хвата в ладони (в осях модели, для правой руки; у левой X с минусом) ---
const GRIP_POINT: Vector3 = Vector3(0.3, 0.855, 0.0)
## Предмет смотрит по -Z. В опущенной руке это «вниз вдоль руки», верх предмета — вперёд.
const GRIP_BASIS: Basis = Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)

# --- Сглаживание состояний, 1/с (больше — резче) ---
const MOVE_BLEND_RATE: float = 10.0
const HEADING_BLEND_RATE: float = 9.0
const AIR_RISE_RATE: float = 14.0
const AIR_FALL_RATE: float = 6.0
const STATE_BLEND_RATE: float = 7.0
const AIM_BLEND_RATE: float = 11.0
## Длинный кадр (подгрузка, сворачивание окна) не должен «выстрелить» позой.
const MAX_STEP_SEC: float = 0.1
## Оценка скорости по смещению узла: быстрее этого — телепорт (спавн, новый раунд), а не бег.
const MAX_ESTIMATED_SPEED: float = 25.0

# --- Ходьба и бег ---
## Скорость, при которой шаг полный (скорость бега игрока).
const RUN_SPEED: float = 5.0
const HEADING_MIN_SPEED: float = 0.15
## Полных циклов (два шага) в секунду — на месте и на полном ходу.
const CADENCE_WALK: float = 1.25
const CADENCE_RUN: float = 2.15
const STEPS_PER_CYCLE: float = 2.0
## Прыжки на одной ноге идут вдвое реже шагов, поэтому фаза живёт в двух оборотах.
const HOP_CADENCE_SHARE: float = 0.5
const PHASE_SPAN: float = TAU / HOP_CADENCE_SHARE
## Размах растёт быстрее скорости: даже медленный шаг заметен.
const STRIDE_CURVE: float = 0.6
const LEG_SWING: float = 0.82
const LEG_LIFT: float = 0.3
const KNEE_BEND: float = 1.25
const KNEE_RUN_BEND: float = 0.12
const FOOT_LEVEL: float = 0.55
const SIDE_STEP: float = 0.5
const ARM_SWING: float = 0.95
const ARM_RUN_SPREAD: float = 0.1
const ELBOW_RUN_BEND: float = 1.0
const ELBOW_SWING: float = 0.35
const BOUNCE_HEIGHT: float = 0.035
const RUN_CROUCH: float = 0.03
const LEAN: float = 0.2
const LEAN_LEG_SHARE: float = 0.6
const LEAN_NECK_SHARE: float = 0.5
const STRAFE_ROLL: float = 0.12
const HIP_TWIST: float = 0.16
const CHEST_TWIST: float = 0.34
const HEAD_BOB: float = 0.05

# --- Покой ---
## Игроки стартуют с разной фазой дыхания и шага, чтобы толпа не двигалась синхронно.
const DESYNC_SEC: float = 60.0
const BREATH_RATE: float = 1.7
const BREATH_RISE: float = 0.005
const BREATH_CHEST: float = 0.018
const HEAD_DRIFT_RATE: float = 0.45
const HEAD_DRIFT: float = 0.07
const ARM_REST_SPREAD: float = 0.1
const ARM_BREATH_SPREAD: float = 0.02
const ELBOW_REST_BEND: float = 0.14
const SWAY_RATE: float = 0.6
const SWAY_ROLL: float = 0.012

# --- Прыжок и падение ---
const AIR_SPEED_THRESHOLD: float = 1.5
const FALL_REFERENCE_SPEED: float = 5.0
const AIR_ARM_FORWARD: float = 0.25
const AIR_ARM_SPREAD_RISE: float = 0.75
const AIR_ARM_SPREAD_FALL: float = 1.65
const AIR_ELBOW: float = 0.45
const AIR_LEAN: float = 0.1
const AIR_POSE: Dictionary[int, Vector3] = {
	Bone.L_UPPER_LEG: Vector3(0.85, 0.0, -0.08),
	Bone.L_LOWER_LEG: Vector3(-1.2, 0.0, 0.0),
	Bone.L_FOOT: Vector3(0.3, 0.0, 0.0),
	Bone.R_UPPER_LEG: Vector3(-0.2, 0.0, 0.08),
	Bone.R_LOWER_LEG: Vector3(-0.55, 0.0, 0.0),
	Bone.R_FOOT: Vector3(-0.35, 0.0, 0.0),
}

# --- Одна нога: прыжки на оставшейся ---
## Какая доля скорости бега уже даёт прыжки в полную силу.
const HOP_FULL_MOVE: float = 0.35
const HOP_HEIGHT: float = 0.13
const HOP_CROUCH: float = 0.05
const HOP_THIGH: float = 0.5
const HOP_KNEE: float = 0.95
const HOP_LEAN: float = 0.1
## Таз сдвигается к центру, чтобы оставшаяся нога была под корпусом.
const HOP_SHIFT: float = 0.07
const HOP_TILT: float = 0.07
const BALANCE_SPREAD: float = 0.5
const BALANCE_FLAP: float = 0.45
const BALANCE_ELBOW: float = 0.55
const BALANCE_WOBBLE_RATE: float = 2.6
const BALANCE_WOBBLE: float = 0.045
## Руки качаются заметнее корпуса.
const BALANCE_ARM_WOBBLE: float = 2.0

# --- Без ног: ползком на руках ---
const CRAWL_FULL_MOVE: float = 0.15
const CRAWL_HIPS_HEIGHT: float = 0.14
const CRAWL_HIPS_BACK: float = 0.3
const CRAWL_BODY_PITCH: float = -1.22
const CRAWL_ARCH: float = 0.12
const CRAWL_NECK: float = 0.35
const CRAWL_HEAD: float = 0.55
const CRAWL_ARM_PITCH: float = 1.5
const CRAWL_ARM_SPREAD: float = 0.3
const CRAWL_REACH: float = 0.5
const CRAWL_ELBOW: float = 1.05
const CRAWL_ELBOW_REACH: float = 0.55
const CRAWL_WIGGLE: float = 0.16
## Позвоночник и грудь возвращают по половине поворота таза: плечи остаются ровно.
const CRAWL_COUNTER_SHARE: float = 0.5
const CRAWL_ROLL: float = 0.09
const CRAWL_BOB: float = 0.025

# --- Предмет в руке ---
const AIM_SHOULDER: float = 0.82
const AIM_ELBOW: float = 0.72
const AIM_INWARD: float = 0.16
const AIM_SPREAD: float = 0.06
const AIM_PITCH_LIMIT: float = deg_to_rad(65.0)

# --- Атаки (разовые) ---
const ATTACK_DURATION: Dictionary[int, float] = {
	Attack.RECOIL: 0.3,
	Attack.STAB: 0.38,
	Attack.PUNCH: 0.42,
	Attack.KICK: 0.5,
	Attack.BUTT: 0.4,
}
## Доля длительности, на которой удар достигает цели.
const ATTACK_PEAK: Dictionary[int, float] = {
	Attack.RECOIL: 0.14,
	Attack.STAB: 0.4,
	Attack.PUNCH: 0.42,
	Attack.KICK: 0.45,
	Attack.BUTT: 0.4,
}
## Замах занимает эту долю времени в начале удара и достигает пика на своей середине.
const WINDUP_SHARE: float = 0.34
const WINDUP_PEAK: float = 0.5
## Насколько замах разворачивает корпус в обратную сторону перед ударом.
const TWIST_WINDUP: float = 0.5
const RECOIL_ELBOW: float = 0.38
const RECOIL_SHOULDER: float = 0.1
const RECOIL_CHEST: float = 0.07
const STAB_SHOULDER: float = 0.5
const STAB_EXTEND: float = 0.42
const STAB_WINDUP: float = 0.3
const STAB_COCK: float = 0.6
const STAB_TWIST: float = 0.4
const STAB_LEAN: float = 0.14
const PUNCH_SHOULDER: float = 1.5
const PUNCH_INWARD: float = 0.2
const PUNCH_ELBOW_COCK: float = 1.7
const PUNCH_ELBOW_END: float = 0.1
const KICK_THIGH: float = 1.35
const KICK_COCK: float = 1.3
const KICK_LEAN_BACK: float = 0.22
const BUTT_LEAN: float = 0.5
const BUTT_WINDUP: float = 0.4
const BUTT_HEAD: float = 0.3

# --- Смерть: игрушка поскальзывается и падает на спину ---
const COLLAPSE_SEC: float = 0.42
const RISE_SEC: float = 0.3
const DEAD_HIPS_HEIGHT: float = 0.17
const DEAD_BOUNCE_HEIGHT: float = 0.09
const DEAD_BOUNCE_RATE: float = 13.0
const DEAD_BOUNCE_DAMPING: float = 5.5
const DEAD_JIGGLE: float = 0.3
const DEAD_POSE: Dictionary[int, Vector3] = {
	Bone.HIPS: Vector3(1.4, 0.12, 0.0),
	Bone.SPINE: Vector3(0.04, 0.0, 0.05),
	Bone.CHEST: Vector3(0.04, 0.0, 0.05),
	Bone.NECK: Vector3(0.05, 0.25, 0.0),
	Bone.HEAD: Vector3(0.05, 0.5, 0.12),
	Bone.L_UPPER_ARM: Vector3(0.1, 0.0, -1.45),
	Bone.L_LOWER_ARM: Vector3(0.0, 0.0, -0.7),
	Bone.L_HAND: Vector3(0.0, 0.0, -0.2),
	Bone.R_UPPER_ARM: Vector3(0.15, 0.0, 2.45),
	Bone.R_LOWER_ARM: Vector3(0.0, 0.0, 0.85),
	Bone.R_HAND: Vector3(0.0, 0.0, 0.3),
	Bone.L_UPPER_LEG: Vector3(-0.1, 0.0, -0.42),
	Bone.L_LOWER_LEG: Vector3(-0.08, 0.0, 0.0),
	Bone.L_FOOT: Vector3(0.0, 0.5, 0.0),
	Bone.R_UPPER_LEG: Vector3(0.75, 0.0, 0.2),
	Bone.R_LOWER_LEG: Vector3(-1.5, 0.0, 0.0),
	Bone.R_FOOT: Vector3(0.3, -0.3, 0.0),
}

# --- Отлетающие конечности ---
const POP_SIDE_SPEED: float = 2.4
const POP_UP_SPEED: float = 3.2
const POP_FORWARD_SPEED: float = 1.2
const POP_SPIN: float = 9.0
const POP_SPEED_JITTER: float = 0.25


## Поза: углы Эйлера каждой кости в осях модели и смещение таза.
class Pose:
	extends RefCounted

	var euler: PackedVector3Array = []
	var hips_offset: Vector3 = Vector3.ZERO

	func _init(bone_count: int) -> void:
		euler.resize(bone_count)
		clear()

	func clear() -> void:
		euler.fill(Vector3.ZERO)
		hips_offset = Vector3.ZERO

	func add(bone: int, value: Vector3) -> void:
		euler[bone] += value

	func toward(bone: int, target: Vector3, weight: float) -> void:
		euler[bone] = euler[bone].lerp(target, weight)

	func blend(other: Pose, weight: float) -> void:
		for bone: int in euler.size():
			euler[bone] = euler[bone].lerp(other.euler[bone], weight)
		hips_offset = hips_offset.lerp(other.hips_offset, weight)


## Сцена отлетевшей конечности (limb_prop.tscn).
@export var limb_prop_scene: PackedScene

var _is_set_up: bool = false
var _headless: bool = false
var _model: Node3D = null
var _skeleton: Skeleton3D = null
var _name_label: Label3D = null
var _props: Node = null
var _label_pixel_size: float = 0.0
var _suit_material: StandardMaterial3D = null
## Меш каждой конечности: BodyPart.Part -> MeshInstance3D.
var _limb_meshes: Dictionary[int, MeshInstance3D] = {}
## Узлы-ладони, в которые кладётся предмет: Hand -> Node3D.
var _grips: Dictionary[int, Node3D] = {}

# Скелет: индекс кости в Skeleton3D и повороты для перевода «оси модели -> оси кости».
var _bone_index: PackedInt32Array = []
var _to_parent: Array[Quaternion] = []
var _rest_global: Array[Quaternion] = []
var _hips_rest: Vector3 = Vector3.ZERO

# Входы от геймплея.
var _velocity: Vector3 = Vector3.ZERO
## Пока set_velocity ни разу не вызывали, скорость оценивается по смещению узла в мире:
## анимация работает и там, где скорость ещё не передают.
var _velocity_is_given: bool = false
var _last_position: Vector3 = Vector3.INF
var _look_pitch: float = 0.0
var _limbs_lost: int = 0
var _dead: bool = false
var _first_person: bool = false
var _held_scene: PackedScene = null
var _held_node: Node3D = null
var _held_hand: Hand = Hand.NONE
var _held_melee: bool = false

# Сглаженное состояние анимации.
var _pose: Pose = Pose.new(Bone.size())
var _overlay: Pose = Pose.new(Bone.size())
var _time: float = 0.0
var _phase: float = 0.0
var _move: float = 0.0
## Направление движения в осях тела: x — вправо, y — вперёд.
var _heading: Vector2 = Vector2(0.0, 1.0)
var _air: float = 0.0
var _fall: float = 0.0
var _limp: float = 0.0
var _crawl: float = 0.0
var _hop_side: float = RIGHT
## Вес позы прицеливания для левой и правой руки.
var _aim: Dictionary[float, float] = {LEFT: 0.0, RIGHT: 0.0}
var _attack: Attack = Attack.NONE
var _attack_time: float = 0.0
var _attack_side: float = RIGHT
var _dead_progress: float = 0.0
var _dead_landed_sec: float = 0.0


func _ready() -> void:
	_set_up()
	_update_processing()


func _process(delta: float) -> void:
	if not _velocity_is_given:
		_estimate_velocity(delta)
	var step: float = minf(delta, MAX_STEP_SEC)
	_advance_state(step)
	_build_pose()
	_apply_pose()
	_update_label(step)


func set_display_name(text: String) -> void:
	_set_up()
	_name_label.text = text


## Наклон головы по взгляду игрока, радианы (вверх — плюс). Рука с предметом целится туда же.
func set_look_pitch(pitch: float) -> void:
	_look_pitch = pitch if is_finite(pitch) else 0.0


## Перекрашивает костюм только этого игрока.
func set_body_color(color: Color) -> void:
	_set_up()
	_suit_material.albedo_color = color


## Скорость аватара в мире, м/с: клиент передаёт её каждый кадр, из неё получаются шаги и прыжок.
func set_velocity(velocity: Vector3) -> void:
	_velocity_is_given = true
	_velocity = velocity if velocity.is_finite() else Vector3.ZERO


## Маска потерянных конечностей (биты BodyPart.bit). Потерянная конечность прячется;
## with_effect ещё и отстреливает её физической деталью. Снятый бит возвращает конечность.
func set_limbs_lost(mask: int, with_effect: bool = true) -> void:
	_set_up()
	var changed: int = mask ^ _limbs_lost
	_limbs_lost = mask
	for part: BodyPart.Part in BodyPart.LIMBS:
		if changed & BodyPart.bit(part) == 0:
			continue
		var lost: bool = BodyPart.is_lost(mask, part)
		_limb_meshes[part].visible = not lost
		if not lost:
			_remove_props(part)
		elif with_effect:
			_pop_limb(part)
	if BodyPart.lost_legs(mask) == 1:
		_hop_side = LEFT if BodyPart.is_lost(mask, BodyPart.Part.RIGHT_LEG) else RIGHT
	_refresh_held_item()


## Предмет в руке (null — пустые руки). Сцена предмета: начало координат в точке хвата,
## ствол/клинок по -Z. Правая рука, без неё — левая, без обеих предмет не показывается.
func set_held_item(model: PackedScene) -> void:
	_set_up()
	if model == _held_scene:
		return
	_held_scene = model
	_drop_held_node()
	_refresh_held_item()


## Разовый удар: отдача (или выпад для ближнего боя) с предметом, тычок кулаком без него,
## пинок без рук.
func play_attack() -> void:
	_set_up()
	if _dead:
		return
	if _held_node != null:
		_attack = Attack.STAB if _held_melee else Attack.RECOIL
		_attack_side = _hand_side(_held_hand)
	elif _free_hand() != Hand.NONE:
		_attack = Attack.PUNCH
		_attack_side = _hand_side(_free_hand())
	elif BodyPart.lost_legs(_limbs_lost) < LEG_COUNT:
		_attack = Attack.KICK
		_attack_side = LEFT if BodyPart.is_lost(_limbs_lost, BodyPart.Part.RIGHT_LEG) else RIGHT
	else:
		_attack = Attack.BUTT
	_attack_time = 0.0


## true — игрушка падает и остаётся лежать, ник скрыт; false — встаёт (новый раунд).
func set_dead(dead: bool) -> void:
	_set_up()
	if dead == _dead:
		return
	_dead = dead
	_dead_landed_sec = 0.0
	_attack = Attack.NONE
	_update_label_visibility()


## Свой игрок: тело и ник не должны попадать в собственную камеру.
func set_first_person(enabled: bool) -> void:
	_set_up()
	_first_person = enabled
	_model.visible = not enabled
	_update_label_visibility()
	_update_processing()


## Заменяет на меше все поверхности с материалом костюма на общий материал игрока.
static func apply_suit_material(mesh_instance: MeshInstance3D, suit: Material) -> void:
	if mesh_instance.mesh == null:
		return
	for surface: int in mesh_instance.mesh.get_surface_count():
		var material: Material = mesh_instance.mesh.surface_get_material(surface)
		if material != null and material.resource_name == SUIT_MATERIAL_NAME:
			mesh_instance.set_surface_override_material(surface, suit)


## Копия материала костюма из модели — своя у каждого игрока, чтобы красить независимо.
static func make_suit_material(root: Node) -> StandardMaterial3D:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
			if material != null and material.resource_name == SUIT_MATERIAL_NAME:
				return material.duplicate() as StandardMaterial3D
	return StandardMaterial3D.new()


## Узел предмета помечен как оружие ближнего боя (см. MELEE_META)?
static func is_melee_item(item: Node) -> bool:
	var nodes: Array[Node] = [item]
	nodes.append_array(item.get_children())
	for node: Node in nodes:
		if node.get_meta(MELEE_META, false):
			return true
		if not node.has_meta(GLTF_EXTRAS_META):
			continue
		var extras: Dictionary = node.get_meta(GLTF_EXTRAS_META) as Dictionary
		if extras.get(String(MELEE_META), false):
			return true
	return false


## Вызывается из _ready и из каждого публичного метода: методы работают и до входа в дерево.
func _set_up() -> void:
	if _is_set_up:
		return
	_is_set_up = true
	_headless = DisplayServer.get_name() == HEADLESS_DISPLAY
	_time = randf() * DESYNC_SEC
	_phase = randf() * PHASE_SPAN
	_model = $Model
	_skeleton = $Model/Armature/Skeleton3D
	_name_label = $NameLabel
	_props = $Props
	_label_pixel_size = _name_label.pixel_size
	_limb_meshes[BodyPart.Part.LEFT_ARM] = $Model/Armature/Skeleton3D/ArmLeft as MeshInstance3D
	_limb_meshes[BodyPart.Part.RIGHT_ARM] = $Model/Armature/Skeleton3D/ArmRight as MeshInstance3D
	_limb_meshes[BodyPart.Part.LEFT_LEG] = $Model/Armature/Skeleton3D/LegLeft as MeshInstance3D
	_limb_meshes[BodyPart.Part.RIGHT_LEG] = $Model/Armature/Skeleton3D/LegRight as MeshInstance3D
	_suit_material = make_suit_material(_model)
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		apply_suit_material(node as MeshInstance3D, _suit_material)
	_read_skeleton()
	_grips[Hand.RIGHT] = _make_grip(Bone.R_HAND, RIGHT)
	_grips[Hand.LEFT] = _make_grip(Bone.L_HAND, LEFT)


func _read_skeleton() -> void:
	_bone_index.resize(Bone.size())
	_to_parent.resize(Bone.size())
	_rest_global.resize(Bone.size())
	for bone: int in Bone.size():
		var index: int = _skeleton.find_bone(BONE_NAMES[bone])
		_bone_index[bone] = index
		_to_parent[bone] = Quaternion.IDENTITY
		_rest_global[bone] = Quaternion.IDENTITY
		if index == -1:
			push_warning("PlayerVisuals: в скелете нет кости %s" % BONE_NAMES[bone])
			continue
		_rest_global[bone] = _skeleton.get_bone_global_rest(index).basis.get_rotation_quaternion()
		var parent: int = _skeleton.get_bone_parent(index)
		if parent != -1:
			_to_parent[bone] = _skeleton.get_bone_global_rest(parent).basis.get_rotation_quaternion().inverse()
	if _bone_index[Bone.HIPS] != -1:
		_hips_rest = _skeleton.get_bone_rest(_bone_index[Bone.HIPS]).origin


## Узел-ладонь на кости кисти: его оси совпадают с осями предмета (см. GRIP_BASIS).
func _make_grip(hand_bone: Bone, side: float) -> Node3D:
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.name = "%sAttachment" % BONE_NAMES[hand_bone]
	_skeleton.add_child(attachment)
	attachment.bone_name = BONE_NAMES[hand_bone]
	var grip: Node3D = Node3D.new()
	grip.name = "Grip"
	attachment.add_child(grip)
	var in_model: Transform3D = Transform3D(GRIP_BASIS, Vector3(GRIP_POINT.x * side, GRIP_POINT.y, GRIP_POINT.z))
	var bone_rest: Transform3D = Transform3D.IDENTITY
	if _bone_index[hand_bone] != -1:
		bone_rest = _skeleton.get_bone_global_rest(_bone_index[hand_bone])
	grip.transform = bone_rest.affine_inverse() * in_model
	return grip


func _update_processing() -> void:
	set_process(not _headless and not _first_person)


func _update_label_visibility() -> void:
	_name_label.visible = not _dead and not _first_person


## Ник следует за высотой головы; вдали он крупнее (читается с 15 м), вблизи небольшой.
func _update_label(delta: float) -> void:
	if not _name_label.visible:
		return
	if _bone_index[Bone.HEAD] != -1:
		var head_height: float = _skeleton.get_bone_global_pose(_bone_index[Bone.HEAD]).origin.y
		_name_label.position.y = _approach(_name_label.position.y, head_height + LABEL_ABOVE_HEAD, LABEL_FOLLOW_RATE, delta)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance: float = camera.global_position.distance_to(_name_label.global_position)
	_name_label.pixel_size = _label_pixel_size * clampf(distance / LABEL_NEAR_DISTANCE, 1.0, LABEL_MAX_SCALE)


# ----------------------------------------------------------------------------------------------
# Предмет в руке
# ----------------------------------------------------------------------------------------------

## Рука, которая сейчас может что-то держать или бить.
func _free_hand() -> Hand:
	if not BodyPart.is_lost(_limbs_lost, BodyPart.Part.RIGHT_ARM):
		return Hand.RIGHT
	if not BodyPart.is_lost(_limbs_lost, BodyPart.Part.LEFT_ARM):
		return Hand.LEFT
	return Hand.NONE


func _hand_side(hand: Hand) -> float:
	return LEFT if hand == Hand.LEFT else RIGHT


func _drop_held_node() -> void:
	if _held_node != null:
		_held_node.get_parent().remove_child(_held_node)
		_held_node.queue_free()
	_held_node = null
	_held_hand = Hand.NONE
	_held_melee = false


## Кладёт предмет в подходящую руку: после смены предмета или потери/возврата руки.
func _refresh_held_item() -> void:
	var hand: Hand = _free_hand() if _held_scene != null else Hand.NONE
	if hand == _held_hand:
		return
	if hand == Hand.NONE:
		_drop_held_node()
		return
	if _held_node == null:
		_held_node = _held_scene.instantiate() as Node3D
		if _held_node == null:
			push_warning("PlayerVisuals: корень сцены предмета должен быть Node3D")
			return
		_held_melee = is_melee_item(_held_node)
	else:
		_held_node.get_parent().remove_child(_held_node)
	_grips[hand].add_child(_held_node)
	_held_hand = hand


# ----------------------------------------------------------------------------------------------
# Отлетающие конечности
# ----------------------------------------------------------------------------------------------

func _limb_side(part: BodyPart.Part) -> float:
	return LEFT if part == BodyPart.Part.LEFT_ARM or part == BodyPart.Part.LEFT_LEG else RIGHT


func _limb_root_bone(part: BodyPart.Part) -> Bone:
	match part:
		BodyPart.Part.LEFT_ARM:
			return Bone.L_UPPER_ARM
		BodyPart.Part.RIGHT_ARM:
			return Bone.R_UPPER_ARM
		BodyPart.Part.LEFT_LEG:
			return Bone.L_UPPER_LEG
		_:
			return Bone.R_UPPER_LEG


func _pop_limb(part: BodyPart.Part) -> void:
	if _headless or limb_prop_scene == null or not is_inside_tree():
		return
	var prop: LimbProp = limb_prop_scene.instantiate() as LimbProp
	if prop == null:
		return
	prop.set_meta(&"part", part)
	_props.add_child(prop)
	# Меш конечности задан в осях модели в позе покоя; деталь стартует там, где сейчас конечность.
	var pose_shift: Transform3D = Transform3D.IDENTITY
	var bone_index: int = _bone_index[_limb_root_bone(part)]
	if bone_index != -1:
		pose_shift = _skeleton.get_bone_global_pose(bone_index) * _skeleton.get_bone_global_rest(bone_index).affine_inverse()
	var side: float = _limb_side(part)
	var jitter: float = 1.0 + randf_range(-POP_SPEED_JITTER, POP_SPEED_JITTER)
	var launch: Vector3 = Vector3(side * POP_SIDE_SPEED, POP_UP_SPEED, -POP_FORWARD_SPEED * randf()) * jitter
	var spin: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), -side).normalized() * POP_SPIN
	var body_basis: Basis = global_basis.orthonormalized()
	prop.launch(_limb_meshes[part].mesh, _suit_material, _skeleton.global_transform * pose_shift,
			_velocity + body_basis * launch, body_basis * spin)


func _remove_props(part: BodyPart.Part) -> void:
	for prop: Node in _props.get_children():
		if prop.get_meta(&"part", -1) == part:
			prop.queue_free()


# ----------------------------------------------------------------------------------------------
# Анимация: состояние
# ----------------------------------------------------------------------------------------------

func _estimate_velocity(delta: float) -> void:
	var current: Vector3 = global_position
	var estimate: Vector3 = Vector3.ZERO
	if _last_position.is_finite() and delta > 0.0:
		estimate = (current - _last_position) / delta
	_last_position = current
	_velocity = estimate if estimate.length() < MAX_ESTIMATED_SPEED else Vector3.ZERO


static func _approach(value: float, target: float, rate: float, delta: float) -> float:
	return lerpf(value, target, 1.0 - exp(-rate * delta))


## 0 -> 1 к моменту peak -> 0 к концу, без изломов.
static func _pulse(progress: float, peak: float) -> float:
	if progress < peak:
		return smoothstep(0.0, peak, progress)
	return 1.0 - smoothstep(peak, 1.0, progress)


func _advance_state(delta: float) -> void:
	_time += delta
	var local: Vector3 = global_basis.orthonormalized().inverse() * _velocity
	var horizontal: Vector2 = Vector2(local.x, -local.z)
	var speed: float = horizontal.length()
	_move = _approach(_move, clampf(speed / RUN_SPEED, 0.0, 1.0), MOVE_BLEND_RATE, delta)
	if speed > HEADING_MIN_SPEED:
		_heading = _heading.lerp(horizontal / speed, 1.0 - exp(-HEADING_BLEND_RATE * delta))
	_phase = wrapf(_phase + TAU * lerpf(CADENCE_WALK, CADENCE_RUN, _move) * delta, 0.0, PHASE_SPAN)
	var airborne: bool = absf(_velocity.y) > AIR_SPEED_THRESHOLD
	_air = _approach(_air, 1.0 if airborne else 0.0, AIR_RISE_RATE if airborne else AIR_FALL_RATE, delta)
	_fall = _approach(_fall, clampf(-_velocity.y / FALL_REFERENCE_SPEED, -1.0, 1.0), AIR_FALL_RATE, delta)
	var lost_legs: int = BodyPart.lost_legs(_limbs_lost)
	_limp = _approach(_limp, 1.0 if lost_legs == 1 else 0.0, STATE_BLEND_RATE, delta)
	_crawl = _approach(_crawl, 1.0 if lost_legs == LEG_COUNT else 0.0, STATE_BLEND_RATE, delta)
	for side: float in SIDES:
		var holding: bool = _held_node != null and _hand_side(_held_hand) == side
		_aim[side] = _approach(_aim[side], 1.0 if holding else 0.0, AIM_BLEND_RATE, delta)
	if _attack != Attack.NONE:
		_attack_time += delta
		if _attack_time >= ATTACK_DURATION[_attack]:
			_attack = Attack.NONE
	if _dead:
		_dead_progress = minf(_dead_progress + delta / COLLAPSE_SEC, 1.0)
		if _dead_progress >= 1.0:
			_dead_landed_sec += delta
	else:
		_dead_progress = maxf(_dead_progress - delta / RISE_SEC, 0.0)


# ----------------------------------------------------------------------------------------------
# Анимация: сборка позы
# ----------------------------------------------------------------------------------------------

func _arm(side: float) -> int:
	return Bone.L_UPPER_ARM if side < 0.0 else Bone.R_UPPER_ARM


func _leg(side: float) -> int:
	return Bone.L_UPPER_LEG if side < 0.0 else Bone.R_UPPER_LEG


func _build_pose() -> void:
	_pose.clear()
	_add_idle(_pose)
	_add_locomotion(_pose)
	_add_hop(_pose)
	_blend_air(_pose)
	if _crawl > EPSILON:
		_fill_crawl(_overlay)
		_pose.blend(_overlay, smoothstep(0.0, 1.0, _crawl))
	_add_look(_pose)
	_blend_aim(_pose)
	_add_attack(_pose)
	if _dead_progress > 0.0:
		_fill_dead(_overlay)
		# Падение ускоряется, как под силой тяжести.
		_pose.blend(_overlay, _dead_progress * _dead_progress)


func _add_idle(pose: Pose) -> void:
	var breath: float = sin(_time * BREATH_RATE)
	pose.hips_offset.y += breath * BREATH_RISE
	pose.add(Bone.HIPS, Vector3(0.0, 0.0, sin(_time * SWAY_RATE) * SWAY_ROLL))
	pose.add(Bone.CHEST, Vector3(breath * BREATH_CHEST, 0.0, 0.0))
	pose.add(Bone.HEAD, Vector3(0.0, sin(_time * HEAD_DRIFT_RATE) * HEAD_DRIFT, 0.0))
	for side: float in SIDES:
		pose.add(_arm(side), Vector3(0.0, 0.0, side * (ARM_REST_SPREAD + breath * ARM_BREATH_SPREAD)))
		pose.add(_arm(side) + LOWER, Vector3(ELBOW_REST_BEND, 0.0, 0.0))


func _add_locomotion(pose: Pose) -> void:
	var stride: float = pow(_move, STRIDE_CURVE) * (1.0 - _limp)
	var forward: float = _heading.y
	var strafe: float = _heading.x
	var lean: float = LEAN * _move * forward
	for side: float in SIDES:
		# Левая нога и правая рука идут в одной фазе.
		var phase: float = _phase + (PI if side > 0.0 else 0.0)
		var swing: float = sin(phase)
		var lift: float = maxf(cos(phase), 0.0)
		var thigh: float = LEG_SWING * stride * (swing * forward + LEG_LIFT * lift) + lean * LEAN_LEG_SHARE
		var knee: float = -LEG_SWING * stride * KNEE_BEND * lift - KNEE_RUN_BEND * stride
		pose.add(_leg(side), Vector3(thigh, 0.0, LEG_SWING * stride * SIDE_STEP * swing * strafe))
		pose.add(_leg(side) + LOWER, Vector3(knee, 0.0, 0.0))
		pose.add(_leg(side) + TIP, Vector3(-(thigh + knee) * FOOT_LEVEL, 0.0, 0.0))
		var arm_swing: float = -swing * forward
		pose.add(_arm(side), Vector3(ARM_SWING * stride * arm_swing, 0.0, side * ARM_RUN_SPREAD * stride))
		pose.add(_arm(side) + LOWER, Vector3(stride * (ELBOW_RUN_BEND + ELBOW_SWING * maxf(arm_swing, 0.0)), 0.0, 0.0))
	var step_wave: float = sin(_phase) * forward
	pose.hips_offset.y += stride * (BOUNCE_HEIGHT * cos(STEPS_PER_CYCLE * _phase) - RUN_CROUCH)
	pose.add(Bone.HIPS, Vector3(-lean, -HIP_TWIST * stride * step_wave, -STRAFE_ROLL * _move * strafe))
	pose.add(Bone.CHEST, Vector3(0.0, CHEST_TWIST * stride * step_wave, 0.0))
	pose.add(Bone.NECK, Vector3(lean * LEAN_NECK_SHARE, 0.0, 0.0))
	pose.add(Bone.HEAD, Vector3(HEAD_BOB * stride * cos(STEPS_PER_CYCLE * _phase), -(CHEST_TWIST - HIP_TWIST) * stride * step_wave, 0.0))


## Одна нога: прыжки на оставшейся, руки ловят равновесие.
func _add_hop(pose: Pose) -> void:
	if _limp < EPSILON:
		return
	var energy: float = minf(_move / HOP_FULL_MOVE, 1.0)
	var flight: float = pow(sin(_phase * HOP_CADENCE_SHARE), 2.0)
	var crouch: float = 1.0 - flight
	var wobble: float = sin(_time * BALANCE_WOBBLE_RATE) * BALANCE_WOBBLE * (1.0 - energy)
	var leg: int = _leg(_hop_side)
	pose.hips_offset += _limp * Vector3(-_hop_side * HOP_SHIFT, energy * (HOP_HEIGHT * flight - HOP_CROUCH * crouch), 0.0)
	pose.add(Bone.HIPS, _limp * Vector3(-HOP_LEAN * energy * _heading.y, 0.0, -_hop_side * HOP_TILT + wobble))
	pose.add(leg, _limp * Vector3(HOP_THIGH * energy * crouch + HOP_LEAN * energy * _heading.y, 0.0, _hop_side * HOP_TILT - wobble))
	pose.add(leg + LOWER, _limp * Vector3(-HOP_KNEE * energy * crouch, 0.0, 0.0))
	pose.add(leg + TIP, _limp * Vector3((HOP_KNEE - HOP_THIGH) * energy * crouch, 0.0, 0.0))
	for side: float in SIDES:
		var spread: float = BALANCE_SPREAD + BALANCE_FLAP * energy * flight - side * wobble * BALANCE_ARM_WOBBLE
		pose.add(_arm(side), _limp * Vector3(0.0, 0.0, side * spread))
		pose.add(_arm(side) + LOWER, _limp * Vector3(BALANCE_ELBOW * (1.0 - energy * flight), 0.0, 0.0))


func _blend_air(pose: Pose) -> void:
	if _air < EPSILON:
		return
	var falling: float = remap(_fall, -1.0, 1.0, 0.0, 1.0)
	for bone: int in AIR_POSE:
		pose.toward(bone, AIR_POSE[bone], _air)
	for side: float in SIDES:
		var spread: float = lerpf(AIR_ARM_SPREAD_RISE, AIR_ARM_SPREAD_FALL, falling)
		pose.toward(_arm(side), Vector3(AIR_ARM_FORWARD, 0.0, side * spread), _air)
		pose.toward(_arm(side) + LOWER, Vector3(AIR_ELBOW, 0.0, 0.0), _air)
	pose.add(Bone.HIPS, Vector3(-AIR_LEAN * _air, 0.0, 0.0))


## Без ног: корпус лежит на полу, руки по очереди подтягивают его вперёд.
func _fill_crawl(pose: Pose) -> void:
	pose.clear()
	var energy: float = minf(_move / CRAWL_FULL_MOVE, 1.0)
	var pull: float = sin(_phase)
	var breath: float = sin(_time * BREATH_RATE)
	pose.hips_offset = Vector3(0.0, CRAWL_HIPS_HEIGHT - _hips_rest.y + energy * CRAWL_BOB * absf(cos(_phase)), CRAWL_HIPS_BACK)
	pose.euler[Bone.HIPS] = Vector3(CRAWL_BODY_PITCH, CRAWL_WIGGLE * energy * pull, CRAWL_ROLL * energy * pull)
	var counter: float = -CRAWL_WIGGLE * energy * pull * CRAWL_COUNTER_SHARE
	pose.euler[Bone.SPINE] = Vector3(CRAWL_ARCH + breath * BREATH_CHEST, counter, 0.0)
	pose.euler[Bone.CHEST] = Vector3(CRAWL_ARCH, counter, 0.0)
	pose.euler[Bone.NECK] = Vector3(CRAWL_NECK, 0.0, 0.0)
	pose.euler[Bone.HEAD] = Vector3(CRAWL_HEAD, sin(_time * HEAD_DRIFT_RATE) * HEAD_DRIFT, 0.0)
	for side: float in SIDES:
		var reach: float = -side * pull * energy
		pose.euler[_arm(side)] = Vector3(CRAWL_ARM_PITCH + CRAWL_REACH * reach, 0.0, side * CRAWL_ARM_SPREAD)
		pose.euler[_arm(side) + LOWER] = Vector3(CRAWL_ELBOW - CRAWL_ELBOW_REACH * reach, 0.0, 0.0)


func _add_look(pose: Pose) -> void:
	var pitch: float = clampf(_look_pitch, -MAX_LOOK_PITCH, MAX_LOOK_PITCH)
	pose.add(Bone.HEAD, Vector3(pitch * LOOK_HEAD_SHARE, 0.0, 0.0))
	pose.add(Bone.NECK, Vector3(pitch * LOOK_NECK_SHARE, 0.0, 0.0))
	pose.add(Bone.CHEST, Vector3(pitch * LOOK_CHEST_SHARE, 0.0, 0.0))


## Наклон корпуса вперёд/назад: его вычитают позы рук, заданные относительно горизонта.
func _torso_pitch(pose: Pose) -> float:
	return pose.euler[Bone.HIPS].x + pose.euler[Bone.SPINE].x + pose.euler[Bone.CHEST].x


## Рука с предметом вытянута вперёд и следит за взглядом.
func _blend_aim(pose: Pose) -> void:
	var pitch: float = clampf(_look_pitch, -AIM_PITCH_LIMIT, AIM_PITCH_LIMIT)
	for side: float in SIDES:
		var weight: float = _aim[side]
		if weight < EPSILON:
			continue
		var shoulder: float = AIM_SHOULDER + pitch - _torso_pitch(pose)
		pose.toward(_arm(side), Vector3(shoulder, side * AIM_INWARD, side * AIM_SPREAD), weight)
		pose.toward(_arm(side) + LOWER, Vector3(AIM_ELBOW, 0.0, 0.0), weight)
		pose.toward(_arm(side) + TIP, Vector3.ZERO, weight)


func _add_attack(pose: Pose) -> void:
	if _attack == Attack.NONE:
		return
	var progress: float = _attack_time / ATTACK_DURATION[_attack]
	var hit: float = _pulse(progress, ATTACK_PEAK[_attack])
	var windup: float = _pulse(minf(progress / WINDUP_SHARE, 1.0), WINDUP_PEAK)
	var side: float = _attack_side
	match _attack:
		Attack.RECOIL:
			pose.add(_arm(side), Vector3(RECOIL_SHOULDER * hit, 0.0, 0.0))
			pose.add(_arm(side) + LOWER, Vector3(RECOIL_ELBOW * hit, 0.0, 0.0))
			pose.add(Bone.CHEST, Vector3(RECOIL_CHEST * hit, 0.0, 0.0))
		Attack.STAB:
			pose.add(_arm(side), Vector3(STAB_SHOULDER * hit - STAB_WINDUP * windup, 0.0, 0.0))
			pose.add(_arm(side) + LOWER, Vector3(STAB_COCK * windup - STAB_EXTEND * hit, 0.0, 0.0))
			pose.add(Bone.CHEST, Vector3(0.0, side * STAB_TWIST * (hit - windup * TWIST_WINDUP), 0.0))
			pose.add(Bone.HIPS, Vector3(-STAB_LEAN * hit, 0.0, 0.0))
		Attack.PUNCH:
			var reach: float = maxf(hit, windup)
			var shoulder: float = PUNCH_SHOULDER - _torso_pitch(pose)
			pose.toward(_arm(side), Vector3(shoulder, side * PUNCH_INWARD, 0.0), reach)
			pose.toward(_arm(side) + LOWER, Vector3(lerpf(PUNCH_ELBOW_COCK, PUNCH_ELBOW_END, hit), 0.0, 0.0), reach)
			pose.add(Bone.CHEST, Vector3(0.0, side * STAB_TWIST * (hit - windup * TWIST_WINDUP), 0.0))
			pose.add(Bone.HIPS, Vector3(-STAB_LEAN * hit, 0.0, 0.0))
		Attack.KICK:
			var reach: float = maxf(hit, windup)
			pose.toward(_leg(side), Vector3(KICK_THIGH, 0.0, 0.0), reach)
			pose.toward(_leg(side) + LOWER, Vector3(-KICK_COCK * (1.0 - hit), 0.0, 0.0), reach)
			pose.add(Bone.HIPS, Vector3(KICK_LEAN_BACK * hit, 0.0, 0.0))
			pose.add(_leg(-side), Vector3(-KICK_LEAN_BACK * hit, 0.0, 0.0))
		Attack.BUTT:
			pose.add(Bone.HIPS, Vector3(BUTT_LEAN * (windup * BUTT_WINDUP - hit), 0.0, 0.0))
			pose.add(Bone.HEAD, Vector3(BUTT_HEAD * (windup - hit), 0.0, 0.0))


## Лежит на спине, раскинув руки и задрав колено; при приземлении подпрыгивает.
func _fill_dead(pose: Pose) -> void:
	pose.clear()
	var bounce: float = 0.0
	if _dead and _dead_progress >= 1.0:
		bounce = exp(-DEAD_BOUNCE_DAMPING * _dead_landed_sec) * absf(sin(DEAD_BOUNCE_RATE * _dead_landed_sec))
	for bone: int in DEAD_POSE:
		pose.euler[bone] = DEAD_POSE[bone]
		if bone > Bone.HEAD:
			pose.euler[bone] *= 1.0 + DEAD_JIGGLE * bounce
	pose.hips_offset = Vector3(0.0, DEAD_HIPS_HEIGHT - _hips_rest.y + DEAD_BOUNCE_HEIGHT * bounce, 0.0)


func _is_bone_lost(bone: int) -> bool:
	if bone >= Bone.L_UPPER_ARM and bone <= Bone.L_HAND:
		return BodyPart.is_lost(_limbs_lost, BodyPart.Part.LEFT_ARM)
	if bone >= Bone.R_UPPER_ARM and bone <= Bone.R_HAND:
		return BodyPart.is_lost(_limbs_lost, BodyPart.Part.RIGHT_ARM)
	if bone >= Bone.L_UPPER_LEG and bone <= Bone.L_FOOT:
		return BodyPart.is_lost(_limbs_lost, BodyPart.Part.LEFT_LEG)
	if bone >= Bone.R_UPPER_LEG:
		return BodyPart.is_lost(_limbs_lost, BodyPart.Part.RIGHT_LEG)
	return false


func _apply_pose() -> void:
	for bone: int in Bone.size():
		var index: int = _bone_index[bone]
		# Потерянные конечности не анимируются: их всё равно не видно.
		if index == -1 or _is_bone_lost(bone):
			continue
		var rotation_in_model: Quaternion = Quaternion.from_euler(_pose.euler[bone])
		_skeleton.set_bone_pose_rotation(index, _to_parent[bone] * rotation_in_model * _rest_global[bone])
	if _bone_index[Bone.HIPS] != -1:
		_skeleton.set_bone_pose_position(_bone_index[Bone.HIPS], _hips_rest + _pose.hips_offset)
