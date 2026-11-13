extends Node3D
## Обход карты scenes/maps/station.tscn со снимками: общий план сверху без потолка и вид
## от первого лица из каждой комнаты и коридоров.
##
## Запуск: обычный — можно летать по карте (WASD, мышь, Esc — выход);
## с аргументом «-- --shots» сцена сохраняет снимки в res://out/ и закрывается;
## «-- --shots --only=<часть имени>» снимает только подходящие ракурсы.

const SHOTS_ARGUMENT: String = "--shots"
const ONLY_PREFIX: String = "--only="
const OUT_DIR: String = "res://out/"
const FILE_PREFIX: String = "station_"
const IGNORE_MARKER: String = ".gdignore"
const HEADLESS_DISPLAY: String = "headless"
## Высота глаз игрока.
const EYE: float = 1.6
## Сколько кадров ждать перед снимком: тени, SSAO и glow успевают устояться.
const WARMUP_FRAMES: int = 6
const WALK_SPEED: float = 5.0
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = 1.5
## Слой отрисовки, на который переезжает потолок: камера общего плана этот слой не рисует.
## Прятать потолок целиком нельзя — вместе с ним погасли бы светильники внутри ceiling_light.
const CEILING_RENDER_LAYER: int = 2
const DEFAULT_RENDER_LAYER: int = 1
## Группа, которой карта помечает узел с потолком (tools/maps/station.py).
const CEILING_GROUP: StringName = &"station_ceilings"
const WALK_FOV: float = 75.0
const TOP_FOV: float = 50.0
## Для вида строго сверху: север (-Z) — вверх кадра.
const TOP_UP: Vector3 = Vector3(0.0, 0.0, -1.0)

## Ракурсы: имя файла, где стоит камера, куда смотрит; top — вид сверху без потолка.
const SHOTS: Array[Dictionary] = [
	{"name": "01_overview", "position": Vector3(18.0, 46.0, 16.2), "target": Vector3(18.0, 0.0, 16.0), "top": true},
	{"name": "02_top_north_west", "position": Vector3(7.0, 26.0, 7.2), "target": Vector3(7.0, 0.0, 7.0), "top": true},
	{"name": "03_top_north_east", "position": Vector3(27.0, 26.0, 9.2), "target": Vector3(27.0, 0.0, 9.0), "top": true},
	{"name": "04_top_south_west", "position": Vector3(7.0, 26.0, 24.2), "target": Vector3(7.0, 0.0, 24.0), "top": true},
	{"name": "05_top_south_east", "position": Vector3(27.0, 26.0, 24.2), "target": Vector3(27.0, 0.0, 24.0), "top": true},
	{"name": "06_top_meeting", "position": Vector3(16.0, 17.0, 16.2), "target": Vector3(16.0, 0.0, 16.0), "top": true},
	{"name": "10_meeting_from_north_door", "position": Vector3(16.0, EYE, 10.9), "target": Vector3(16.0, 1.0, 16.0)},
	{"name": "11_meeting_from_corner", "position": Vector3(11.2, EYE, 11.6), "target": Vector3(17.0, 1.1, 18.0)},
	{"name": "12_meeting_seat", "position": Vector3(18.77, EYE, 17.15), "target": Vector3(16.0, 1.0, 16.0)},
	{"name": "13_meeting_spawn_camera", "position": Vector3(20.7, 2.55, 20.7), "target": Vector3(16.0, 0.7, 16.0)},
	{"name": "20_office_from_south_door", "position": Vector3(20.0, EYE, 5.2), "target": Vector3(14.0, 1.2, 0.0)},
	{"name": "21_office_from_west_door", "position": Vector3(10.8, EYE, 4.0), "target": Vector3(20.0, 1.2, 1.0)},
	{"name": "22_office_keypad", "position": Vector3(14.6, EYE, 3.4), "target": Vector3(12.4, 1.1, 5.8)},
	{"name": "30_server_from_east_door", "position": Vector3(5.2, EYE, 4.0), "target": Vector3(0.0, 1.2, 7.0)},
	{"name": "31_server_from_south_door", "position": Vector3(0.0, EYE, 9.2), "target": Vector3(3.0, 1.3, 3.0)},
	{"name": "32_server_tasks", "position": Vector3(3.6, EYE, 5.0), "target": Vector3(4.8, 1.1, 9.5)},
	{"name": "40_storage_from_east_door", "position": Vector3(5.2, EYE, 16.0), "target": Vector3(0.0, 1.0, 19.0)},
	{"name": "41_storage_from_north_door", "position": Vector3(0.0, EYE, 10.8), "target": Vector3(3.0, 1.0, 20.0)},
	{"name": "42_storage_rack", "position": Vector3(3.6, EYE, 18.2), "target": Vector3(1.2, 0.9, 21.6)},
	{"name": "50_reactor_from_west_door", "position": Vector3(26.8, EYE, 16.0), "target": Vector3(32.0, 1.4, 16.0)},
	{"name": "51_reactor_from_north_door", "position": Vector3(32.0, EYE, 10.8), "target": Vector3(32.0, 1.2, 17.0)},
	{"name": "52_reactor_panel", "position": Vector3(34.6, EYE, 21.0), "target": Vector3(31.0, 1.2, 17.0)},
	{"name": "53_reactor_docks", "position": Vector3(34.6, EYE, 12.0), "target": Vector3(37.6, 0.9, 16.5)},
	{"name": "60_lab_from_west_door", "position": Vector3(26.8, EYE, 8.0), "target": Vector3(32.0, 1.2, 4.0)},
	{"name": "61_lab_from_south_door", "position": Vector3(32.0, EYE, 9.2), "target": Vector3(27.5, 1.2, 3.5)},
	{"name": "70_airlock_from_door", "position": Vector3(26.8, EYE, 28.0), "target": Vector3(32.0, 1.1, 31.5)},
	{"name": "71_airlock_back", "position": Vector3(33.0, EYE, 29.6), "target": Vector3(27.5, 1.1, 30.5)},
	{"name": "80_cabins_from_door", "position": Vector3(5.2, EYE, 28.0), "target": Vector3(0.0, 1.1, 31.0)},
	{"name": "81_cabins_back", "position": Vector3(-0.8, EYE, 30.6), "target": Vector3(4.5, 1.2, 28.0)},
	{"name": "90_corridor_north", "position": Vector3(7.0, EYE, 8.2), "target": Vector3(26.0, 1.7, 8.0)},
	{"name": "91_corridor_north_back", "position": Vector3(25.0, EYE, 8.0), "target": Vector3(6.0, 1.7, 8.0)},
	{"name": "92_corridor_west", "position": Vector3(8.0, EYE, 10.6), "target": Vector3(8.0, 1.7, 26.0)},
	{"name": "93_corridor_east", "position": Vector3(24.0, EYE, 21.4), "target": Vector3(24.0, 1.7, 6.0)},
	{"name": "94_corridor_south", "position": Vector3(25.0, EYE, 24.0), "target": Vector3(6.0, 1.6, 24.0)},
	{"name": "95_corridor_south_windows", "position": Vector3(12.0, EYE, 23.0), "target": Vector3(20.0, 1.5, 25.6)},
	{"name": "96_stub_north", "position": Vector3(8.0, EYE, 8.6), "target": Vector3(8.0, 1.8, 2.0)},
	{"name": "97_stub_cabins", "position": Vector3(8.6, EYE, 23.2), "target": Vector3(7.4, 1.8, 30.0)},
	{"name": "98_stub_airlock", "position": Vector3(23.4, EYE, 23.2), "target": Vector3(24.6, 1.8, 30.0)},
	{"name": "detail_door_sign", "position": Vector3(15.2, EYE, 12.6), "target": Vector3(16.0, 2.6, 10.0)},
	{"name": "detail_table", "position": Vector3(16.0, 1.0, 19.2), "target": Vector3(16.0, 0.8, 16.0)},
	{"name": "detail_corridor_wiring", "position": Vector3(15.4, EYE, 23.7), "target": Vector3(16.2, 1.3, 22.1)},
	{"name": "detail_cabins_stand", "position": Vector3(1.6, EYE, 31.6), "target": Vector3(0.6, 0.9, 33.6)},
	{"name": "detail_airlock_keypad", "position": Vector3(31.6, EYE, 31.0), "target": Vector3(33.6, 1.0, 32.2)},
	{"name": "detail_lab_stand", "position": Vector3(31.4, EYE, 4.6), "target": Vector3(33.0, 1.0, 2.6)},
	{"name": "detail_reactor_calibrator", "position": Vector3(28.6, EYE, 19.2), "target": Vector3(26.5, 1.0, 20.8)},
	{"name": "detail_storage_wiring", "position": Vector3(0.4, EYE, 14.8), "target": Vector3(-1.9, 1.2, 16.4)},
]

var _yaw: float = 0.0
var _pitch: float = 0.0

@onready var _camera: Camera3D = $Camera


func _ready() -> void:
	var shots_requested: bool = SHOTS_ARGUMENT in OS.get_cmdline_user_args()
	for ceilings: Node in get_tree().get_nodes_in_group(CEILING_GROUP):
		ceilings.propagate_call(&"set_layer_mask_value", [DEFAULT_RENDER_LAYER, false])
		ceilings.propagate_call(&"set_layer_mask_value", [CEILING_RENDER_LAYER, true])
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		# Без видеокарты сцена только загружается: ни снимков, ни покадровой работы.
		set_process(false)
		set_process_unhandled_input(false)
		if shots_requested:
			print("STATION TOUR: снимки в режиме headless недоступны")
			get_tree().quit(1)
		return
	# У карты своя камера для игроков без аватара — обход смотрит своей.
	_camera.make_current()
	if shots_requested:
		set_process(false)
		set_process_unhandled_input(false)
		_take_shots()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x


func _process(delta: float) -> void:
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var direction: Vector3 = Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)
	_camera.position += direction * WALK_SPEED * delta
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed(&"ui_cancel"):
		get_tree().quit(0)


func _take_shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Пустой .gdignore: редактор не импортирует снимки как текстуры проекта.
	var marker: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + IGNORE_MARKER), FileAccess.WRITE)
	if marker != null:
		marker.close()
	var only: String = _shot_filter()
	for shot: Dictionary in SHOTS:
		var shot_name: String = shot["name"]
		if only != "" and not shot_name.contains(only):
			continue
		var camera_position: Vector3 = shot["position"]
		var target: Vector3 = shot["target"]
		var is_top: bool = shot.get("top", false)
		_camera.fov = TOP_FOV if is_top else WALK_FOV
		_camera.look_at_from_position(camera_position, target, TOP_UP if is_top else Vector3.UP)
		_camera.set_cull_mask_value(CEILING_RENDER_LAYER, not is_top)
		for frame: int in WARMUP_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = OUT_DIR + FILE_PREFIX + shot_name + ".png"
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("STATION TOUR: сохранён %s (объектов в кадре %d, вызовов отрисовки %d)" % [path,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit(0)


## «--only=<часть имени>» после «--shots» оставляет только подходящие ракурсы.
func _shot_filter() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(ONLY_PREFIX):
			return argument.trim_prefix(ONLY_PREFIX)
	return ""
