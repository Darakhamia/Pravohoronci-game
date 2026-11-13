extends Node3D
## Просмотр персонажа: восемь членов экипажа в цветах игроков и в разных состояниях.
##
## В редакторе (F6) сцена крутит состояния по кругу: конечности отлетают, мертвец падает,
## потом всё возвращается. С аргументом --shots снимает кадры в res://out/ и выходит:
##   godot --rendering-driver vulkan --fixed-fps 30 res://tests/visual/character_preview.tscn -- --shots
## (--fixed-fps делает шаг времени постоянным, чтобы кадры не зависели от скорости рендера).
## Снять только часть кадров: --only=lineup,run (группы — см. SHOT_GROUPS); --draft — без
## отражений и свечения, когда важны только позы.

enum Role { IDLE, RUN, PISTOL, KNIFE, ONE_ARM, ONE_LEG, CRAWL, DEAD }

const VISUALS_SCENE: PackedScene = preload("res://scenes/characters/player_visuals.tscn")
const VIEWMODEL_SCENE: PackedScene = preload("res://scenes/characters/viewmodel.tscn")
const PISTOL_SCENE: PackedScene = preload("res://assets/models/weapons/pistol.glb")
const KNIFE_SCENE: PackedScene = preload("res://assets/models/weapons/knife.glb")

const SHOTS_ARGUMENT: String = "--shots"
const ONLY_ARGUMENT: String = "--only="
## Черновая съёмка без дорогих эффектов экрана: быстрее, когда проверяются только позы.
const DRAFT_ARGUMENT: String = "--draft"
const OUT_DIR: String = "res://out"
const SHOT_GROUPS: PackedStringArray = [
	"lineup", "portrait", "run", "aim", "knife", "limbs", "hop", "crawl", "dead", "view", "weapons",
]
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
const LOOP_ATTACK_EVERY: float = 1.3
const AIM_SWEEP_RATE: float = 0.8
const AIM_SWEEP: float = 0.45
## Обычный объектив сцены и длиннофокусный для портретов.
const WIDE_FOV: float = 50.0
const PORTRAIT_FOV: float = 28.0
const ROLE_NAMES: Dictionary[int, String] = {
	Role.IDLE: "Стоит",
	Role.RUN: "Бежит",
	Role.PISTOL: "Пистолет",
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
## Пока true, все актёры стоят смирно (общий план) и не целятся.
var _at_ease: bool = false
var _aim_pitch: float = NAN

@onready var _actor_root: Node3D = $Actors
@onready var _stage_camera: Camera3D = $StageCamera
@onready var _viewer: Node3D = $Viewer
@onready var _view_camera: Camera3D = $Viewer/ViewCamera
@onready var _pedestal: Node3D = $Pedestal
@onready var _world_environment: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	_spawn_actors()
	_spawn_viewer()
	_shots_mode = SHOTS_ARGUMENT in OS.get_cmdline_user_args()
	if DRAFT_ARGUMENT in OS.get_cmdline_user_args():
		var environment: Environment = _world_environment.environment
		environment.ssr_enabled = false
		environment.ssil_enabled = false
		environment.glow_enabled = false
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
	# Руки видит только камера зрителя: в кадрах со сцены их быть не должно.
	_viewmodel.visible = false


## Скорость «на беговой дорожке»: актёр перебирает ногами на месте.
func _treadmill(actor: PlayerVisuals, speed: float) -> void:
	actor.set_velocity(actor.global_basis * Vector3(0.0, 0.0, -speed))


func _drive_actors(delta: float) -> void:
	if _at_ease:
		for actor: PlayerVisuals in _actors:
			actor.set_velocity(Vector3.ZERO)
			actor.set_look_pitch(0.0)
		return
	_treadmill(_actors[Role.RUN], RUN_SPEED)
	_treadmill(_actors[Role.ONE_ARM], WALK_SPEED)
	_treadmill(_actors[Role.ONE_LEG], LIMP_SPEED if _limbs_gone else WALK_SPEED)
	_treadmill(_actors[Role.CRAWL], CRAWL_SPEED if _limbs_gone else RUN_SPEED)
	var aim: float = sin(_time * AIM_SWEEP_RATE) * AIM_SWEEP if is_nan(_aim_pitch) else _aim_pitch
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
		target_height: float = 0.95, solo: bool = false, fov: float = WIDE_FOV) -> void:
	var middle: Vector3 = Vector3.ZERO
	for role: Role in roles:
		middle += _actors[role].position / roles.size()
	for role: int in _actors.size():
		_actors[role].visible = not solo or roles.has(role as Role)
	var yaw: float = deg_to_rad(yaw_deg)
	var eye: Vector3 = middle + Vector3(sin(yaw) * distance, eye_height, cos(yaw) * distance)
	_stage_camera.fov = fov
	_stage_camera.make_current()
	_stage_camera.look_at_from_position(eye, middle + Vector3(0.0, target_height, 0.0))


## Группы кадров, которые просили снять (все, если --only не задан).
func _wanted_groups() -> PackedStringArray:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(ONLY_ARGUMENT):
			return argument.trim_prefix(ONLY_ARGUMENT).split(",", false)
	return SHOT_GROUPS


func _take_shots() -> void:
	_prepare_out_dir()
	var wanted: PackedStringArray = _wanted_groups()
	# Первые кадры уходят на прогрев: зонд отражений, тени, сглаживание поз.
	_at_ease = true
	await _wait(1.2)
	if wanted.has("lineup"):
		await _shoot_lineup()
	if wanted.has("portrait"):
		await _shoot_portrait()
	_at_ease = false
	if wanted.has("run"):
		await _shoot_run()
	if wanted.has("aim"):
		await _shoot_aim()
	if wanted.has("knife"):
		await _shoot_knife()
	if wanted.has("limbs") or wanted.has("hop") or wanted.has("crawl") or wanted.has("dead"):
		await _shoot_limbs(wanted)
	if wanted.has("view"):
		await _shoot_view()
	if wanted.has("weapons"):
		await _shoot_weapons()
	get_tree().quit(0)


func _shoot_lineup() -> void:
	_stage_camera.fov = WIDE_FOV
	_frame([Role.KNIFE, Role.ONE_ARM], 6.6, 0.0, 1.75, 1.0)
	await _shoot("01_lineup")
	_frame([Role.PISTOL, Role.KNIFE, Role.ONE_ARM], 3.4, 24.0, 1.45, 1.05)
	await _shoot("02_lineup_close")
	_frame([Role.KNIFE, Role.ONE_ARM], 6.2, 180.0, 1.9, 1.0)
	await _shoot("03_lineup_back")
	# С пятнадцати метров цвет игрока должен читаться так же уверенно.
	_frame([Role.KNIFE, Role.ONE_ARM], 15.0, 0.0, 1.7, 1.0)
	await _shoot("03_lineup_far")


func _shoot_portrait() -> void:
	_frame([Role.IDLE], 2.3, -22.0, 1.56, 1.47, false, PORTRAIT_FOV)
	await _shoot("04_portrait")
	_frame([Role.ONE_LEG], 1.9, 18.0, 1.5, 1.42, false, PORTRAIT_FOV)
	await _shoot("05_portrait_blue")
	_frame([Role.RUN], 3.6, 30.0, 1.2, 0.93, true, 36.0)
	await _shoot("06_full_body")
	_frame([Role.RUN], 3.6, 152.0, 1.35, 0.95, true, 36.0)
	await _shoot("07_back")
	_frame([Role.RUN], 2.2, 170.0, 1.45, 1.28, true, PORTRAIT_FOV)
	await _shoot("08_backpack")
	_frame([Role.KNIFE], 2.3, 90.0, 1.1, 0.95, true, 40.0)
	await _shoot("09_side")
	_frame([Role.IDLE], 1.5, 40.0, 0.55, 0.3, true, 40.0)
	await _shoot("10_boots")


func _shoot_run() -> void:
	await _wait(1.0)
	_frame([Role.RUN], 3.5, 90.0, 1.05, 0.95, true)
	for index: int in 4:
		await _shoot("11_run_side_%d" % (index + 1))
		await _wait(0.16)
	_frame([Role.RUN], 3.4, 28.0, 1.2, 0.95, true)
	await _shoot("12_run_front")
	await _wait(0.16)
	await _shoot("12_run_front_2")
	_frame([Role.ONE_ARM], 3.4, 62.0, 1.15, 0.95, true)
	await _shoot("13_walk")
	_jump()
	await _wait(0.25)
	_frame([Role.IDLE], 4.0, 40.0, 1.8, 1.5, true)
	await _shoot("14_jump")
	await _wait(0.9)


func _shoot_aim() -> void:
	_aim_pitch = 0.0
	await _wait(0.6)
	_frame([Role.PISTOL], 2.9, -32.0, 1.45, 1.1, true)
	await _shoot("15_aim")
	_frame([Role.PISTOL], 2.6, 88.0, 1.35, 1.15, true)
	await _shoot("16_aim_side")
	_frame([Role.PISTOL], 1.25, 148.0, 1.72, 1.36, true, 60.0)
	await _shoot("17_aim_over_shoulder")
	_frame([Role.PISTOL], 1.3, -38.0, 1.5, 1.36, true, 40.0)
	await _shoot("18_aim_hands")
	_actors[Role.PISTOL].play_attack()
	_frame([Role.PISTOL], 2.6, 88.0, 1.35, 1.15, true)
	await _wait(0.07)
	await _shoot("19_recoil")
	_aim_pitch = 0.55
	await _wait(0.6)
	await _shoot("20_aim_up")
	_aim_pitch = -0.6
	await _wait(0.6)
	await _shoot("21_aim_down")
	_aim_pitch = NAN


func _shoot_knife() -> void:
	_aim_pitch = 0.0
	await _wait(0.5)
	_frame([Role.KNIFE], 2.8, -28.0, 1.3, 1.0, true)
	await _shoot("22_knife")
	_frame([Role.KNIFE], 1.3, 30.0, 1.1, 0.98, true, 40.0)
	await _shoot("23_knife_hand")
	_frame([Role.KNIFE], 2.9, 80.0, 1.25, 1.0, true)
	_actors[Role.KNIFE].play_attack()
	await _wait(0.08)
	await _shoot("24_stab_windup")
	await _wait(0.1)
	await _shoot("25_stab")
	_actors[Role.IDLE].play_attack()
	_frame([Role.IDLE], 2.9, 60.0, 1.25, 1.05, true)
	await _wait(0.18)
	await _shoot("26_punch")
	await _wait(0.5)
	_aim_pitch = NAN


func _shoot_limbs(wanted: PackedStringArray) -> void:
	await _wait(0.4)
	# Конечности отлетают, мертвец оседает.
	_frame([Role.ONE_ARM, Role.ONE_LEG, Role.CRAWL, Role.DEAD], 5.0, 0.0, 1.5)
	if wanted.has("limbs"):
		_frame([Role.ONE_ARM], 2.5, -20.0, 1.5, 1.15, true)
	_lose_limbs(true)
	await _wait(0.07)
	if wanted.has("limbs"):
		await _shoot("27_arm_lost_sparks")
		await _wait(0.1)
		await _shoot("28_arm_lost_flying")
	if wanted.has("dead"):
		_frame([Role.DEAD], 3.4, 50.0, 1.3, 0.75, true)
		await _wait(0.25)
		await _shoot("36_collapse_1")
		await _wait(0.2)
		await _shoot("36_collapse_2")
		await _wait(0.2)
		await _shoot("36_collapse_3")
	await _wait(2.0)
	if wanted.has("limbs"):
		_frame([Role.ONE_ARM, Role.ONE_LEG, Role.CRAWL, Role.DEAD], 5.0, 0.0, 1.5)
		await _shoot("29_limbs_settled")
		_frame([Role.ONE_ARM], 1.25, -42.0, 1.5, 1.36, true, 40.0)
		await _shoot("30_stump")
		_frame([Role.ONE_ARM], 2.8, -25.0, 1.4, 1.05, true)
		await _shoot("31_one_arm_aim")
	if wanted.has("hop"):
		_frame([Role.ONE_LEG], 3.3, 75.0, 1.15, 0.95, true)
		for index: int in 3:
			await _shoot("32_hop_%d" % (index + 1))
			await _wait(0.2)
		_frame([Role.ONE_LEG], 3.0, 15.0, 1.2, 0.95, true)
		await _shoot("33_hop_front")
	if wanted.has("crawl"):
		_frame([Role.CRAWL], 2.5, 55.0, 0.9, 0.35, true)
		await _shoot("34_crawl")
		await _wait(0.25)
		_frame([Role.CRAWL], 2.7, 90.0, 0.5, 0.3, true)
		await _shoot("35_crawl_side")
	if wanted.has("dead"):
		_frame([Role.DEAD], 2.9, 35.0, 1.7, 0.3, true)
		await _shoot("37_dead")
		_frame([Role.DEAD], 3.0, 100.0, 0.55, 0.3, true)
		await _shoot("38_dead_side")
		_frame([Role.DEAD], 2.6, -150.0, 1.5, 0.3, true)
		await _shoot("39_dead_back")
	_restore_limbs()
	_frame([Role.KNIFE, Role.ONE_ARM], 6.6, 0.0, 1.75, 1.0)


## Вид от первого лица: пистолет, выстрел, нож, выпад, пустые руки и удар кулаком.
func _shoot_view() -> void:
	_frame([Role.KNIFE, Role.ONE_ARM], 6.6, 0.0, 1.75, 1.0)
	_view_camera.make_current()
	_viewmodel.visible = true
	_viewmodel.set_held_item(PISTOL_SCENE)
	await _wait(1.0)
	await _shoot("40_view_pistol")
	_viewmodel.play_attack()
	await _wait(0.05)
	await _shoot("41_view_pistol_recoil")
	_viewmodel.set_limbs_lost(BodyPart.bit(BodyPart.Part.LEFT_ARM))
	await _wait(0.8)
	await _shoot("42_view_pistol_one_hand")
	_viewmodel.set_limbs_lost(BodyPart.bit(BodyPart.Part.RIGHT_ARM))
	await _wait(0.9)
	await _shoot("43_view_pistol_left_hand")
	_viewmodel.set_limbs_lost(0)
	_viewmodel.set_held_item(KNIFE_SCENE)
	await _wait(1.0)
	await _shoot("44_view_knife")
	_viewmodel.play_attack()
	await _wait(0.19)
	await _shoot("45_view_knife_stab")
	_viewmodel.set_held_item(null)
	await _wait(1.0)
	await _shoot("46_view_empty")
	_viewmodel.play_attack()
	await _wait(0.18)
	await _shoot("47_view_punch")
	_viewmodel.set_velocity(Vector3(0.0, 0.0, -RUN_SPEED))
	await _wait(0.5)
	await _shoot("48_view_empty_run")
	_viewmodel.set_velocity(Vector3.ZERO)
	_viewmodel.visible = false
	_stage_camera.make_current()


## Оружие крупным планом на подставке.
func _shoot_weapons() -> void:
	for actor: PlayerVisuals in _actors:
		actor.visible = false
	_pedestal.visible = true
	var pistol: Node3D = PISTOL_SCENE.instantiate() as Node3D
	var knife: Node3D = KNIFE_SCENE.instantiate() as Node3D
	_pedestal.add_child(pistol)
	_pedestal.add_child(knife)
	pistol.position = Vector3(-0.13, 1.13, 0.0)
	pistol.rotation = Vector3(0.0, deg_to_rad(-90.0), 0.0)
	knife.position = Vector3(0.2, 1.08, 0.02)
	knife.rotation = Vector3(0.0, deg_to_rad(-90.0), deg_to_rad(8.0))
	_stage_camera.fov = 24.0
	_stage_camera.make_current()
	_stage_camera.look_at_from_position(Vector3(-0.25, 1.36, 1.0), Vector3(0.06, 1.1, 0.0))
	await _wait(0.3)
	await _shoot("50_weapons")
	_stage_camera.look_at_from_position(Vector3(-0.75, 1.32, -0.62), Vector3(0.0, 1.1, 0.0))
	await _shoot("51_weapons_back")
	_stage_camera.look_at_from_position(Vector3(-0.28, 1.24, 0.5), Vector3(-0.07, 1.125, 0.0))
	await _shoot("52_pistol_close")
	_stage_camera.look_at_from_position(Vector3(0.1, 1.24, 0.5), Vector3(0.27, 1.085, 0.0))
	await _shoot("53_knife_close")
	pistol.queue_free()
	knife.queue_free()
	_pedestal.visible = false
	for actor: PlayerVisuals in _actors:
		actor.visible = true
