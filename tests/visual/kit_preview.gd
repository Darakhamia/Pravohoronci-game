extends Node3D
## Демонстрационный уголок станции из набора scenes/maps/kit и реквизита scenes/maps/props:
## офис с переговорным столом, коридор и реакторная. Сцену собирает tools/assets/environment_preview.py.
##
## Запуск: обычный — можно ходить (WASD, мышь, Esc — выход);
## с аргументом «-- --shots» сцена сохраняет снимки в res://out/ и закрывается.
##
## РЕЦЕПТ СВЕТА (его же повторяй на боевой карте)
## 1. Окружение resources/maps/station_environment.tres даёт основу: ровный холодный ambient (тени не
##    чёрные), SSAO (объём в углах и под мебелью), glow (ореол вокруг всего светящегося), лёгкий туман
##    и космос с планетой за окнами.
## 2. Потолочная панель ceiling_light уже светит сама: в её префабе лежит SpotLight3D БЕЗ теней, который
##    смотрит строго вниз (energy 2,2, угол 33°, range 4,2, тёплый белый). Пятно на полу — круг радиусом 2 м,
##    он не выходит за клетку 4 x 4 м, поэтому свет не пролезает под стеной в соседнюю комнату.
##    Светлая комната — панель в каждой клетке; мрачная — в каждой второй.
## 3. Тени и объём даёт ОДИН OmniLight3D с тенями на комнату до 8 x 8 м (на большую — по одному на блок
##    8 x 8 м): под потолком в центре, y = 2,6–2,95, energy 1,2–1,5, omni_range 9–9,5, omni_attenuation 1,
##    shadow_bias 0,06. Цвет: тёплый белый (1, 0.95, 0.86) в жилых комнатах, холодный (0.86, 0.93, 1)
##    в технических. В коридоре — один такой на каждые 8 м, energy 1,2, omni_range 7,5.
## 4. Тени обязательны у любого источника, который достаёт до стены: свет без теней проходит сквозь стены.
##    Без теней ставь только прожекторы панелей (п. 2) и цветные акценты, у которых omni_range меньше
##    расстояния до ближайшей стены.
## 5. Цветной акцент — один на комнату. В реакторной это оранжевый OmniLight3D в центре ядра
##    (energy 3, omni_range 3,5, omni_attenuation 0,8, без теней: до стен он не достаёт).
## 6. Итого на клетку 4 x 4 м: до одного прожектора без теней (дешёвые, их можно десятки) и 0,25–0,5
##    источника с тенями. На карту из 8–10 комнат выходит 12–18 источников с тенями; геометрия неподвижна,
##    поэтому карты теней перерисовываются только там, где ходят игроки.

const SHOTS_ARGUMENT: String = "--shots"
const OUT_DIR: String = "res://out/"
const IGNORE_MARKER: String = ".gdignore"
const HEADLESS_DISPLAY: String = "headless"
## Высота глаз игрока.
const EYE_HEIGHT: float = 1.6
## Сколько кадров ждать перед снимком: тени, SSAO и glow успевают устояться.
const WARMUP_FRAMES: int = 6
const WALK_SPEED: float = 4.0
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = 1.5
## Слой отрисовки, на который переезжает потолок: камера общего плана этот слой не рисует.
## Прятать потолок целиком нельзя — вместе с ним погасли бы светильники внутри ceiling_light.
const CEILING_RENDER_LAYER: int = 2
const DEFAULT_RENDER_LAYER: int = 1
const WALK_FOV: float = 75.0
const OVERVIEW_FOV: float = 50.0

## Ракурсы для снимков: имя файла, где стоит камера, куда смотрит, угол обзора, прятать ли потолок.
const SHOTS: Array[Dictionary] = [
	{"name": "01_overview", "position": Vector3(10.0, 16.0, 13.5), "target": Vector3(10.0, 0.0, 2.4), "fov": OVERVIEW_FOV, "hide_ceiling": true},
	{"name": "02_office_from_door", "position": Vector3(5.2, EYE_HEIGHT, 0.4), "target": Vector3(0.5, 1.2, 2.6), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "03_office_window", "position": Vector3(3.6, EYE_HEIGHT, 5.0), "target": Vector3(0.6, 1.3, -2.0), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "04_office_to_corridor", "position": Vector3(-1.0, EYE_HEIGHT, 4.6), "target": Vector3(6.0, 1.3, 0.6), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "05_corridor", "position": Vector3(6.6, EYE_HEIGHT, 0.5), "target": Vector3(14.0, 1.3, -0.3), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "06_doorway", "position": Vector3(8.7, EYE_HEIGHT, -0.9), "target": Vector3(6.0, 1.25, 0.2), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "07_window", "position": Vector3(8.0, EYE_HEIGHT, 0.6), "target": Vector3(8.4, 1.75, -2.0), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "08_reactor_from_door", "position": Vector3(14.5, EYE_HEIGHT, 0.2), "target": Vector3(19.0, 1.3, 2.4), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "09_reactor_room", "position": Vector3(20.3, EYE_HEIGHT, 3.3), "target": Vector3(15.5, 1.0, 0.2), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "10_reactor_panel", "position": Vector3(15.0, EYE_HEIGHT, 4.3), "target": Vector3(21.5, 1.0, 3.0), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "11_canisters", "position": Vector3(19.3, EYE_HEIGHT, 1.0), "target": Vector3(20.9, 0.8, 0.2), "fov": WALK_FOV, "hide_ceiling": false},
	{"name": "12_task_panel", "position": Vector3(16.6, EYE_HEIGHT, 4.5), "target": Vector3(16.9, 1.3, 6.0), "fov": WALK_FOV, "hide_ceiling": false},
]

var _yaw: float = 0.0
var _pitch: float = 0.0

@onready var _camera: Camera3D = $Camera
@onready var _ceilings: Node3D = $Ceilings


func _ready() -> void:
	var shots_requested: bool = SHOTS_ARGUMENT in OS.get_cmdline_user_args()
	_ceilings.propagate_call(&"set_layer_mask_value", [DEFAULT_RENDER_LAYER, false])
	_ceilings.propagate_call(&"set_layer_mask_value", [CEILING_RENDER_LAYER, true])
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		# Без видеокарты сцена только загружается: ни снимков, ни покадровой работы.
		set_process(false)
		set_process_unhandled_input(false)
		if shots_requested:
			print("KIT PREVIEW: снимки в режиме headless недоступны")
			get_tree().quit(1)
		return
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
		var hide_ceiling: bool = shot["hide_ceiling"]
		_camera.fov = shot["fov"]
		_camera.look_at_from_position(camera_position, target)
		_camera.set_cull_mask_value(CEILING_RENDER_LAYER, not hide_ceiling)
		for frame: int in WARMUP_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = OUT_DIR + shot_name + ".png"
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("KIT PREVIEW: сохранён ", path)
	get_tree().quit(0)


## «--only=<часть имени>» после «--shots» оставляет только подходящие ракурсы.
func _shot_filter() -> String:
	const PREFIX: String = "--only="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(PREFIX):
			return argument.trim_prefix(PREFIX)
	return ""
