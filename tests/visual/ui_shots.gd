extends Node
## Снимки всех экранов интерфейса на поддельных данных — чтобы оценивать вёрстку глазами.
## Запуск (нужен настоящий рендер, размер окна задаёт --resolution):
##   godot --path . --resolution 1920x1080 res://tests/visual/ui_shots.tscn -- --shots --dir=1080
## Кладёт 21 PNG в res://out/<dir>/ и выходит. Необязательные аргументы: --only=<начало имени>
## снимает часть кадров, --stress добавляет кадры x_* с предельными случаями. Под программным
## Vulkan перед командой нужны VK_ICD_FILENAMES=<путь к lvp_icd.json> и xvfb-run.
## Без --shots сцена ничего не делает: её загружает и модульный тест.
## Тему экраны несут сами (theme у корня каждой сцены scenes/ui), настройка проекта не нужна.
## Фон HUD — уголок настоящей станции (tests/visual/hud_backdrop.tscn), а не серые кубики.
## Данные ставятся прямо в экраны и элементы HUD, минуя ведущего матча (MatchPresenter):
## его проверяет модульный тест, а здесь важен только внешний вид.

const OUT_DIR: String = "res://out/"
const GDIGNORE_FILE: String = ".gdignore"
const SHOTS_FLAG: String = "--shots"
const ONLY_ARG: String = "--only"
## Подпапка в out/: снимки разных разрешений лежат отдельно (--dir=1080, --dir=720).
const DIR_ARG: String = "--dir"
## Вместе с --shots добавляет кадры x_*: предельные имена и голоса, фокус клавиатуры.
const STRESS_FLAG: String = "--stress"
const MENU_SCENE: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const LOBBY_SCENE: PackedScene = preload("res://scenes/ui/lobby.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const MEETING_SCENE: PackedScene = preload("res://scenes/ui/meeting_screen.tscn")
const REVEAL_SCENE: PackedScene = preload("res://scenes/ui/role_reveal.tscn")
const RESULTS_SCENE: PackedScene = preload("res://scenes/ui/results_screen.tscn")
const BACKDROP_SCENE: PackedScene = preload("res://tests/visual/hud_backdrop.tscn")
## Сколько кадров ждём перед снимком: раскладка контейнеров и перенос строк устаканиваются не сразу.
const SETTLE_FRAMES: int = 4
## Откуда и куда смотрит камера на фоне HUD: реакторная от двери.
const BACKDROP_EYE: Vector3 = Vector3(14.5, 1.6, 0.2)
const BACKDROP_TARGET: Vector3 = Vector3(19.0, 1.3, 2.4)
## Номер цвета и имя члена экипажа, который стоит в кадре.
const BACKDROP_CREW_COLOR: int = 3
## peer_id локального игрока: без подключения multiplayer.get_unique_id() равен 1.
const LOCAL_ID: int = 1
## Номер локального игрока в списках PLAYER_IDS и PLAYER_NAMES.
const LOCAL_INDEX: int = 2
## Уведомления на снимках не должны погаснуть, пока программный рендер рисует кадр.
const TOAST_HOLD_SEC: float = 3600.0
## Номера клавиш кодовой панели в сетке: цифры 1–9 идут с нуля.
const KEYPAD_KEY_4: int = 3
const KEYPAD_KEY_8: int = 7
const KEYPAD_KEY_1: int = 0
const KEYPAD_KEY_5: int = 4

## Восемь игроков в порядке входа: peer_id, имя. Локальный игрок — третий.
const PLAYER_IDS: Array[int] = [41, 17, LOCAL_ID, 58, 23, 76, 92, 35]
const PLAYER_NAMES: PackedStringArray = [
	"Ваня", "Оля_Котик", "Давид", "Космонавт_Валера", "Джексон", "Дамир", "Мила", "xX_Тимур_Xx",
]

var _layer: CanvasLayer = null
var _only: String = ""
var _out_dir: String = OUT_DIR


func _ready() -> void:
	if not OS.get_cmdline_user_args().has(SHOTS_FLAG):
		return
	_run.call_deferred()


func _run() -> void:
	_only = CmdArgs.get_value(ONLY_ARG)
	UiMotion.enabled = false
	_out_dir = OUT_DIR.path_join(CmdArgs.get_value(DIR_ARG))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	# Без этого файла редактор начнёт импортировать снимки как текстуры.
	var marker: FileAccess = FileAccess.open(OUT_DIR.path_join(GDIGNORE_FILE), FileAccess.WRITE)
	if marker != null:
		marker.close()
	_layer = CanvasLayer.new()
	add_child(_layer)
	await _shoot_menu()
	await _shoot_lobby()
	await _shoot_hud()
	await _shoot_meeting()
	await _shoot_role_reveal()
	await _shoot_results()
	print("SHOTS: готово")
	get_tree().quit(0)


func _wants(shot_name: String) -> bool:
	return _only.is_empty() or shot_name.begins_with(_only)


func _snap(shot_name: String) -> void:
	if not _wants(shot_name):
		return
	for frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _out_dir.path_join(shot_name + ".png")
	var error: Error = image.save_png(ProjectSettings.globalize_path(path))
	print("SHOTS: %s %s %s" % [path, image.get_size(), error_string(error)])


# --- Меню ---

func _shoot_menu() -> void:
	var menu: MainMenu = MENU_SCENE.instantiate() as MainMenu
	_layer.add_child(menu)
	(menu.get_node(^"%NameEdit") as LineEdit).text = "Давид"
	(menu.get_node(^"%AddressEdit") as LineEdit).text = "predatel.example.org:7777"
	await _snap("01_menu_idle")
	menu.show_connecting()
	await _snap("02_menu_connecting")
	menu.show_status(Net.REASON_VERSION_MISMATCH)
	await _snap("03_menu_error")
	menu.queue_free()


# --- Лобби ---

func _shoot_lobby() -> void:
	var lobby: Lobby = LOBBY_SCENE.instantiate() as Lobby
	_layer.add_child(lobby)
	# Ты хост, игроков хватает.
	_fake_lobby(6, LOCAL_ID, 5)
	await _snap("04_lobby_host_ready")
	# Хост — другой игрок, лобби полное.
	_fake_lobby(8, PLAYER_IDS[0], 5)
	await _snap("05_lobby_guest_waiting")
	# Ты хост, но игроков мало.
	_fake_lobby(3, LOCAL_ID, 5)
	await _snap("06_lobby_need_players")
	lobby.queue_free()
	_clear_session()


## Подставляет в Net и Game лобби из первых count игроков.
func _fake_lobby(count: int, host_id: int, min_players: int) -> void:
	Net.status = Net.Status.JOINED
	Net.players.clear()
	Net.player_colors.clear()
	for index: int in count:
		Net.players[PLAYER_IDS[index]] = PLAYER_NAMES[index]
		Net.player_colors[PLAYER_IDS[index]] = index
	Net.host_id = host_id
	Game.min_players = min_players
	Net.lobby_changed.emit()


func _clear_session() -> void:
	Net.status = Net.Status.OFFLINE
	Net.players.clear()
	Net.player_colors.clear()
	Net.host_id = 0


# --- HUD ---

func _shoot_hud() -> void:
	var backdrop: Node3D = BACKDROP_SCENE.instantiate() as Node3D
	add_child(backdrop)
	(backdrop.get_node(^"Camera") as Camera3D).look_at_from_position(BACKDROP_EYE, BACKDROP_TARGET)
	var crewmate: PlayerVisuals = backdrop.get_node(^"Crewmate") as PlayerVisuals
	crewmate.set_body_color(PlayerPalette.color(BACKDROP_CREW_COLOR))
	crewmate.set_display_name(PLAYER_NAMES[BACKDROP_CREW_COLOR])
	var hud: Hud = HUD_SCENE.instantiate() as Hud
	_layer.add_child(hud)
	# Ведущий матча каждый кадр сверяет таймеры с игрой, а игры тут нет: он затёр бы
	# подставленные числа.
	(hud.get_node(^"%Match") as MatchPresenter).set_process(false)
	# Ты хост: в паузе видна кнопка «Завершить матч».
	_fake_lobby(PLAYER_IDS.size(), LOCAL_ID, 5)
	var crosshair: Control = hud.get_node(^"%Crosshair") as Control
	var banner: HudBanner = hud.get_node(^"%Banner") as HudBanner
	var role: HudRole = hud.get_node(^"%Role") as HudRole
	var tasks: HudTasks = hud.get_node(^"%Tasks") as HudTasks
	var vitals: HudVitals = hud.get_node(^"%Vitals") as HudVitals
	var weapon: HudWeapon = hud.get_node(^"%Weapon") as HudWeapon
	var prompt: HudPrompt = hud.get_node(^"%Prompt") as HudPrompt
	var gauge: HudGauge = hud.get_node(^"%Gauge") as HudGauge
	var alert: HudAlert = hud.get_node(^"%Alert") as HudAlert
	var ability: HudAbility = hud.get_node(^"%Ability") as HudAbility
	var toasts: HudToasts = hud.get_node(^"%Toasts") as HudToasts
	var keypad: KeypadPanel = hud.get_node(^"%Keypad") as KeypadPanel

	# Экипаж: задания (два уже сделаны), ранения, пистолет, подсказка с удержанием.
	banner.hide_banner()
	crosshair.visible = true
	role.visible = true
	role.set_role(false, PackedStringArray())
	tasks.visible = true
	tasks.set_tasks(
			PackedStringArray(["Заправить реактор", "Починить проводку — Реактор", "Скачать журнал полётов",
					"Откалибровать датчик — Мостик", "Ввести код доступа — Склад"]),
			[true, false, true, false, false] as Array[bool])
	tasks.set_progress(7, 20)
	vitals.visible = true
	vitals.set_health(64, 100)
	vitals.set_parts(PackedFloat32Array([1.0, 0.8, 0.0, 1.0, 1.0, 0.4]), BodyPart.bit(BodyPart.Part.LEFT_ARM))
	weapon.visible = true
	weapon.set_weapon("Пистолет", 5, true)
	prompt.show_prompt(MatchText.KEY_INTERACT, "Починить проводку")
	prompt.set_hold_progress(0.6)
	await _snap("07_hud_crew")

	# Пауза хоста поверх того же HUD. После паузы ведущий сам решает, виден ли прицел
	# (своего аватара тут нет), поэтому возвращаем его вручную.
	_press_cancel()
	await get_tree().process_frame
	await _snap("09_hud_pause")
	_press_cancel()
	await get_tree().process_frame
	crosshair.visible = true

	# Калибратор: под подсказкой шкала, заполнение подходит к зелёной зоне.
	prompt.show_prompt(MatchText.KEY_INTERACT, "Калибровать")
	prompt.set_hold_progress(0.0)
	gauge.show_gauge(0.58, 0.78)
	gauge.set_fraction(0.46)
	await _snap("19_calibrate")
	gauge.hide_gauge()
	prompt.hide_prompt()

	# Уведомления: задание выполнено и потерянная конечность.
	toasts.show_toast(MatchText.task_done("Починить проводку"), HudToast.Kind.SUCCESS, TOAST_HOLD_SEC)
	toasts.show_toast(MatchText.limb_lost(BodyPart.Part.LEFT_ARM), HudToast.Kind.DANGER, TOAST_HOLD_SEC)
	await _snap("21_toast")
	toasts.clear()

	# Кодовая панель: код на наклейке, две цифры уже набраны.
	crosshair.visible = false
	keypad.open("Ввести код доступа", "4815")
	var keys: Node = keypad.get_node(^"%Keys")
	(keys.get_child(KEYPAD_KEY_4) as Button).pressed.emit()
	(keys.get_child(KEYPAD_KEY_8) as Button).pressed.emit()
	await _snap("18_keypad")
	if OS.get_cmdline_user_args().has(STRESS_FLAG):
		(keys.get_child(KEYPAD_KEY_5) as Button).pressed.emit()
		(keys.get_child(KEYPAD_KEY_1) as Button).pressed.emit()
		keypad.show_error()
		toasts.show_toast(MatchText.TOAST_WRONG_CODE, HudToast.Kind.DANGER, TOAST_HOLD_SEC)
		await _snap("x_keypad_error")
		toasts.clear()
	keypad.close()

	# Призрак: боевого HUD нет, роль и задания остались, внизу строка призрака.
	vitals.visible = false
	weapon.visible = false
	banner.show_banner(MatchText.BANNER_GHOST)
	await _snap("20_hud_ghost")

	# Предатель с напарником: та же панель заданий (для прикрытия) с прогрессом экипажа,
	# нож, саботаж на перезарядке, тревога.
	banner.hide_banner()
	crosshair.visible = true
	tasks.set_tasks(
			PackedStringArray(["Починить проводку — Реактор", "Скачать журнал полётов", "Заправить реактор"]),
			[false, false, false] as Array[bool])
	tasks.set_progress(7, 20)
	role.set_role(true, PackedStringArray(["Мила"]))
	vitals.visible = true
	vitals.set_health(100, 100)
	vitals.set_parts(PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0]), 0)
	weapon.visible = true
	weapon.set_weapon("Нож", -1, true)
	ability.visible = true
	ability.set_ability(MatchText.KEY_SABOTAGE, MatchText.ABILITY_SABOTAGE, 12.0)
	alert.show_alert(MatchText.ALERT_REACTOR, 38.0)
	await _snap("08_hud_traitor_alert")

	# Наблюдатель: пустой HUD и строка внизу.
	alert.hide_alert()
	role.visible = false
	tasks.visible = false
	vitals.visible = false
	weapon.visible = false
	ability.visible = false
	crosshair.visible = false
	banner.show_banner(MatchText.BANNER_SPECTATOR)
	await _snap("10_hud_spectator")
	hud.queue_free()
	backdrop.queue_free()
	_clear_session()


func _press_cancel() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


# --- Собрание ---

func _shoot_meeting() -> void:
	var meeting: MeetingScreen = MEETING_SCENE.instantiate() as MeetingScreen
	_layer.add_child(meeting)
	var jackson: int = PLAYER_IDS[4]
	meeting.open(MatchText.meeting_title(Meeting.Reason.BODY),
			MatchText.meeting_subtitle(Meeting.Reason.BODY, PLAYER_NAMES[4], PLAYER_NAMES[6]), _entries([]))
	meeting.set_stage(MeetingScreen.Stage.DISCUSSION, 42.0)
	await _snap("11_meeting_discussion")

	# Трое проголосовали, ты выбрал Джексона.
	meeting.set_stage(MeetingScreen.Stage.VOTING, 23.0)
	meeting.set_entries(_entries([PLAYER_IDS[0], LOCAL_ID, PLAYER_IDS[3]]))
	meeting.mark_own_vote(jackson)
	meeting.set_can_vote(false)
	await _snap("12_meeting_voting")

	var votes: Dictionary[int, int] = {
		PLAYER_IDS[0]: jackson,
		PLAYER_IDS[1]: jackson,
		LOCAL_ID: jackson,
		PLAYER_IDS[3]: MeetingScreen.SKIP_ID,
		jackson: PLAYER_IDS[0],
		PLAYER_IDS[7]: jackson,
	}
	meeting.set_entries(_entries(votes.keys()))
	meeting.show_verdict(MatchText.verdict(true, PLAYER_NAMES[4], Game.Role.TRAITOR), votes, jackson)
	meeting.set_stage(MeetingScreen.Stage.VERDICT, 6.0)
	await _snap("13_meeting_verdict")
	if OS.get_cmdline_user_args().has(STRESS_FLAG):
		await _shoot_stress(meeting)
	meeting.queue_free()


## Восемь игроков собрания; двое мертвы. voted — кто уже проголосовал.
func _entries(voted: Array) -> Array[MeetingScreen.Entry]:
	var dead: Array[int] = [PLAYER_IDS[5], PLAYER_IDS[6]]
	var entries: Array[MeetingScreen.Entry] = []
	for index: int in PLAYER_IDS.size():
		var entry: MeetingScreen.Entry = MeetingScreen.Entry.new()
		entry.peer_id = PLAYER_IDS[index]
		entry.name = PLAYER_NAMES[index]
		entry.color = PlayerPalette.color(index)
		entry.alive = not dead.has(entry.peer_id)
		entry.is_self = entry.peer_id == LOCAL_ID
		entry.has_voted = voted.has(entry.peer_id)
		entries.append(entry)
	return entries


## Предельные случаи, которых нет в основном наборе: самое широкое имя, восемь голосов
## в одну карточку, длинный итог, все пропустили, фокус клавиатуры, ошибка в три строки.
func _shoot_stress(meeting: MeetingScreen) -> void:
	var entries: Array[MeetingScreen.Entry] = _entries([])
	var votes: Dictionary[int, int] = {}
	for entry: MeetingScreen.Entry in entries:
		entry.alive = true
		if entry.is_self:
			entry.name = "Ш".repeat(PlayerName.MAX_LENGTH)
		votes[entry.peer_id] = LOCAL_ID
	meeting.set_entries(entries)
	meeting.show_verdict("Никого не изгнали: ничья. Очень длинный текст итога, который не помещается в строку.",
			votes, LOCAL_ID)
	await _snap("x_meeting_all_votes")
	for entry: MeetingScreen.Entry in entries:
		votes[entry.peer_id] = MeetingScreen.SKIP_ID
	meeting.show_verdict(MatchText.verdict(false, "", Game.Role.NONE), votes, MeetingScreen.SKIP_ID)
	await _snap("x_meeting_all_skipped")
	meeting.open(MatchText.meeting_title(Meeting.Reason.BUTTON),
			MatchText.meeting_subtitle(Meeting.Reason.BUTTON, PLAYER_NAMES[3], ""), entries)
	meeting.set_stage(MeetingScreen.Stage.VOTING, 75.0)
	meeting.set_can_vote(true)
	await _snap("x_meeting_can_vote")
	meeting.mark_own_vote(MeetingScreen.SKIP_ID)
	meeting.set_can_vote(false)
	await _snap("x_meeting_own_skip")
	meeting.close()

	var menu: MainMenu = MENU_SCENE.instantiate() as MainMenu
	_layer.add_child(menu)
	var name_edit: LineEdit = menu.get_node(^"%NameEdit") as LineEdit
	name_edit.grab_focus()
	name_edit.select_all()
	await _snap("x_menu_field_focus")
	(menu.get_node(^"%ConnectButton") as Button).grab_focus()
	await _snap("x_menu_button_focus")
	(menu.get_node(^"%QuitButton") as Button).grab_focus()
	(menu.get_node(^"%AddressEdit") as LineEdit).text = ""
	menu.show_status(MainMenu.TEXT_JOIN_ERROR % "Can't resolve hostname, check the address and try again later")
	await _snap("x_menu_long_error")
	menu.queue_free()


# --- Роль в начале матча ---

func _shoot_role_reveal() -> void:
	var reveal: RoleReveal = REVEAL_SCENE.instantiate() as RoleReveal
	_layer.add_child(reveal)
	var own_color: Color = PlayerPalette.color(LOCAL_INDEX)
	reveal.show_role(false, own_color, PackedStringArray(), [] as Array[Color])
	reveal.set_seconds_left(5.0)
	await _snap("14_role_reveal_crew")
	reveal.show_role(true, own_color, PackedStringArray([PLAYER_NAMES[6]]), [PlayerPalette.color(6)] as Array[Color])
	reveal.set_seconds_left(4.0)
	await _snap("15_role_reveal_traitor")
	if OS.get_cmdline_user_args().has(STRESS_FLAG):
		# Пауза на чтение роли выключена, напарника нет.
		reveal.show_role(true, own_color, PackedStringArray(), [] as Array[Color])
		reveal.set_seconds_left(0.0)
		await _snap("x_reveal_traitor_alone")
	reveal.queue_free()


# --- Итоги ---

func _shoot_results() -> void:
	var results: ResultsScreen = RESULTS_SCENE.instantiate() as ResultsScreen
	_layer.add_child(results)
	# Экипаж победил, ты в экипаже и дожил до конца.
	results.open(MatchText.winner_title(Game.Winner.CREW), MatchText.end_reason(Game.EndReason.TASKS_DONE),
			ResultsScreen.Team.CREW, ResultsScreen.Outcome.WON, _result_entries([6, 4], [5, 6]))
	results.set_seconds_left(8.0)
	await _snap("16_results_victory")
	# Победили предатели, а ты из экипажа и не дожил.
	results.open(MatchText.winner_title(Game.Winner.TRAITORS), MatchText.end_reason(Game.EndReason.SABOTAGE),
			ResultsScreen.Team.TRAITORS, ResultsScreen.Outcome.LOST, _result_entries([6, 4], [LOCAL_INDEX, 0, 5]))
	results.set_seconds_left(6.0)
	await _snap("17_results_defeat")
	if OS.get_cmdline_user_args().has(STRESS_FLAG):
		# Наблюдатель, самые широкие имена, один предатель.
		var entries: Array[ResultsScreen.Entry] = _result_entries([1], [3])
		for entry: ResultsScreen.Entry in entries:
			entry.name = "Ш".repeat(PlayerName.MAX_LENGTH)
			entry.is_self = false
		results.open(MatchText.winner_title(Game.Winner.TRAITORS),
				MatchText.end_reason(Game.EndReason.CREW_OUTNUMBERED),
				ResultsScreen.Team.TRAITORS, ResultsScreen.Outcome.WATCHED, entries)
		results.set_seconds_left(75.0)
		await _snap("x_results_watched")
	results.queue_free()


## Восемь участников; traitors и dead — номера в списке игроков.
func _result_entries(traitors: Array[int], dead: Array[int]) -> Array[ResultsScreen.Entry]:
	var entries: Array[ResultsScreen.Entry] = []
	for index: int in PLAYER_IDS.size():
		var entry: ResultsScreen.Entry = ResultsScreen.Entry.new()
		entry.name = PLAYER_NAMES[index]
		entry.color = PlayerPalette.color(index)
		entry.is_traitor = traitors.has(index)
		entry.alive = not dead.has(index)
		entry.is_self = index == LOCAL_INDEX
		entries.append(entry)
	return entries
