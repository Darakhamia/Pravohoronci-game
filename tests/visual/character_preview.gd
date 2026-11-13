extends Node3D
## Просмотр персонажа: восемь игрушек в цветах игроков и в разных состояниях.
##
## В редакторе (F6) сцена крутит состояния по кругу: конечности отлетают, мертвец падает,
## потом всё возвращается. С аргументом --shots снимает кадры в res://out/ и выходит:
##   godot --rendering-driver vulkan --fixed-fps 30 res://tests/visual/character_preview.tscn -- --shots
## (--fixed-fps делает шаг времени постоянным, чтобы кадры не зависели от скорости рендера).

enum Role { IDLE, RUN, PISTOL, KNIFE, ONE_ARM, ONE_LEG, CRAWL, DEAD }

const VISUALS_SCENE: PackedScene = preload("res://scenes/characters/player_visuals.tscn")
const VIEWMODEL_SCENE: PackedScene = preload("res://scenes/characters/viewmodel.tscn")
const PISTOL_SCENE: PackedScene = preload("res://assets/models/weapons/pistol.glb")
const KNIFE_SCENE: PackedScene = preload("res://assets/models/weapons/knife.glb")

const SHOTS_ARGUMENT: String = "--shots"
const OUT_DIR: String = "res://out"
const ACTOR_SPACING: float = 1.15
const RUN_SPEED: float = 5.0
const WALK_SPEED: float = 1.6
const LIMP_SPEED: float = 2.5
const CRAWL_SPEED: float = 1.0
const JUMP_VELOCITY: float = 5.5
const GRAVITY: float = 15.0
## Цикл показа в редакторе, секунды.
const LOOP_SEC: float = 9.0
const LOOP_LOSE_AT: float = 2.0
const LOOP_ATTACK_EVERY: float = 1.1
const AIM_SWEEP_RATE: float = 0.8
const AIM_SWEEP: float = 0.45
const ROLE_NAMES: Dictionary[int, String] = {
	Role.IDLE: "Стоит",
	Role.RUN: "Бежит",
	Role.PISTOL: "Бластер",
	Role.KNIFE: "Нож",
	Role.ONE_ARM: "Без руки",
	Role.ONE_LEG: "Без ноги",
	Role.CRAWL: "Ползёт",
	Role.DEAD: "Труп",
}

var _actors: Array[PlayerVisuals] = []
var _viewer_body: PlayerVisuals = null
var _viewmodel: Viewmodel = null
var _time: float = 0.0
var _jump_velocity: float = 0.0
var _limbs_gone: bool = false
var _next_attack: float = 0.0
var _shots_mode: bool = false

@onready var _actor_root: Node3D = $Actors
@onready var _stage_camera: Camera3D = $StageCamera
@onready var _viewer: Node3D = $Viewer
@onready var _view_camera: Camera3D = $Viewer/ViewCamera


func _ready() -> void:
	_spawn_actors()
	_spawn_viewer()
	_shots_mode = SHOTS_ARGUMENT in OS.get_cmdline_user_args()
	if _shots_mode:
		_take_shots()


func _process(delta: float) -> void:
	_time += delta
	_drive_actors(delta)
	if not _shots_mode:
		_run_loop()


func _spawn_actors() -> void:
	var count: int = Role.size()
	for role: int in count:
		var actor: PlayerVisuals = VISUALS_SCENE.instantiate() as PlayerVisuals
		_actor_root.add_child(actor)
		# Актёры стоят в ряд лицом к камере (перёд модели — -Z, камера со стороны +Z).
		actor.position = Vector3((role - (count - 1) * 0.5) * ACTOR_SPACING, 0.0, 0.0)
		actor.rotation.y = PI
		actor.set_body_color(PlayerPalette.color(role))
		actor.set_display_name(ROLE_NAMES[role])
		_actors.append(actor)
	_actors[Role.PISTOL].set_held_item(PISTOL_SCENE)
	_actors[Role.KNIFE].set_held_item(KNIFE_SCENE)
	_actors[Role.ONE_ARM].set_held_item(PISTOL_SCENE)


## Зритель от первого лица: тело скрыто, в камере — руки с предметом.
func _spawn_viewer() -> void:
	_viewer_body = VISUALS_SCENE.instantiate() as PlayerVisuals
	_viewer.add_child(_viewer_body)
	_viewer_body.set_body_color(PlayerPalette.color(Role.PISTOL))
	_viewer_body.set_first_person(true)
	_viewmodel = VIEWMODEL_SCENE.instantiate() as Viewmodel
	_view_camera.add_child(_viewmodel)
	_viewmodel.set_body_color(PlayerPalette.color(Role.PISTOL))


## Скорость «на беговой дорожке»: актёр перебирает ногами на месте.
func _treadmill(actor: PlayerVisuals, speed: float) -> void:
	actor.set_velocity(actor.global_basis * Vector3(0.0, 0.0, -speed))


func _drive_actors(delta: float) -> void:
	_treadmill(_actors[Role.RUN], RUN_SPEED)
	_treadmill(_actors[Role.ONE_ARM], WALK_SPEED)
	_treadmill(_actors[Role.ONE_LEG], LIMP_SPEED if _limbs_gone else WALK_SPEED)
	_treadmill(_actors[Role.CRAWL], CRAWL_SPEED if _limbs_gone else RUN_SPEED)
	var aim: float = sin(_time * AIM_SWEEP_RATE) * AIM_SWEEP
	_actors[Role.PISTOL].set_look_pitch(aim)
	_actors[Role.KNIFE].set_look_pitch(-aim * 0.5)
	# Прыжок первого актёра: та же баллистика, что у игрока.
	var jumper: PlayerVisuals = _actors[Role.IDLE]
	if jumper.position.y > 0.0 or _jump_velocity > 0.0:
		_jump_velocity -= GRAVITY * delta
		jumper.position.y = maxf(jumper.position.y + _jump_velocity * delta, 0.0)
		if jumper.position.y <= 0.0:
			_jump_velocity = 0.0
	jumper.set_velocity(Vector3(0.0, _jump_velocity, 0.0))


func _jump() -> void:
	_jump_velocity = JUMP_VELOCITY


func _lose_limbs(with_effect: bool) -> void:
	_limbs_gone = true
	_actors[Role.ONE_ARM].set_limbs_lost(BodyPart.bit(BodyPart.Part.RIGHT_ARM), with_effect)
	_actors[Role.ONE_LEG].set_limbs_lost(BodyPart.bit(BodyPart.Part.LEFT_LEG), with_effect)
	_actors[Role.CRAWL].set_limbs_lost(
			BodyPart.bit(BodyPart.Part.LEFT_LEG) | BodyPart.bit(BodyPart.Part.RIGHT_LEG), with_effect)
	_actors[Role.DEAD].set_dead(true)


func _restore_limbs() -> void:
	_limbs_gone = false
	for actor: PlayerVisuals in _actors:
		actor.set_limbs_lost(0)
		actor.set_dead(false)


func _attack_all() -> void:
	for role: int in [Role.IDLE, Role.PISTOL, Role.KNIFE, Role.ONE_ARM]:
		_actors[role].play_attack()


## Бесконечный показ для человека в редакторе.
func _run_loop() -> void:
	var loop_time: float = fmod(_time, LOOP_SEC)
	if loop_time < LOOP_LOSE_AT and _limbs_gone:
		_restore_limbs()
		_jump()
	elif loop_time >= LOOP_LOSE_AT and not _limbs_gone:
		_lose_limbs(true)
	if _time >= _next_attack:
		_next_attack = _time + LOOP_ATTACK_EVERY
		_attack_all()


# ----------------------------------------------------------------------------------------------
# Съёмка кадров
# ----------------------------------------------------------------------------------------------

func _wait(seconds: float) -> void:
	var until: float = _time + seconds
	while _time < until:
		await get_tree().process_frame


func _shoot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = OUT_DIR.path_join("%s.png" % shot_name)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", path)


## Папка с кадрами не должна попадать в импорт Godot: в ней лежит пустой .gdignore.
func _prepare_out_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var marker: FileAccess = FileAccess.open(OUT_DIR.path_join(".gdignore"), FileAccess.WRITE)
	if marker != null:
		marker.close()


## Ставит камеру на актёров roles: смотрит в середину между ними с расстояния distance,
## под углом yaw_deg вокруг них (0 — спереди, 90 — слева от актёров, 180 — сзади).
## solo = true прячет остальных, чтобы не лезли в кадр.
func _frame(roles: Array[Role], distance: float, yaw_deg: float = 0.0, eye_height: float = 1.3,
		target_height: float = 0.95, solo: bool = false) -> void:
	var middle: Vector3 = Vector3.ZERO
	for role: Role in roles:
		middle += _actors[role].position / roles.size()
	for role: int in _actors.size():
		_actors[role].visible = not solo or roles.has(role as Role)
	var yaw: float = deg_to_rad(yaw_deg)
	var eye: Vector3 = middle + Vector3(sin(yaw) * distance, eye_height, cos(yaw) * distance)
	_stage_camera.make_current()
	_stage_camera.look_at_from_position(eye, middle + Vector3(0.0, target_height, 0.0))


func _take_shots() -> void:
	_prepare_out_dir()
	await _wait(1.0)
	await _shoot("01_lineup")
	_frame([Role.IDLE, Role.RUN], 3.3, 20.0)
	await _wait(0.2)
	await _shoot("02_idle_run")
	_frame([Role.RUN], 3.4, 90.0, 1.1, 0.95, true)
	await _shoot("03_run_side")
	await _wait(0.12)
	await _shoot("04_run_side_next_step")
	_frame([Role.IDLE, Role.RUN], 3.3, 150.0, 1.6, 0.95, true)
	await _shoot("05_idle_run_back")
	_frame([Role.PISTOL, Role.KNIFE], 3.2, -20.0)
	await _shoot("06_pistol_knife")
	_frame([Role.PISTOL, Role.KNIFE], 2.0, -12.0, 1.45, 1.25)
	await _shoot("06_pistol_knife_close")
	_frame([Role.PISTOL, Role.KNIFE], 3.2, -20.0)
	_attack_all()
	await _wait(0.14)
	await _shoot("07_pistol_knife_attack")
	_frame([Role.PISTOL, Role.KNIFE], 3.6, 78.0, 1.2, 1.0, true)
	await _wait(0.6)
	await _shoot("08_pistol_knife_side")
	_actors[Role.IDLE].play_attack()
	_frame([Role.IDLE], 3.0, 60.0, 1.2, 1.0, true)
	await _wait(0.17)
	await _shoot("09_punch")
	await _wait(0.5)
	_jump()
	await _wait(0.25)
	_frame([Role.IDLE], 4.2, 40.0, 1.9, 1.5, true)
	await _shoot("10_jump")
	await _wait(0.8)
	# Конечности отлетают, мертвец падает.
	_frame([Role.ONE_ARM, Role.ONE_LEG, Role.CRAWL, Role.DEAD], 5.2, 0.0, 1.5)
	_lose_limbs(true)
	await _wait(0.2)
	await _shoot("11_limbs_pop")
	await _wait(0.25)
	await _shoot("12_limbs_fly")
	await _wait(2.2)
	await _shoot("13_limbs_settled")
	_frame([Role.ONE_ARM, Role.ONE_LEG], 3.3, 15.0)
	await _shoot("14_one_arm_one_leg")
	_actors[Role.ONE_ARM].play_attack()
	_frame([Role.ONE_LEG], 3.4, 75.0, 1.2, 0.95, true)
	await _wait(0.2)
	await _shoot("15_hop_side")
	_frame([Role.CRAWL], 2.6, 55.0, 0.9, 0.35, true)
	await _shoot("16_crawl")
	await _wait(0.2)
	_frame([Role.CRAWL], 2.8, 90.0, 0.5, 0.3, true)
	await _shoot("17_crawl_side")
	_frame([Role.DEAD], 2.9, 35.0, 1.9, 0.2, true)
	await _shoot("18_dead")
	_frame([Role.DEAD], 3.0, 100.0, 0.6, 0.2, true)
	await _shoot("19_dead_side")
	_frame([Role.PISTOL, Role.ONE_LEG], 7.0, 0.0, 2.4, 0.8)
	await _shoot("20_lineup_after")
	await _take_view_shots()
	get_tree().quit(0)


## Вид от первого лица: бластер, выстрел, нож, выпад, пустые руки и удар кулаком.
func _take_view_shots() -> void:
	_view_camera.make_current()
	_viewmodel.set_held_item(PISTOL_SCENE)
	await _wait(0.8)
	await _shoot("30_view_pistol")
	_viewmodel.play_attack()
	await _wait(0.05)
	await _shoot("31_view_pistol_recoil")
	_viewmodel.set_held_item(KNIFE_SCENE)
	await _wait(0.8)
	await _shoot("32_view_knife")
	_viewmodel.play_attack()
	await _wait(0.16)
	await _shoot("33_view_knife_stab")
	_viewmodel.set_limbs_lost(BodyPart.bit(BodyPart.Part.RIGHT_ARM))
	await _wait(0.8)
	await _shoot("34_view_knife_left_hand")
	_viewmodel.set_limbs_lost(0)
	_viewmodel.set_held_item(null)
	await _wait(0.8)
	await _shoot("35_view_empty")
	_viewmodel.play_attack()
	await _wait(0.17)
	await _shoot("36_view_punch")
