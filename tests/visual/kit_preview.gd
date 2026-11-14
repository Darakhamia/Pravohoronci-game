extends Node3D
## Демонстрационный уголок станции из набора scenes/maps/kit и реквизита scenes/maps/props:
## офис с переговорным столом, коридор и реакторная. Сцену собирает tools/assets/environment_preview.py.
##
## Запуск: обычный — можно ходить (WASD, мышь, Esc — выход);
## с аргументом «-- --shots» сцена сохраняет снимки в res://out/ и закрывается;
## «--only=<часть имени>[,<часть имени>...]» оставляет часть ракурсов, «--hide=<путь узла>» прячет узел
## (SunLight, Decals, Probes), «--show=<путь узла>» показывает спрятанный, «--frames=N» — сколько кадров
## ждать перед снимком, «--fast» выключает MSAA (черновые снимки на программном рендере).
## Итоговые снимки делай в 1920x1080: godot --resolution 1920x1080 res://tests/visual/kit_preview.tscn -- --shots
##
## РЕЦЕПТ СВЕТА (его же повторяй на боевой карте). Источники — префабы scenes/maps/lights и набора.
## 0. Окружение resources/maps/station_environment.tres: тональная кривая AgX, SDFGI, SSAO + SSIL, SSR,
##    сдержанный glow, объёмная дымка, космос за окнами. Ровного ambient внутри станции НЕТ: куда не попал
##    свет ламп, попадает только отскок от стен и пола (SDFGI). Тёмный угол лечится лампой, а не настройкой
##    окружения или экспозицией. Яркости ниже подобраны под AgX с экспозицией 1,1.
##    Сглаживание — настройки проекта (project.godot, раздел [rendering]): MSAA 4x + FXAA. Без него мелкие
##    детали набора (болты, решётки, перфорация) рябят в движении.
## 1. Практический свет — потолочная панель ceiling_light: в её префабе узел Light, SpotLight3D БЕЗ теней,
##    смотрит строго вниз (energy 12, spot_attenuation 2 — почти обратные квадраты, угол 33°, range 5,5).
##    Пятно на полу — круг радиусом 2 м, он не выходит за клетку 4 x 4 м, поэтому свет без теней не
##    пролезает под стеной к соседям. В дымке под панелью виден мягкий конус.
##    Светлая комната — панель в каждой клетке; мрачная — в каждой второй. Панели освещают только пол и
##    столы: стены, лица и потолок без ключевого света (п. 2) останутся тёмными.
## 2. Ключевой свет — key_light.tscn, ОДИН на блок до 8 x 8 м: OmniLight3D с тенями в центре блока под
##    потолком (y = 2,6). Светит во все стороны и почти не слабеет с расстоянием (omni_attenuation 0,5,
##    range 10): даёт вертикальную освещённость — верх стен, лица людей за столом, потолок, — тени от
##    мебели и игроков и блики на глянце (light_specular 0,5). energy 3 в жилых комнатах: переговорная —
##    самая светлая зона станции, белые стены на снимке около 190–200 из 255. light_size 0,1: тени
##    мягкие, а отражение лампы в окне — маленькая звезда, а не белый диск.
##    Цвет: тёплый белый (1, 0.94, 0.85) в жилых комнатах; в технических — холодный (0.86, 0.93, 1) и
##    energy 2,4. В коридоре шириной 4 м — один на каждые 8 м, energy 1,6 (стены вдвое ближе к лампе).
##    В комнате с тёмной половиной (над ней короба вместо светильников) ключевой свет ставь над этой
##    половиной, а не в центре.
##    Не вешай его ниже 2,5 м и не поднимай energy выше 4: игрок прямо под лампой выгорит в белое.
## 3. Акценты, не больше двух на комнату, БЕЗ теней и с радиусом меньше расстояния до соседней комнаты:
##    accent_desk_lamp (тёплый, energy 1,6, range 3) — у настольных ламп и торшеров;
##    accent_strip_cool (голубой, energy 1,4, range 3,2) — у светящихся полос, арок, экранов (в 25–40 см
##    перед полосой, не вплотную: иначе стена вокруг неё выгорает);
##    accent_emergency (красный, energy 2,4, range 4,5) — над дверью опасного помещения.
##    Исключение с тенями — свечение реактора: OmniLight3D в центре ядра (energy 5, range 7,
##    attenuation 1,8, shadow_enabled): прутья клетки ложатся тенями на стены. Один такой на карту.
## 4. Солнце — sun_light.tscn, ОДИН на карту, в начале координат без поворота: DirectionalLight3D с тенями
##    (energy 3,5), направление совпадает с солнцем в небе (sun_direction шейдера космоса). Свет входит
##    только через окна: яркие пятна на полу и стенах, лучи в дымке. Меняешь направление — меняй оба.
##    Тени: четыре каскада на 18 м со сглаженными стыками — край солнечного пятна ровный и вдали.
##    Для настроек «высокое качество» подними rendering/lights_and_shadows/directional_shadow/size до 8192.
## 5. Отражения. На полу и столах — SSR (то, что в кадре: лампы, ядро реактора, светящиеся полосы) и
##    SDFGI (грубые, но везде). Пол, столешницы и эмаль сделаны полуглянцевыми (шероховатость 0,25–0,45),
##    иначе отражаться не в чем. Зонд reflection_probe_room.tscn — по одному на помещение: центр комнаты,
##    y = 1,6, size = размер помещения по осям стен + 0,4 м, снимается один раз. В этой сцене зонды
##    стоят в узле Probes. Если свет в комнате меняется (саботаж), зонд надо переснять, иначе тёмная
##    комната «светится» старым отражением: см. _set_zone_dark().
## 6. Декали scenes/maps/decals (разметка, надписи, пятна, потёртости): 4–8 на комнату, см. tools/textures/make_decals.py.
## 7. Свет не должен проходить сквозь стены: тени обязательны у любого источника, который достаёт до стены
##    (кроме панелей из п. 1 и акцентов из п. 3 — у них маленький радиус). Отскок SDFGI сквозь стену 0,2 м
##    почти не течёт (sdfgi_use_occlusion включён); проверка — снимки 19 и 20 «тёмная комната».
## 8. Бюджет на комнату 8 x 8 м: 4 панели без теней, 1 ключевой с тенями (куб из 6 граней, но геометрия
##    неподвижна: карта теней перерисовывается, только когда рядом ходят игроки), до 2 акцентов. В кадре
##    обычно 2–4 источника с тенями (комната, коридор, соседняя комната через дверь) плюс солнце.
## 9. Заметность игрока: низ стен и пол не темнее 40–45 из 255 (материалы env_deep, env_panel, env_line
##    держат 4–9 % отражения — это проверяет юнит-тест). Проверочные ракурсы с фигурами экипажа:
##    05 (игрок в 15 м в конце коридора), 10 (тело на полу у пульта), 21 (лица за столом собраний).

const SHOTS_ARGUMENT: String = "--shots"
## «--only=<часть имени>[,<часть имени>...]» оставляет только подходящие ракурсы.
const ONLY_ARGUMENT: String = "--only="
const FRAMES_ARGUMENT: String = "--frames="
const HIDE_ARGUMENT: String = "--hide="
const SHOW_ARGUMENT: String = "--show="
## «--fast» выключает MSAA: черновые снимки на программном рендере идут в несколько раз быстрее.
const FAST_ARGUMENT: String = "--fast"
## Сцена внешнего вида игрока: фигуры экипажа в ракурсах с пометкой crew.
const CREW_SCENE: String = "res://scenes/characters/player_visuals.tscn"
## Экипаж для проверки заметности: где стоит, куда повёрнут (градусы вокруг Y), цвет, лежит ли телом.
const CREW: Array[Dictionary] = [
	{"position": Vector3(21.2, 0.0, -0.1), "yaw": 90.0, "color": Color(0.9, 0.25, 0.2)},
	{"position": Vector3(17.3, 0.0, 5.25), "yaw": 250.0, "color": Color(0.2, 0.35, 0.9), "dead": true},
	{"position": Vector3(3.45, 0.0, 0.6), "yaw": 225.0, "color": Color(0.95, 0.8, 0.2)},
	{"position": Vector3(0.6, 0.0, 0.65), "yaw": 135.0, "color": Color(0.2, 0.75, 0.8)},
	{"position": Vector3(-0.15, 0.0, 2.7), "yaw": 100.0, "color": Color(0.9, 0.25, 0.2)},
]
const OUT_DIR: String = "res://out/"
const IGNORE_MARKER: String = ".gdignore"
const HEADLESS_DISPLAY: String = "headless"
## Высота глаз игрока.
const EYE_HEIGHT: float = 1.6
## Сколько кадров ждать перед первым снимком: SDFGI, тени, SSAO и glow успевают устояться.
const WARMUP_FRAMES: int = 48
## Сколько кадров ждать после смены ракурса: каскады SDFGI переезжают вслед за камерой.
const SETTLE_FRAMES: int = 26
## Сколько кадров ждать после выключения света в комнате: отскоки SDFGI гаснут не сразу.
const DARK_SETTLE_FRAMES: int = 120
const WALK_SPEED: float = 4.0
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = 1.5
## Слой отрисовки, на который переезжает потолок: камера общего плана этот слой не рисует.
## Прятать потолок целиком нельзя — вместе с ним погасли бы светильники внутри ceiling_light.
const CEILING_RENDER_LAYER: int = 2
const DEFAULT_RENDER_LAYER: int = 1
const WALK_FOV: float = 75.0
const OVERVIEW_FOV: float = 50.0
const CLOSE_FOV: float = 50.0
## Зона, которую гасит снимок «тёмная комната рядом со светлой».
const DARK_ZONE: String = "RoomB"
## Группы узлов, разложенные по зонам (см. tools/assets/environment_preview.py).
const ZONE_GROUPS: PackedStringArray = ["Decor", "Gameplay", "Lights"]
## Группа с зондами отражений, тоже разложенными по зонам.
const PROBES_GROUP: String = "Probes"
const LAMP_MATERIAL_SUFFIX: String = "env_lamp.tres"
const LAMP_OFF_MATERIAL: String = "res://resources/materials/env_lamp_off.tres"
const CEILING_LIGHT_NODE: String = "Light"

## Ракурсы для снимков: имя файла, где стоит камера, куда смотрит, угол обзора; по желанию —
## hide_ceiling (спрятать потолок), dark (погасить зону DARK_ZONE: проверка, что свет не течёт сквозь стены)
## и crew (поставить фигуры экипажа CREW: видно ли игрока с 15 м, тело на полу, лица на собрании).
const SHOTS: Array[Dictionary] = [
	{"name": "01_overview", "position": Vector3(10.0, 16.0, 13.5), "target": Vector3(10.0, 0.0, 2.4), "fov": OVERVIEW_FOV, "hide_ceiling": true},
	{"name": "02_office_from_door", "position": Vector3(5.2, EYE_HEIGHT, 0.4), "target": Vector3(0.5, 1.2, 2.6), "fov": WALK_FOV},
	{"name": "03_office_window", "position": Vector3(3.6, EYE_HEIGHT, 5.0), "target": Vector3(0.6, 1.3, -2.0), "fov": WALK_FOV},
	{"name": "04_office_to_corridor", "position": Vector3(-1.0, EYE_HEIGHT, 4.6), "target": Vector3(6.0, 1.3, 0.6), "fov": WALK_FOV},
	{"name": "05_corridor", "position": Vector3(6.6, EYE_HEIGHT, 0.5), "target": Vector3(14.0, 1.3, -0.3), "fov": WALK_FOV, "crew": true},
	{"name": "06_doorway", "position": Vector3(8.7, EYE_HEIGHT, -0.9), "target": Vector3(6.0, 1.25, 0.2), "fov": WALK_FOV},
	{"name": "07_window", "position": Vector3(8.0, EYE_HEIGHT, 0.6), "target": Vector3(8.4, 1.75, -2.0), "fov": WALK_FOV},
	{"name": "08_reactor_from_door", "position": Vector3(14.5, EYE_HEIGHT, 0.2), "target": Vector3(19.0, 1.3, 2.4), "fov": WALK_FOV},
	{"name": "09_reactor_room", "position": Vector3(20.3, EYE_HEIGHT, 3.3), "target": Vector3(15.5, 1.0, 0.2), "fov": WALK_FOV},
	{"name": "10_reactor_panel", "position": Vector3(15.0, EYE_HEIGHT, 4.3), "target": Vector3(21.5, 1.0, 3.0), "fov": WALK_FOV, "crew": true},
	{"name": "11_canisters", "position": Vector3(19.3, EYE_HEIGHT, 1.0), "target": Vector3(20.9, 0.8, 0.2), "fov": WALK_FOV},
	{"name": "12_task_panel", "position": Vector3(16.6, EYE_HEIGHT, 4.5), "target": Vector3(16.9, 1.3, 6.0), "fov": WALK_FOV},
	{"name": "13_close_wall", "position": Vector3(-1.55, 1.7, 5.2), "target": Vector3(-1.9, 1.75, 0.5), "fov": CLOSE_FOV},
	{"name": "14_close_floor", "position": Vector3(6.9, 0.5, -0.5), "target": Vector3(12.5, 0.05, 0.4), "fov": CLOSE_FOV},
	{"name": "15_close_metal", "position": Vector3(4.7, 1.25, 3.7), "target": Vector3(5.5, 1.1, 3.0), "fov": CLOSE_FOV},
	{"name": "16_close_screen", "position": Vector3(-0.6, 1.25, -0.55), "target": Vector3(-1.0, 1.0, -1.35), "fov": CLOSE_FOV},
	{"name": "17_close_glass", "position": Vector3(1.6, 1.75, -0.2), "target": Vector3(-0.2, 1.9, -2.0), "fov": CLOSE_FOV},
	{"name": "18_close_reactor", "position": Vector3(17.0, 1.45, 3.4), "target": Vector3(18.0, 1.25, 1.6), "fov": CLOSE_FOV},
	{"name": "21_crew_meeting", "position": Vector3(3.3, EYE_HEIGHT, 4.5), "target": Vector3(1.6, 1.25, 0.6), "fov": WALK_FOV, "crew": true},
	{"name": "22_close_table", "position": Vector3(3.9, 1.3, 3.8), "target": Vector3(2.5, 0.75, 2.2), "fov": CLOSE_FOV},
	{"name": "23_close_vending", "position": Vector3(3.7, 1.45, 3.2), "target": Vector3(5.5, 1.05, 4.3), "fov": CLOSE_FOV},
	{"name": "24_close_bunk", "position": Vector3(16.0, 1.45, 0.75), "target": Vector3(16.75, 0.75, -1.3), "fov": CLOSE_FOV},
	{"name": "25_close_plant", "position": Vector3(4.1, 1.35, -0.05), "target": Vector3(3.2, 0.75, -1.4), "fov": CLOSE_FOV},
	{"name": "19_dark_room_inside", "position": Vector3(20.4, EYE_HEIGHT, 4.6), "target": Vector3(14.0, 1.4, 0.8), "fov": WALK_FOV, "dark": true},
	{"name": "20_dark_room_from_corridor", "position": Vector3(8.4, EYE_HEIGHT, 0.6), "target": Vector3(14.0, 1.4, 0.0), "fov": WALK_FOV, "dark": true},
]

var _yaw: float = 0.0
var _pitch: float = 0.0
var _crew: Node3D = null

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
	_hide_requested_nodes()
	if FAST_ARGUMENT in OS.get_cmdline_user_args():
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
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
	var only: String = _argument_value(ONLY_ARGUMENT)
	# «--frames=N» — сколько кадров ждать перед каждым снимком (для быстрых проб; свет не успевает устояться).
	var frames_override: int = _argument_value(FRAMES_ARGUMENT).to_int()
	var frames_to_wait: int = frames_override if frames_override > 0 else WARMUP_FRAMES
	var is_dark: bool = false
	for shot: Dictionary in SHOTS:
		var shot_name: String = shot["name"]
		if not _is_wanted(shot_name, only):
			continue
		var camera_position: Vector3 = shot["position"]
		var target: Vector3 = shot["target"]
		var hide_ceiling: bool = shot.get("hide_ceiling", false)
		var dark: bool = shot.get("dark", false)
		_set_crew_visible(shot.get("crew", false))
		if dark != is_dark:
			is_dark = dark
			_set_zone_dark(DARK_ZONE, dark)
			frames_to_wait = maxi(frames_to_wait, DARK_SETTLE_FRAMES)
		_camera.fov = shot["fov"]
		_camera.look_at_from_position(camera_position, target)
		_camera.set_cull_mask_value(CEILING_RENDER_LAYER, not hide_ceiling)
		for frame: int in frames_to_wait:
			await get_tree().process_frame
		frames_to_wait = frames_override if frames_override > 0 else SETTLE_FRAMES
		await RenderingServer.frame_post_draw
		var path: String = OUT_DIR + shot_name + ".png"
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("KIT PREVIEW: сохранён ", path)
	get_tree().quit(0)


## Показывает или прячет фигуры экипажа; при первом показе создаёт их из сцены внешнего вида игрока.
func _set_crew_visible(shown: bool) -> void:
	if _crew == null:
		if not shown or not ResourceLoader.exists(CREW_SCENE):
			return
		var scene: PackedScene = load(CREW_SCENE) as PackedScene
		_crew = Node3D.new()
		_crew.name = "Crew"
		add_child(_crew)
		for member: Dictionary in CREW:
			var figure: Node3D = scene.instantiate() as Node3D
			_crew.add_child(figure)
			figure.position = member["position"]
			figure.rotation_degrees.y = member["yaw"]
			if figure.has_method(&"set_display_name"):
				figure.call(&"set_display_name", "")
			if figure.has_method(&"set_body_color"):
				figure.call(&"set_body_color", member["color"])
			if member.get("dead", false) and figure.has_method(&"set_dead"):
				figure.call(&"set_dead", true)
	_crew.visible = shown


## Гасит (или зажигает обратно) зону: свет, реквизит со светящимися деталями и потолочные лампы.
## Так же игровой код может делать саботаж «свет»: выключить узлы Light, подменить материал ламп
## на env_lamp_off и переснять зонды отражений (они сняты один раз и помнят светлую комнату):
## update_mode = UPDATE_ALWAYS на время перехода, через 2–3 секунды — обратно UPDATE_ONCE.
func _set_zone_dark(zone: String, dark: bool) -> void:
	for group: String in ZONE_GROUPS:
		var node: Node3D = get_node_or_null("%s/%s" % [group, zone]) as Node3D
		if node != null:
			node.visible = not dark
	var lamp_off: Material = load(LAMP_OFF_MATERIAL) as Material
	var ceilings: Node = get_node_or_null("Ceilings/%s" % zone)
	if ceilings != null:
		for light: Node in ceilings.find_children(CEILING_LIGHT_NODE, "Light3D", true, false):
			(light as Light3D).visible = not dark
		for node: Node in ceilings.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance: MeshInstance3D = node as MeshInstance3D
			for surface: int in mesh_instance.mesh.get_surface_count():
				var material: Material = mesh_instance.mesh.surface_get_material(surface)
				if material != null and material.resource_path.ends_with(LAMP_MATERIAL_SUFFIX):
					mesh_instance.set_surface_override_material(surface, lamp_off if dark else null)
	var probes: Node = get_node_or_null("%s/%s" % [PROBES_GROUP, zone])
	if probes == null:
		return
	for node: Node in probes.find_children("*", "ReflectionProbe", true, false):
		var probe: ReflectionProbe = node as ReflectionProbe
		# Зонд снят один раз и помнит светлую комнату: в темноте стены «светились» бы старым отражением.
		# Пока свет погашен, зонд снимает комнату постоянно (отскоки SDFGI гаснут пару секунд, и один
		# снимок застал бы их на полпути); когда свет вернулся — снова один раз.
		probe.update_mode = ReflectionProbe.UPDATE_ALWAYS if dark else ReflectionProbe.UPDATE_ONCE


## «--hide=<путь узла>» прячет узел сцены, «--show=<путь узла>» показывает спрятанный (можно несколько
## раз): так удобно смотреть, что дают солнце (SunLight), декали (Decals) или зонды отражений (Probes).
func _hide_requested_nodes() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var show: bool = argument.begins_with(SHOW_ARGUMENT)
		if not show and not argument.begins_with(HIDE_ARGUMENT):
			continue
		var node_path: String = argument.trim_prefix(SHOW_ARGUMENT if show else HIDE_ARGUMENT)
		var node: Node3D = get_node_or_null(node_path) as Node3D
		if node != null:
			node.visible = show


## Подходит ли ракурс под фильтр «--only=»: части имени через запятую, пустой фильтр — все ракурсы.
func _is_wanted(shot_name: String, only: String) -> bool:
	if only == "":
		return true
	for part: String in only.split(",", false):
		if shot_name.contains(part):
			return true
	return false


## Значение аргумента вида «--имя=значение» после «--» в командной строке; пустая строка, если его нет.
func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""
