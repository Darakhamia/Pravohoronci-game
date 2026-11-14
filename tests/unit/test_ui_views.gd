extends TestCase
## Элементы HUD и экраны матча без окна: сервер и боты создают те же сцены, поэтому каждый
## публичный метод обязан работать без рендера и с любым мусором на входе. Заодно проверяем
## правила показа, на которые опирается ведущий матча: порядок заданий, цвета состояний,
## видимость «Пропустить» по этапам собрания, набор кода, колонки итогов, уведомления.

const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const MEETING_SCENE: PackedScene = preload("res://scenes/ui/meeting_screen.tscn")
const KEYPAD_SCENE: PackedScene = preload("res://scenes/ui/keypad_panel.tscn")
const RESULTS_SCENE: PackedScene = preload("res://scenes/ui/results_screen.tscn")
const REVEAL_SCENE: PackedScene = preload("res://scenes/ui/role_reveal.tscn")
const TOASTS_SCENE: PackedScene = preload("res://scenes/ui/hud/hud_toasts.tscn")
const GAUGE_SCENE: PackedScene = preload("res://scenes/ui/hud/hud_gauge.tscn")
## Клавиши кодовой панели в сетке: цифры 1–9, «стереть», 0, «подтвердить».
const KEY_ERASE: int = 9
const KEY_ZERO: int = 10
const KEY_CONFIRM: int = 11
const PLAYER_COUNT: int = 8
const LOCAL_INDEX: int = 2
const DEAD_INDEX: int = 5


func test_tasks_show_pending_before_done() -> void:
	var done: Array[bool] = [true, false, true, false]
	assert_eq(HudTasks.display_order(4, done), PackedInt32Array([1, 3, 0, 2]), "выполненные тонут вниз")
	assert_eq(HudTasks.display_order(3, [] as Array[bool]), PackedInt32Array([0, 1, 2]), "без done все невыполненные")
	assert_eq(HudTasks.display_order(0, done), PackedInt32Array(), "пустой список")


func test_state_colors() -> void:
	assert_eq(UiTokens.damage_color(1.0), UiTokens.TEXT, "целая часть тела")
	assert_eq(UiTokens.damage_color(0.0), UiTokens.DANGER, "часть тела без здоровья")
	assert_true(UiTokens.damage_color(0.8) != UiTokens.TEXT, "раненая часть отличается от целой")
	assert_eq(UiTokens.health_color(1.0), UiTokens.SUCCESS, "полное здоровье")
	assert_eq(UiTokens.health_color(0.5), UiTokens.WARNING, "половина здоровья")
	assert_eq(UiTokens.health_color(0.1), UiTokens.DANGER, "здоровье на исходе")


func test_progress_path_is_closed_and_survives_garbage() -> void:
	var path: PackedVector2Array = UiDraw.rounded_path(Rect2(0.0, 0.0, 40.0, 40.0), 8.0)
	assert_eq(path[0], path[path.size() - 1], "контур замкнут")
	assert_eq(path[0], Vector2(20.0, 0.0), "контур начинается с середины верхней стороны")
	var tiny: PackedVector2Array = UiDraw.rounded_path(Rect2(0.0, 0.0, 2.0, 2.0), 100.0)
	assert_true(tiny.size() > 2, "радиус больше стороны не ломает контур")


func test_hud_views_accept_any_input() -> void:
	var hud: Hud = HUD_SCENE.instantiate() as Hud
	await _add_to_tree(hud)
	var role: HudRole = hud.get_node(^"%Role") as HudRole
	role.set_role(false, PackedStringArray())
	role.set_role(true, PackedStringArray(["Мила", "Очень_длинное_имя", "Ещё_один_напарник"]))
	var tasks: HudTasks = hud.get_node(^"%Tasks") as HudTasks
	tasks.set_tasks(PackedStringArray(["А", "Б", "В"]), [true] as Array[bool])
	tasks.set_tasks(PackedStringArray(), [true, true] as Array[bool])
	tasks.set_progress(-3, 0)
	tasks.set_progress(99, 20)
	tasks.set_cover(true)
	assert_eq(tasks.get_list_title(), "", "без списка заголовка «для прикрытия» нет")
	tasks.set_tasks(PackedStringArray(["А"]), [] as Array[bool])
	assert_eq(tasks.get_list_title(), HudTasks.TEXT_COVER, "список предателя подписан")
	tasks.set_cover(false)
	assert_eq(tasks.get_list_title(), "", "у экипажа список без заголовка")
	var vitals: HudVitals = hud.get_node(^"%Vitals") as HudVitals
	vitals.set_health(-5, 0)
	vitals.set_health(250, 100)
	vitals.set_parts(PackedFloat32Array(), 0)
	vitals.set_parts(PackedFloat32Array([2.0, -1.0, 0.5]), 255)
	var weapon: HudWeapon = hud.get_node(^"%Weapon") as HudWeapon
	weapon.set_weapon("", -1, false)
	weapon.set_weapon("Дробовик", 0, true)
	var ability: HudAbility = hud.get_node(^"%Ability") as HudAbility
	ability.set_ability("F", "Саботаж", 0.0)
	ability.set_ability("", "", -4.0)
	ability.set_ability("F", "Саботаж", 12.4)
	var prompt: HudPrompt = hud.get_node(^"%Prompt") as HudPrompt
	prompt.set_hold_progress(7.0)
	prompt.show_prompt("E", "Починить проводку")
	prompt.set_hold_progress(-1.0)
	assert_true(prompt.visible, "подсказка показана")
	assert_true(not prompt.is_hint_shown() and (prompt.get_node(^"%Key") as Control).visible, "у действия есть клавиша")
	prompt.set_hold_progress(0.5)
	prompt.show_hint("Нужна канистра со склада")
	assert_true(prompt.is_hint_shown() and not (prompt.get_node(^"%Key") as Control).visible, "у объяснения клавиши нет")
	assert_near((prompt.get_node(^"%Key") as HudKeyCap).get_hold(), 0.0, "объяснение сбрасывает рамку удержания")
	prompt.show_prompt("E", "Залить топливо")
	assert_true(not prompt.is_hint_shown(), "действие возвращает клавишу")
	prompt.show_hint("")
	prompt.hide_prompt()
	assert_true(not prompt.visible and not prompt.is_hint_shown(), "подсказка спрятана")
	var alert: HudAlert = hud.get_node(^"%Alert") as HudAlert
	alert.show_alert("Реактор перегревается", -2.0)
	alert.show_alert("", 3599.9)
	assert_true(alert.visible, "тревога показана")
	alert.hide_alert()
	assert_true(not alert.visible, "тревога спрятана")
	var banner: HudBanner = hud.get_node(^"%Banner") as HudBanner
	banner.show_banner("")
	banner.hide_banner()
	hud.set_cursor_needed(&"test", true)
	hud.set_cursor_needed(&"test", false)
	hud.set_map(null)
	await _free_from_tree(hud)


func test_meeting_skip_is_offered_only_while_voting() -> void:
	var meeting: MeetingScreen = MEETING_SCENE.instantiate() as MeetingScreen
	await _add_to_tree(meeting)
	var skip: Button = meeting.get_node(^"%SkipButton") as Button
	var skip_voters: Control = meeting.get_node(^"%SkipVoters") as Control
	meeting.open("Найдено тело", "Тело: Мила. Сообщает Джексон.", _entries())
	assert_true(meeting.visible, "собрание открыто")
	assert_true(not skip.visible, "в обсуждении «Пропустить» нет")
	meeting.set_stage(MeetingScreen.Stage.VOTING, 30.0)
	meeting.set_can_vote(true)
	assert_true(skip.visible and not skip.disabled, "в голосовании «Пропустить» можно нажать")
	meeting.mark_own_vote(MeetingScreen.SKIP_ID)
	meeting.set_can_vote(false)
	assert_true(skip.visible and skip.disabled, "мой пропуск остаётся на экране как выбор")
	meeting.mark_own_vote(_peer_id(0))
	assert_true(not skip.visible, "после голоса за игрока «Пропустить» убрано")
	var votes: Dictionary[int, int] = {_peer_id(0): MeetingScreen.SKIP_ID, _peer_id(1): _peer_id(0), 12345: 777}
	meeting.show_verdict("Никого не изгнали.", votes, MeetingScreen.SKIP_ID)
	assert_true(not skip.visible, "в итоге «Пропустить» — не кнопка")
	assert_eq(skip_voters.get_child_count(), 1, "пропустившие стоят мини-шлемами")
	meeting.set_entries([] as Array[MeetingScreen.Entry])
	meeting.close()
	assert_true(not meeting.visible, "собрание закрыто")
	await _free_from_tree(meeting)


func test_meeting_card_press_reports_vote() -> void:
	var meeting: MeetingScreen = MEETING_SCENE.instantiate() as MeetingScreen
	await _add_to_tree(meeting)
	var pressed: Array[int] = []
	meeting.vote_pressed.connect(func(target_id: int) -> void: pressed.append(target_id))
	meeting.open("Собрание", "", _entries())
	meeting.set_stage(MeetingScreen.Stage.VOTING, 30.0)
	meeting.set_can_vote(true)
	var cards: Node = meeting.get_node(^"%Cards")
	var alive_card: Button = cards.get_child(0) as Button
	var dead_card: Button = cards.get_child(DEAD_INDEX) as Button
	assert_true(not alive_card.disabled, "за живого можно голосовать")
	assert_true(dead_card.disabled, "за выбывшего голосовать нельзя")
	alive_card.pressed.emit()
	(meeting.get_node(^"%SkipButton") as Button).pressed.emit()
	assert_eq(pressed, [_peer_id(0), MeetingScreen.SKIP_ID] as Array[int], "нажатия уходят сигналом vote_pressed")
	# Подсказка и отметка выбора — по тому, что передал ведущий.
	assert_eq(meeting.get_hint(), MeetingScreen.TEXT_HINT_CAN_VOTE, "подсказка: можно голосовать")
	meeting.mark_own_vote(_peer_id(0))
	meeting.set_can_vote(false)
	assert_eq(meeting.get_hint(), MeetingScreen.TEXT_HINT_VOTED, "подсказка: голос принят")
	assert_true((alive_card.get_node(^"%Tag") as Label).visible, "мой выбор отмечен")
	# Игрок, за которого я голосовал, вышел: он вне игры, отметки нет, подсказка объясняет.
	var entries: Array[MeetingScreen.Entry] = _entries()
	entries[0].alive = false
	meeting.set_entries(entries)
	meeting.mark_own_vote(MeetingScreen.NO_VOTE)
	meeting.set_vote_lost(true)
	assert_true(alive_card.disabled and not (alive_card.get_node(^"%Tag") as Label).visible, "вышедший не отмечен и не нажимается")
	assert_eq(meeting.get_hint(), MeetingScreen.TEXT_HINT_VOTE_LOST, "подсказка: голос пропал")
	meeting.set_vote_lost(false)
	assert_eq(meeting.get_hint(), MeetingScreen.TEXT_HINT_WATCHING, "без голоса и без права голосовать — наблюдатель")
	meeting.open("Собрание", "", _entries())
	meeting.set_stage(MeetingScreen.Stage.VOTING, 30.0)
	assert_eq(meeting.get_hint(), MeetingScreen.TEXT_HINT_WATCHING, "новое собрание забывает пропавший голос")
	await _free_from_tree(meeting)


func test_keypad_typing_erase_and_confirm() -> void:
	var keypad: KeypadPanel = KEYPAD_SCENE.instantiate() as KeypadPanel
	await _add_to_tree(keypad)
	var submitted: Array[String] = []
	keypad.submitted.connect(func(text: String) -> void: submitted.append(text))
	var keys: Node = keypad.get_node(^"%Keys")
	var confirm: Button = keys.get_child(KEY_CONFIRM) as Button
	keypad.open("Ввести код доступа", "4815")
	assert_true(keypad.is_open(), "панель открыта")
	assert_eq(keys.get_child_count(), 12, "клавиш 3x4")
	assert_eq(keypad.get_node(^"%Cells").get_child_count(), 4, "ячеек столько, сколько цифр в коде")
	assert_true(confirm.disabled, "пустой код подтвердить нельзя")
	for index: int in [3, 7, KEY_ZERO, 0, 4]:
		(keys.get_child(index) as Button).pressed.emit()
	assert_eq(keypad.get_entry(), "4801", "лишняя цифра не набирается")
	assert_true(not confirm.disabled, "полный код можно подтвердить")
	(keys.get_child(KEY_ERASE) as Button).pressed.emit()
	assert_eq(keypad.get_entry(), "480", "стёрта последняя цифра")
	confirm.pressed.emit()
	assert_eq(submitted, [] as Array[String], "неполный код не уходит")
	(keys.get_child(4) as Button).pressed.emit()
	confirm.pressed.emit()
	assert_eq(submitted, ["4805"] as Array[String], "код ушёл сигналом submitted")
	# Ошибка: набранное остаётся красным, следующая цифра начинает заново.
	keypad.show_error()
	assert_true(keypad.is_error_shown() and confirm.disabled, "ошибку подтвердить нельзя")
	(keys.get_child(0) as Button).pressed.emit()
	assert_eq(keypad.get_entry(), "1", "после ошибки набор начинается заново")
	assert_true(not keypad.is_error_shown(), "ошибка снята")
	keypad.close()
	assert_true(not keypad.is_open(), "панель закрыта")
	# Мусор на входе: код без цифр, слишком длинный, пустой.
	keypad.open("", "")
	assert_eq(keypad.get_node(^"%Cells").get_child_count(), KeypadPanel.DEFAULT_LENGTH, "без кода ячеек по умолчанию")
	assert_true(not (keypad.get_node(^"%Note") as Control).visible, "без кода наклейки нет")
	keypad.open("Длинный", "1".repeat(40))
	assert_eq(keypad.get_node(^"%Cells").get_child_count(), KeypadPanel.MAX_LENGTH, "ячеек не больше предела")
	await _free_from_tree(keypad)


func test_keypad_keyboard() -> void:
	var keypad: KeypadPanel = KEYPAD_SCENE.instantiate() as KeypadPanel
	await _add_to_tree(keypad)
	var submitted: Array[String] = []
	var cancelled: Array[bool] = []
	keypad.submitted.connect(func(text: String) -> void: submitted.append(text))
	keypad.cancelled.connect(func() -> void: cancelled.append(true))
	keypad.open("Ввести код", "42")
	keypad._unhandled_key_input(_key(KEY_4, "4"))
	keypad._unhandled_key_input(_key(KEY_Q, "q"))
	keypad._unhandled_key_input(_key(KEY_KP_7, "7"))
	assert_eq(keypad.get_entry(), "47", "цифры с верхнего ряда и с цифрового блока, буквы пропущены")
	keypad._unhandled_key_input(_key(KEY_BACKSPACE, ""))
	keypad._unhandled_key_input(_key(KEY_2, "2"))
	keypad._unhandled_key_input(_key(KEY_ENTER, ""))
	assert_eq(submitted, ["42"] as Array[String], "Enter подтверждает")
	var escape: InputEventKey = _key(KEY_ESCAPE, "")
	keypad._unhandled_key_input(escape)
	assert_eq(cancelled.size(), 1, "Esc сообщает об отмене")
	await _free_from_tree(keypad)


func test_results_screen_groups_players_by_team() -> void:
	var results: ResultsScreen = RESULTS_SCENE.instantiate() as ResultsScreen
	await _add_to_tree(results)
	var entries: Array[ResultsScreen.Entry] = []
	for index: int in PLAYER_COUNT:
		var entry: ResultsScreen.Entry = ResultsScreen.Entry.new()
		entry.name = "Игрок %d" % index
		entry.color = PlayerPalette.color(index)
		entry.is_traitor = index == DEAD_INDEX
		entry.alive = index != DEAD_INDEX
		entry.is_self = index == LOCAL_INDEX
		entries.append(entry)
	results.open("Победа экипажа", "Предателей не осталось.", ResultsScreen.Team.CREW, ResultsScreen.Outcome.WON, entries)
	results.set_seconds_left(7.4)
	assert_true(results.is_open(), "итоги открыты")
	assert_eq(results.get_node(^"%CrewList").get_child_count(), PLAYER_COUNT - 1, "экипаж в своей колонке")
	assert_eq(results.get_node(^"%TraitorList").get_child_count(), 1, "предатель в своей колонке")
	assert_eq((results.get_node(^"%Timer") as Label).text, "0:08", "отсчёт до лобби")
	assert_eq((results.get_node(^"%Outcome") as Label).text, ResultsScreen.TEXT_WON, "личный исход")
	# Мы — предатель, и мы проиграли.
	entries[LOCAL_INDEX].is_traitor = true
	results.open("Победа экипажа", "", ResultsScreen.Team.CREW, ResultsScreen.Outcome.LOST, entries)
	assert_eq((results.get_node(^"%Outcome") as Label).text, ResultsScreen.TEXT_LOST, "поражение")
	assert_eq((results.get_node(^"%OutcomeCaption") as Label).text, ResultsScreen.TEXT_ROLE_TRAITOR, "наша роль")
	assert_eq(results.get_node(^"%TraitorList").get_child_count(), 2, "списки пересобраны")
	# Матч без предателей и пустой итог не ломают экран.
	results.open("Матч окончен", "", ResultsScreen.Team.NONE, ResultsScreen.Outcome.WATCHED, [] as Array[ResultsScreen.Entry])
	assert_true(not (results.get_node(^"%Personal") as Control).visible, "наблюдателю личный исход не показан")
	assert_true(not (results.get_node(^"%CrewWon") as Control).visible, "без победителя меток нет")
	results.set_seconds_left(-3.0)
	results.close()
	assert_true(not results.is_open(), "итоги закрыты")
	await _free_from_tree(results)


func test_role_reveal_view() -> void:
	var reveal: RoleReveal = REVEAL_SCENE.instantiate() as RoleReveal
	await _add_to_tree(reveal)
	reveal.show_role(false, PlayerPalette.color(2), PackedStringArray(["Чужой"]), [] as Array[Color])
	reveal.set_seconds_left(4.2)
	assert_true(reveal.is_open(), "экран роли открыт")
	assert_eq((reveal.get_node(^"%RoleName") as Label).text, RoleReveal.TEXT_CREW, "экипаж")
	assert_true(not (reveal.get_node(^"%Partners") as Control).visible, "экипажу напарников не показывают")
	assert_eq((reveal.get_node(^"%Timer") as Label).text, "0:05", "отсчёт")
	reveal.show_role(true, PlayerPalette.color(2), PackedStringArray(["Мила", "Ваня"]), [PlayerPalette.color(6)] as Array[Color])
	assert_eq((reveal.get_node(^"%RoleName") as Label).text, RoleReveal.TEXT_TRAITOR, "предатель")
	assert_eq(reveal.get_node(^"%PartnerList").get_child_count(), 2, "строка на каждого напарника")
	assert_eq((reveal.get_node(^"%PartnersCaption") as Label).text, RoleReveal.TEXT_PARTNERS, "подпись во множественном числе")
	reveal.set_seconds_left(0.0)
	assert_true(not (reveal.get_node(^"%Countdown") as Control).visible, "без паузы отсчёта нет")
	reveal.close()
	assert_true(not reveal.is_open(), "экран роли закрыт")
	await _free_from_tree(reveal)


func test_toasts_stack_without_duplicates() -> void:
	var toasts: HudToasts = TOASTS_SCENE.instantiate() as HudToasts
	await _add_to_tree(toasts)
	toasts.show_toast("Первое", HudToast.Kind.SUCCESS)
	toasts.show_toast("Второе", HudToast.Kind.WARNING)
	toasts.show_toast("Первое", HudToast.Kind.SUCCESS)
	toasts.show_toast("", HudToast.Kind.DANGER)
	assert_eq(toasts.get_texts(), PackedStringArray(["Первое", "Второе"]), "повтор и пустой текст не добавляют строк")
	toasts.show_toast("Третье", HudToast.Kind.DANGER)
	toasts.show_toast("Четвёртое", HudToast.Kind.DANGER)
	assert_eq(toasts.get_texts(), PackedStringArray(["Второе", "Третье", "Четвёртое"]), "новое вытесняет самое старое")
	# Время вышло: уведомление гаснет и освобождает место.
	var newest: HudToast = toasts.get_child(toasts.get_child_count() - 1) as HudToast
	assert_eq(newest.get_text(), "Четвёртое", "новое уведомление стоит снизу")
	(newest.get_node(^"%Life") as Timer).timeout.emit()
	assert_true(not newest.visible, "погасшее уведомление скрыто")
	assert_eq(toasts.get_texts(), PackedStringArray(["Второе", "Третье"]), "место освободилось")
	toasts.clear()
	assert_eq(toasts.get_texts(), PackedStringArray(), "все уведомления убраны")
	await _free_from_tree(toasts)


func test_gauge_zone() -> void:
	assert_eq(HudGauge.zone_of(0.2, 0.6, 0.8), HudGauge.Zone.BEFORE, "до зоны")
	assert_eq(HudGauge.zone_of(0.6, 0.6, 0.8), HudGauge.Zone.INSIDE, "начало зоны уже в зоне")
	assert_eq(HudGauge.zone_of(0.8, 0.6, 0.8), HudGauge.Zone.INSIDE, "конец зоны ещё в зоне")
	assert_eq(HudGauge.zone_of(0.9, 0.6, 0.8), HudGauge.Zone.AFTER, "после зоны")
	var gauge: HudGauge = GAUGE_SCENE.instantiate() as HudGauge
	await _add_to_tree(gauge)
	gauge.show_gauge(0.9, 0.3)
	assert_eq(gauge.get_zone(), Vector2(0.3, 0.9), "перепутанные края зоны встают по порядку")
	gauge.show_gauge(-2.0, 7.0)
	assert_eq(gauge.get_zone(), Vector2(0.0, 1.0), "зона не выходит за шкалу")
	gauge.set_fraction(3.0)
	assert_near(gauge.get_fraction(), 1.0, "заполнение не больше целого")
	gauge.hide_gauge()
	assert_true(not gauge.visible, "шкала спрятана")
	assert_near(gauge.get_fraction(), 0.0, "спрятанная шкала пуста")
	await _free_from_tree(gauge)


func _key(keycode: Key, character: String) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.unicode = character.unicode_at(0) if not character.is_empty() else 0
	event.pressed = true
	return event


func _peer_id(index: int) -> int:
	return 10 + index


func _entries() -> Array[MeetingScreen.Entry]:
	var entries: Array[MeetingScreen.Entry] = []
	for index: int in PLAYER_COUNT:
		var entry: MeetingScreen.Entry = MeetingScreen.Entry.new()
		entry.peer_id = _peer_id(index)
		entry.name = "Игрок %d" % index
		entry.color = PlayerPalette.color(index)
		entry.alive = index != DEAD_INDEX
		entry.is_self = index == LOCAL_INDEX
		entries.append(entry)
	return entries


## Тесты стартуют из _ready запускающей сцены: в этот момент корень дерева ещё занят и детей
## не принимает, поэтому сначала пропускаем кадр.
func _add_to_tree(node: Node) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	tree.root.add_child(node)


func _free_from_tree(node: Node) -> void:
	node.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
