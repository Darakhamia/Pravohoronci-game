extends TestCase
## Ведущий матча (MatchPresenter) без окна и без сети: HUD стоит в дереве, состояние игры
## подставляется в публичные поля Game, Game.tasks, Game.meeting и Game.sabotage, события —
## их же сигналами, а тест смотрит, что получили экраны и элементы HUD.
## Части матча (tasks, meeting, sabotage) на время теста заменены наследниками: у настоящих
## пока нет ответов на вопросы «какие у меня задания» и некуда записать просьбу клиента.
## После каждого теста всё, что тронуто в Net и Game, возвращается на место: остальные тесты
## идут в том же процессе.

const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const MAP_SCENE: PackedScene = preload("res://tests/maps/arena_core.tscn")
## Без подключения multiplayer.get_unique_id() равен 1: это и есть наш игрок.
const LOCAL_ID: int = 1
const VANYA: int = 41
const OLYA: int = 17
const MILA: int = 58
const PEER_IDS: Array[int] = [VANYA, OLYA, LOCAL_ID, MILA]
const PEER_NAMES: PackedStringArray = ["Ваня", "Оля", "Давид", "Мила"]
const PISTOL_ITEM: int = 1
const CODE: String = "4815"
## Клавиши кодовой панели в сетке: цифры 1–9, «стереть», 0, «подтвердить».
const KEY_CONFIRM: int = 11


## Задания: список и отметки задаёт тест, ответы клиента складываются в answers.
class FakeTasks:
	extends TaskBoard
	var ids: PackedInt32Array = []
	var done: Dictionary[int, bool] = {}
	var answers: Array[Array] = []

	func get_local_tasks() -> PackedInt32Array:
		return ids

	func is_local_done(station_id: int) -> bool:
		return done.has(station_id) and done[station_id]

	func is_pending(_peer_id: int, station_id: int) -> bool:
		return ids.has(station_id) and not is_local_done(station_id)

	func request_answer(station_id: int, answer: String) -> void:
		answers.append([station_id, answer])


## Собрание: голоса клиента складываются в requested.
class FakeMeeting:
	extends Meeting
	var requested: Array[int] = []

	func request_vote(target_id: int) -> void:
		requested.append(target_id)


class FakeSabotage:
	extends Sabotage
	var allowed: bool = true

	func can_trigger(_peer_id: int) -> bool:
		return allowed


## Станция-калибратор: ведущий узнаёт её по свойствам zone_start и zone_end.
class FakeCalibrator:
	extends TaskStation
	var zone_start: float = 0.6
	var zone_end: float = 0.8


var _hud: Hud = null
var _presenter: MatchPresenter = null
var _map: GameMap = null
var _player: Player = null
var _wiring: TaskStation = null
var _keypad_station: TaskStation = null
var _calibrator: FakeCalibrator = null
var _tasks: FakeTasks = null
var _meeting: FakeMeeting = null
var _sabotage: FakeSabotage = null
var _real_tasks: TaskBoard = null
var _real_meeting: Meeting = null
var _real_sabotage: Sabotage = null
var _real_state: Game.State = Game.State.LOBBY
var _mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
## Просьбы о курсоре от ведущего: [кто, нужен ли].
var _cursor_log: Array[Array] = []


func test_role_reveal_and_role_chip() -> void:
	await _open(true)
	var reveal: RoleReveal = _view(^"%RoleReveal") as RoleReveal
	var role: HudRole = _view(^"%Role") as HudRole
	assert_true(not reveal.is_open() and not role.visible, "пока роль неизвестна, её нет на экране")
	# Сервер прислал роль; пауза на чтение роли выключена (идёт фаза PLAYING).
	Game.local_role = Game.Role.CREW
	Game.role_assigned.emit(Game.Role.CREW)
	assert_true(reveal.is_open(), "роль показана и без фазы ROLE_REVEAL")
	assert_true(not reveal.is_traitor_shown(), "показан экипаж")
	assert_true(not (reveal.get_node(^"%Countdown") as Control).visible, "без фазы отсчёта нет")
	assert_true(role.visible, "плашка роли в HUD")
	assert_eq((role.get_node(^"%Title") as Label).text, HudRole.TEXT_CREW, "плашка экипажа")
	assert_true(not (_view(^"%Crosshair") as Control).visible, "под экраном роли прицела нет")
	# Минимальное время показа вышло.
	var hold: Timer = _view(^"%RevealHold") as Timer
	assert_true(not hold.is_stopped(), "идёт минимальное время показа")
	hold.stop()
	hold.timeout.emit()
	assert_true(not reveal.is_open(), "экран роли закрыт")
	assert_true((_view(^"%Crosshair") as Control).visible, "прицел вернулся")
	# Обычный матч: фаза ROLE_REVEAL с таймером.
	_set_phase(Game.Phase.ROLE_REVEAL, 5.0)
	assert_true(reveal.is_open(), "экран роли на всю фазу ROLE_REVEAL")
	assert_eq((reveal.get_node(^"%Timer") as Label).text, "0:05", "отсчёт до начала")
	Game.phase_seconds_left = 3.0
	_presenter.refresh_timers()
	assert_eq((reveal.get_node(^"%Timer") as Label).text, "0:03", "отсчёт читается из Game")
	_set_phase(Game.Phase.PLAYING, 0.0)
	assert_true(not reveal.is_open(), "с началом игры экран роли закрыт")
	await _close()


func test_traitor_sees_partner_and_sabotage_chip() -> void:
	await _open(true)
	# Напарников Game хранит у себя, публичного поля для них нет: зовём обработчик пакета сервера.
	Game._receive_role(Game.Role.TRAITOR, PackedInt32Array([MILA]))
	var reveal: RoleReveal = _view(^"%RoleReveal") as RoleReveal
	assert_true(reveal.is_open() and reveal.is_traitor_shown(), "показан предатель")
	assert_eq(reveal.get_partner_names(), PackedStringArray(["Мила"]), "напарник на экране роли")
	var role: HudRole = _view(^"%Role") as HudRole
	assert_eq((role.get_node(^"%Title") as Label).text, HudRole.TEXT_TRAITOR, "плашка предателя")
	assert_eq((role.get_node(^"%Partner") as Label).text, HudRole.TEXT_PARTNER % "Мила", "напарник в плашке")
	var ability: HudAbility = _view(^"%Ability") as HudAbility
	var key: HudKeyCap = ability.get_node(^"%Key") as HudKeyCap
	assert_true(ability.visible, "плашка саботажа у предателя")
	assert_eq(key.text, MatchText.KEY_SABOTAGE, "клавиша саботажа")
	assert_true(not key.is_dimmed(), "саботаж доступен")
	_sabotage.cooldown_left = 11.2
	_sabotage.allowed = false
	_sabotage.cooldown_changed.emit()
	assert_true(key.is_dimmed(), "на перезарядке клавиша приглушена")
	assert_eq((ability.get_node(^"%Cooldown") as Label).text, HudAbility.TEXT_COOLDOWN % 12, "секунды перезарядки")
	_sabotage.cooldown_left = 0.0
	_sabotage.cooldown_changed.emit()
	assert_true(key.is_dimmed(), "перезарядка прошла, но сервер ещё не разрешает — клавиша приглушена")
	_player.life = Player.Life.CORPSE
	assert_true(not ability.visible, "мёртвый предатель саботаж не включает")
	await _close()


func test_tasks_list_progress_and_done_toast() -> void:
	await _open(true)
	var tasks: HudTasks = _view(^"%Tasks") as HudTasks
	var toasts: HudToasts = _view(^"%Toasts") as HudToasts
	assert_true(not tasks.visible, "без заданий и прогресса панели нет")
	_tasks.ids = PackedInt32Array([_wiring.interact_id, _keypad_station.interact_id, _calibrator.interact_id])
	_tasks.total_count = 12
	_tasks.done_count = 5
	_tasks.local_tasks_changed.emit()
	_tasks.progress_changed.emit()
	assert_true(tasks.visible, "панель заданий показана")
	assert_eq(tasks.get_shown_titles(), PackedStringArray(["Починить проводку — Реактор", "Ввести код доступа",
			"Откалибровать датчик — Мостик"]), "названия берутся у станций карты")
	assert_eq((tasks.get_node(^"%ProgressCount") as Label).text, "5/12", "общий прогресс экипажа")
	assert_eq(toasts.get_texts(), PackedStringArray(), "первое появление списка — без уведомлений")
	# Задание сделано: отметка, строка тонет вниз, уведомление.
	_tasks.done[_wiring.interact_id] = true
	_tasks.done_count = 6
	_tasks.local_tasks_changed.emit()
	_tasks.progress_changed.emit()
	assert_eq(tasks.get_shown_titles()[2], "Починить проводку — Реактор", "выполненное задание внизу")
	assert_eq(tasks.get_shown_done(), [false, false, true] as Array[bool], "отметка выполнения")
	assert_eq((tasks.get_node(^"%ProgressCount") as Label).text, "6/12", "прогресс обновился")
	assert_eq(toasts.get_texts(), PackedStringArray(["Готово: Починить проводку"]), "уведомление о задании")
	_tasks.local_tasks_changed.emit()
	assert_eq(toasts.get_texts().size(), 1, "то же задание второй раз не объявляется")
	# Карта исчезла: названий больше нет, но список остаётся.
	_hud.set_map(null)
	assert_eq(tasks.get_shown_titles().size(), 3, "без карты задания не пропадают")
	assert_eq(tasks.get_shown_titles()[0], MatchText.TASK_UNKNOWN, "без карты у задания нет названия")
	await _close()


func test_vitals_weapon_and_death() -> void:
	await _open(true)
	var vitals: HudVitals = _view(^"%Vitals") as HudVitals
	var weapon: HudWeapon = _view(^"%Weapon") as HudWeapon
	var banner: HudBanner = _view(^"%Banner") as HudBanner
	var toasts: HudToasts = _view(^"%Toasts") as HudToasts
	var crosshair: Control = _view(^"%Crosshair") as Control
	_tasks.total_count = 12
	_tasks.progress_changed.emit()
	assert_true(vitals.visible and weapon.visible and crosshair.visible, "живой игрок видит боевой HUD")
	assert_true(not banner.visible, "живому игроку строка внизу не нужна")
	assert_eq((vitals.get_node(^"%Health") as Label).text, str(PlayerBody.CONFIG.max_health), "полное здоровье")
	assert_eq((weapon.get_node(^"%Title") as Label).text, PlayerWeapons.ITEMS.get_item(PlayerWeapons.EMPTY_HANDS).title,
			"в руках кулаки")
	assert_true(not (weapon.get_node(^"%Ammo") as Label).visible, "у кулаков нет счётчика патронов")
	# Сервер прислал здоровье и оторвал ногу.
	var parts: PackedInt32Array = _player.body.part_health.duplicate()
	parts[BodyPart.Part.LEFT_LEG] = 0
	_player.body.apply_vitals(64, parts)
	_player.limbs_lost = BodyPart.bit(BodyPart.Part.LEFT_LEG)
	assert_eq((vitals.get_node(^"%Health") as Label).text, "64", "здоровье с сервера")
	assert_eq(toasts.get_texts(), PackedStringArray(["Потеряна левая нога"]), "уведомление о потерянной конечности")
	_player.held_item = PISTOL_ITEM
	assert_eq((weapon.get_node(^"%Title") as Label).text, PlayerWeapons.ITEMS.get_item(PISTOL_ITEM).title,
			"в руках пистолет")
	# Смерть: боевого HUD нет, задания остаются, внизу строка призрака.
	_player.life = Player.Life.CORPSE
	assert_true(not vitals.visible and not weapon.visible and not crosshair.visible, "у мёртвого нет боевого HUD")
	assert_true((_view(^"%Tasks") as HudTasks).visible, "прогресс заданий остаётся")
	assert_true(banner.visible, "строка призрака показана")
	assert_eq((banner.get_node(^"%Text") as Label).text, MatchText.BANNER_GHOST, "текст призрака")
	# Аватар исчез вместе с картой.
	_hud.set_map(null)
	assert_true(not vitals.visible and not weapon.visible, "без аватара боевого HUD нет")
	await _close()


func test_prompt_hold_and_calibrator_gauge() -> void:
	await _open(true)
	var prompt: HudPrompt = _view(^"%Prompt") as HudPrompt
	var gauge: HudGauge = _view(^"%Gauge") as HudGauge
	var key: HudKeyCap = prompt.get_node(^"%Key") as HudKeyCap
	assert_true(not prompt.visible and not gauge.visible, "пока под прицелом пусто, подсказки нет")
	_focus(_wiring)
	assert_true(prompt.visible, "подсказка под прицелом")
	assert_eq(key.text, MatchText.KEY_INTERACT, "клавиша действия")
	assert_eq((prompt.get_node(^"%Action") as Label).text, "Починить", "текст подсказки от предмета")
	assert_true(not gauge.visible, "у обычной станции шкалы нет")
	_hold(0.5)
	assert_near(key.get_hold(), 0.5, "удержание рисует рамка клавиши")
	# Калибратор: вместо рамки — шкала с зелёной зоной.
	_hold(0.0)
	_focus(_calibrator)
	assert_true(gauge.visible, "у калибратора шкала")
	assert_eq(gauge.get_zone(), Vector2(0.6, 0.8), "зелёная зона взята у станции")
	_hold(0.7)
	assert_near(gauge.get_fraction(), 0.7, "шкала заполняется удержанием")
	assert_near(key.get_hold(), 0.0, "рамка клавиши у калибратора пуста")
	_focus(null)
	assert_true(not prompt.visible and not gauge.visible, "прицел ушёл — подсказка и шкала спрятаны")
	# Вне игры (собрание) подсказок нет, даже если предмет под прицелом.
	_focus(_wiring)
	_set_phase(Game.Phase.MEETING, 0.0)
	assert_true(not prompt.visible, "на собрании подсказки нет")
	await _close()


func test_sabotage_alert() -> void:
	await _open(true)
	var alert: HudAlert = _view(^"%Alert") as HudAlert
	assert_true(not alert.visible, "без саботажа тревоги нет")
	_sabotage.active = true
	_sabotage.seconds_left = 38.0
	_sabotage.started.emit()
	assert_true(alert.visible, "тревога показана")
	assert_eq((alert.get_node(^"%Title") as Label).text, MatchText.ALERT_REACTOR, "название тревоги")
	assert_eq((alert.get_node(^"%Time") as Label).text, "0:38", "отсчёт до взрыва")
	_sabotage.seconds_left = 36.5
	_presenter.refresh_timers()
	assert_eq((alert.get_node(^"%Time") as Label).text, "0:37", "отсчёт читается из Game.sabotage")
	_sabotage.active = false
	_sabotage.ended.emit(true)
	assert_true(not alert.visible, "починили — тревоги нет")
	await _close()


func test_meeting_from_start_to_verdict() -> void:
	await _open(true)
	var meeting: MeetingScreen = _view(^"%Meeting") as MeetingScreen
	var cards: Node = meeting.get_node(^"%Cards")
	var skip: Button = meeting.get_node(^"%SkipButton") as Button
	# Нашли тело Милы: на собрании трое живых.
	_meeting.caller_id = VANYA
	_meeting.reason = Meeting.Reason.BODY
	_meeting.victim_id = MILA
	_meeting.attendees = PackedInt32Array([VANYA, OLYA, LOCAL_ID])
	_meeting.stage = Meeting.Stage.DISCUSSION
	_meeting.stage_seconds_left = 15.0
	_set_phase(Game.Phase.MEETING, 0.0)
	_meeting.started.emit()
	assert_true(meeting.visible, "экран собрания открыт")
	assert_true(_cursor_log.has([MatchPresenter.CURSOR_MEETING, true]), "собрание просит курсор")
	assert_eq((meeting.get_node(^"%Title") as Label).text, "Найдено тело", "заголовок")
	assert_eq((meeting.get_node(^"%Deck") as Label).text, "Тело: Мила. Сообщает Ваня.", "повод собрания")
	assert_eq((meeting.get_node(^"%Timer") as Label).text, "0:15", "таймер стадии")
	assert_eq(_visible_count(cards), PEER_IDS.size(), "карточка на каждого участника матча")
	assert_true((cards.get_child(0) as Button).disabled, "в обсуждении голосовать нельзя")
	# Голосование.
	_meeting.stage = Meeting.Stage.VOTING
	_meeting.stage_seconds_left = 30.0
	_meeting.stage_changed.emit(Meeting.Stage.VOTING)
	assert_eq((meeting.get_node(^"%Timer") as Label).text, "0:30", "таймер голосования")
	assert_true(not (cards.get_child(1) as Button).disabled, "за живого можно голосовать")
	assert_true((cards.get_child(3) as Button).disabled, "за мёртвого голосовать нельзя")
	assert_true(skip.visible and not skip.disabled, "можно пропустить")
	(cards.get_child(1) as Button).pressed.emit()
	assert_eq(_meeting.requested, [OLYA] as Array[int], "голос ушёл серверу")
	assert_true((cards.get_child(0) as Button).disabled, "второй раз голосовать нельзя")
	(cards.get_child(0) as Button).pressed.emit()
	skip.pressed.emit()
	assert_eq(_meeting.requested.size(), 1, "повторные нажатия серверу не уходят")
	_meeting.voted[LOCAL_ID] = true
	_meeting.vote_cast.emit(LOCAL_ID)
	_meeting.voted[VANYA] = true
	_meeting.vote_cast.emit(VANYA)
	assert_true(meeting.visible, "собрание продолжается")
	# Вердикт: стадия и итог могут прийти в любом порядке.
	_meeting.votes = {VANYA: OLYA, LOCAL_ID: OLYA, OLYA: MatchRules.SKIP_VOTE}
	_meeting.ejected_id = OLYA
	_meeting.ejected_role = Game.Role.CREW
	_meeting.stage = Meeting.Stage.VERDICT
	_meeting.stage_seconds_left = 6.0
	_meeting.verdict_ready.emit()
	_meeting.stage_changed.emit(Meeting.Stage.VERDICT)
	assert_eq((meeting.get_node(^"%Deck") as Label).text, "Оля за бортом.\nЭто был не предатель.", "вердикт")
	assert_eq(meeting.get_node(^"%SkipVoters").get_child_count(), 1, "пропустившие показаны")
	assert_true(not skip.visible, "в итоге «Пропустить» нет")
	# Конец собрания.
	_meeting.closed.emit()
	assert_true(not meeting.visible, "экран собрания закрыт по сигналу closed")
	_meeting.stage = Meeting.Stage.NONE
	_meeting.stage_changed.emit(Meeting.Stage.NONE)
	_set_phase(Game.Phase.PLAYING, 0.0)
	assert_true(not meeting.visible, "после собрания экран не возвращается")
	assert_true(_cursor_log.has([MatchPresenter.CURSOR_MEETING, false]), "курсор отдан")
	# Следующее собрание по кнопке: свой голос забыт.
	_meeting.reason = Meeting.Reason.BUTTON
	_meeting.victim_id = 0
	_meeting.voted.clear()
	_meeting.votes.clear()
	_meeting.ejected_id = MatchRules.SKIP_VOTE
	_meeting.stage = Meeting.Stage.VOTING
	_set_phase(Game.Phase.MEETING, 0.0)
	_meeting.started.emit()
	assert_eq((meeting.get_node(^"%Deck") as Label).text, "Ваня жмёт тревожную кнопку", "повод — кнопка")
	assert_true(not (cards.get_child(0) as Button).disabled, "на новом собрании снова можно голосовать")
	skip.pressed.emit()
	assert_eq(_meeting.requested, [OLYA, MatchRules.SKIP_VOTE] as Array[int], "пропуск ушёл серверу")
	_meeting.ejected_id = MatchRules.SKIP_VOTE
	_meeting.stage = Meeting.Stage.VERDICT
	_meeting.verdict_ready.emit()
	assert_eq((meeting.get_node(^"%Deck") as Label).text, MatchText.VERDICT_NOBODY, "никого не изгнали")
	await _close()


func test_spectator_joins_during_meeting() -> void:
	# Мы вошли посреди матча: аватара нет, в участниках нас нет, собрание уже идёт.
	Game.participants = PackedInt32Array([VANYA, OLYA, MILA])
	await _open(false, func() -> void:
		_meeting.caller_id = OLYA
		_meeting.reason = Meeting.Reason.BUTTON
		_meeting.attendees = PackedInt32Array([VANYA, OLYA, MILA])
		_meeting.stage = Meeting.Stage.VOTING
		_meeting.stage_seconds_left = 20.0
		Game.phase = Game.Phase.MEETING)
	var meeting: MeetingScreen = _view(^"%Meeting") as MeetingScreen
	assert_true(meeting.visible, "собрание показано сразу")
	assert_true((meeting.get_node(^"%Cards").get_child(0) as Button).disabled, "наблюдатель не голосует")
	assert_true(not (meeting.get_node(^"%SkipButton") as Button).visible, "наблюдателю не предлагают пропустить")
	_meeting.stage = Meeting.Stage.NONE
	_meeting.closed.emit()
	_set_phase(Game.Phase.PLAYING, 0.0)
	var banner: HudBanner = _view(^"%Banner") as HudBanner
	assert_true(banner.visible, "строка наблюдателя")
	assert_eq((banner.get_node(^"%Text") as Label).text, MatchText.BANNER_SPECTATOR, "текст наблюдателя")
	assert_true(not (_view(^"%Vitals") as Control).visible and not (_view(^"%Role") as Control).visible,
			"у наблюдателя нет ни роли, ни здоровья")
	assert_true(not (_view(^"%Crosshair") as Control).visible, "у наблюдателя нет прицела")
	# Итоги наблюдатель тоже видит, но без личного исхода.
	_finish_match(Game.Winner.TRAITORS, Game.EndReason.SABOTAGE)
	var results: ResultsScreen = _view(^"%Results") as ResultsScreen
	assert_true(results.is_open(), "итоги показаны наблюдателю")
	assert_true(not (results.get_node(^"%Personal") as Control).visible, "личного исхода у наблюдателя нет")
	await _close()


func test_results_and_reset_after_match() -> void:
	await _open(true)
	Game.local_role = Game.Role.CREW
	Game.role_assigned.emit(Game.Role.CREW)
	_tasks.total_count = 12
	_tasks.progress_changed.emit()
	_sabotage.active = true
	_sabotage.started.emit()
	var results: ResultsScreen = _view(^"%Results") as ResultsScreen
	assert_true(not results.is_open(), "пока матч идёт, итогов нет")
	_finish_match(Game.Winner.CREW, Game.EndReason.TASKS_DONE)
	assert_true(results.is_open(), "итоги открыты")
	assert_true(_cursor_log.has([MatchPresenter.CURSOR_RESULTS, true]), "итоги просят курсор")
	assert_eq((results.get_node(^"%Title") as Label).text, "Победа экипажа", "кто победил")
	assert_eq((results.get_node(^"%Reason") as Label).text, "Экипаж выполнил все задания.", "почему")
	assert_eq((results.get_node(^"%Outcome") as Label).text, ResultsScreen.TEXT_WON, "мы победили")
	assert_eq((results.get_node(^"%OutcomeCaption") as Label).text, ResultsScreen.TEXT_ROLE_CREW, "наша роль")
	assert_eq((results.get_node(^"%Timer") as Label).text, "0:10", "отсчёт до лобби")
	assert_true((results.get_node(^"%CrewWon") as Control).visible, "метка победы у экипажа")
	assert_true(not (results.get_node(^"%TraitorsWon") as Control).visible, "у предателей метки нет")
	var crew_rows: Array[Node] = results.get_node(^"%CrewList").get_children()
	var traitor_rows: Array[Node] = results.get_node(^"%TraitorList").get_children()
	assert_eq(crew_rows.size(), 3, "экипаж в своей колонке")
	assert_eq(traitor_rows.size(), 1, "предатель в своей колонке")
	var own_row: ResultsPlayerRow = crew_rows[2] as ResultsPlayerRow
	assert_eq(own_row.get_player_name(), "Давид", "наша строка")
	assert_true(own_row.is_marked_self() and not own_row.is_marked_out(), "мы отмечены и живы")
	var traitor_row: ResultsPlayerRow = traitor_rows[0] as ResultsPlayerRow
	assert_eq(traitor_row.get_player_name(), "Мила", "роль предателя раскрыта")
	assert_true(traitor_row.is_marked_out(), "предатель выбыл")
	assert_true(not (_view(^"%Alert") as Control).visible, "на итогах тревоги нет")
	# Сервер вернул всех в лобби: фаза NONE.
	_set_phase(Game.Phase.NONE, 0.0)
	assert_true(not results.is_open(), "итоги закрыты")
	assert_true(_cursor_log.has([MatchPresenter.CURSOR_RESULTS, false]), "курсор отдан")
	for path: NodePath in [^"%Role", ^"%Tasks", ^"%Vitals", ^"%Weapon", ^"%Ability", ^"%Alert", ^"%Banner",
			^"%Prompt", ^"%RoleReveal", ^"%Meeting", ^"%Keypad"]:
		assert_true(not (_view(path) as Control).visible, "после матча %s скрыт" % path)
	await _close()


func test_keypad_task() -> void:
	await _open(true)
	var keypad: KeypadPanel = _view(^"%Keypad") as KeypadPanel
	var keys: Node = keypad.get_node(^"%Keys")
	var toasts: HudToasts = _view(^"%Toasts") as HudToasts
	var station_id: int = _keypad_station.interact_id
	_tasks.task_opened.emit(_wiring.interact_id, {})
	assert_true(not keypad.is_open(), "задание без кода панель не открывает")
	_tasks.task_opened.emit(station_id, {"code": CODE})
	assert_true(keypad.is_open(), "кодовая панель открыта")
	assert_true(_cursor_log.has([MatchPresenter.CURSOR_KEYPAD, true]), "панель просит курсор")
	assert_eq((keypad.get_node(^"%Title") as Label).text, "Ввести код доступа", "название задания")
	assert_eq((keypad.get_node(^"%Code") as Label).text, CODE, "код на наклейке")
	assert_true(not (_view(^"%Crosshair") as Control).visible, "под панелью прицела нет")
	# Набираем 4 8 1 5 и подтверждаем.
	for digit: String in CODE:
		(keys.get_child(_key_index(digit)) as Button).pressed.emit()
	(keys.get_child(KEY_CONFIRM) as Button).pressed.emit()
	assert_eq(_tasks.answers, [[station_id, CODE]] as Array[Array], "ответ ушёл серверу")
	# Сервер не принял код.
	_tasks.task_feedback.emit(station_id, false)
	assert_true(keypad.is_open() and keypad.is_error_shown(), "панель показывает ошибку и остаётся")
	assert_eq(toasts.get_texts(), PackedStringArray([MatchText.TOAST_WRONG_CODE]), "уведомление о неверном коде")
	# Сервер принял код.
	_tasks.task_feedback.emit(station_id, true)
	assert_true(not keypad.is_open(), "после верного кода панель закрыта")
	assert_true(_cursor_log.has([MatchPresenter.CURSOR_KEYPAD, false]), "курсор отдан")
	# Esc закрывает панель.
	_tasks.task_opened.emit(station_id, {"code": CODE})
	keypad.cancelled.emit()
	assert_true(not keypad.is_open(), "Esc закрывает панель")
	# Игра ушла из PLAYING.
	_tasks.task_opened.emit(station_id, {"code": CODE})
	_set_phase(Game.Phase.MEETING, 0.0)
	assert_true(not keypad.is_open(), "собрание закрывает панель")
	_tasks.task_opened.emit(station_id, {"code": CODE})
	assert_true(not keypad.is_open(), "вне игры панель не открывается")
	# Игрок умер.
	_set_phase(Game.Phase.PLAYING, 0.0)
	_tasks.task_opened.emit(station_id, {"code": CODE})
	assert_true(keypad.is_open(), "в игре панель открывается снова")
	_player.life = Player.Life.CORPSE
	assert_true(not keypad.is_open(), "смерть закрывает панель")
	# Промах у калибратора — отдельное уведомление.
	toasts.clear()
	_tasks.task_feedback.emit(_calibrator.interact_id, false)
	assert_eq(toasts.get_texts(), PackedStringArray([MatchText.TOAST_MISSED_ZONE]), "мимо зелёной зоны")
	await _close()


func test_hidden_hud_shows_nothing_until_visible() -> void:
	await _open(true)
	_hud.visible = false
	Game.local_role = Game.Role.CREW
	Game.role_assigned.emit(Game.Role.CREW)
	_sabotage.active = true
	_sabotage.started.emit()
	_tasks.task_opened.emit(_keypad_station.interact_id, {"code": CODE})
	assert_true(not (_view(^"%Alert") as Control).visible, "скрытый HUD не показывает тревогу")
	assert_true(not (_view(^"%Keypad") as KeypadPanel).is_open(), "скрытый HUD не открывает панель")
	assert_true(not _presenter.is_processing(), "скрытый HUD не работает каждый кадр")
	# HUD появился посреди матча: всё берётся из текущего состояния.
	_hud.visible = true
	assert_true((_view(^"%Alert") as Control).visible, "тревога взята из состояния")
	assert_true((_view(^"%Role") as Control).visible, "роль взята из состояния")
	assert_true((_view(^"%RoleReveal") as RoleReveal).is_open(), "роль, пришедшая до HUD, всё равно показана")
	assert_true((_view(^"%Vitals") as Control).visible, "здоровье взято из состояния")
	await _close()


# --- Подготовка и уборка ---


## Ставит в дерево карту со станциями, HUD и (если with_player) наш аватар; Net и Game
## переводит в «идёт матч, фаза PLAYING». before_hud — что ещё подставить до появления HUD.
func _open(with_player: bool, before_hud: Callable = Callable()) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	# Тесты стартуют из _ready запускающей сцены: корень дерева ещё занят и детей не принимает.
	await tree.process_frame
	_mouse_mode = Input.mouse_mode
	_cursor_log = []
	Net.status = Net.Status.JOINED
	for index: int in PEER_IDS.size():
		Net.players[PEER_IDS[index]] = PEER_NAMES[index]
		Net.player_colors[PEER_IDS[index]] = index
	Net.host_id = VANYA
	_real_tasks = Game.tasks
	_real_meeting = Game.meeting
	_real_sabotage = Game.sabotage
	_real_state = Game.state
	_tasks = FakeTasks.new()
	_meeting = FakeMeeting.new()
	_sabotage = FakeSabotage.new()
	Game.tasks = _tasks
	Game.meeting = _meeting
	Game.sabotage = _sabotage
	if Game.participants.is_empty():
		Game.participants = PackedInt32Array(PEER_IDS)
	Game.state = Game.State.MATCH
	Game.phase = Game.Phase.PLAYING
	if before_hud.is_valid():
		before_hud.call()

	_map = MAP_SCENE.instantiate() as GameMap
	_wiring = _add_station(TaskStation.new(), "Починить проводку", "Реактор", "Починить")
	_keypad_station = _add_station(TaskStation.new(), "Ввести код доступа", "", "Ввести код")
	_calibrator = _add_station(FakeCalibrator.new(), "Откалибровать датчик", "Мостик", "Калибровать") as FakeCalibrator
	tree.root.add_child(_map)
	_hud = HUD_SCENE.instantiate() as Hud
	tree.root.add_child(_hud)
	_presenter = _hud.get_node(^"%Match") as MatchPresenter
	_presenter.cursor_needed.connect(_on_cursor_needed)
	_hud.set_map(_map)
	if with_player:
		_player = GameMap.PLAYER_SCENE.instantiate() as Player
		_player.name = str(LOCAL_ID)
		_player.map = _map
		_map.get_node(^"Players").add_child(_player)
		# Прицел в тесте наводим сами: свой поиск предмета аватару не нужен.
		_player.interactor.set_physics_process(false)
		_map.player_added.emit(_player)


func _close() -> void:
	_hud.queue_free()
	_map.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
	_hud = null
	_presenter = null
	_map = null
	_player = null
	Game.tasks = _real_tasks
	Game.meeting = _real_meeting
	Game.sabotage = _real_sabotage
	_tasks.free()
	_meeting.free()
	_sabotage.free()
	Game.state = _real_state
	Game.phase = Game.Phase.NONE
	Game.phase_seconds_left = 0.0
	Game.participants = PackedInt32Array()
	Game.local_role = Game.Role.NONE
	Game.last_result = null
	# Роли, пришедшие «пакетом сервера» и с итогами матча.
	Game._roles.clear()
	Net.status = Net.Status.OFFLINE
	Net.players.clear()
	Net.player_colors.clear()
	Net.host_id = 0
	Input.mouse_mode = _mouse_mode


func _add_station(station: TaskStation, title: String, location: String, prompt: String) -> TaskStation:
	station.title = title
	station.location = location
	station.prompt = prompt
	_map.add_child(station)
	return station


func _view(path: NodePath) -> Node:
	return _hud.get_node(path)


func _set_phase(phase: Game.Phase, seconds_left: float) -> void:
	Game.phase = phase
	Game.phase_seconds_left = seconds_left
	Game.phase_changed.emit(phase)


## Наводит прицел аватара на предмет (null — в пустоту), как это делает PlayerInteractor.
func _focus(target: Interactable) -> void:
	_player.interactor.focus = target
	_player.interactor.focus_changed.emit(target)


func _hold(fraction: float) -> void:
	_player.interactor.hold_fraction = fraction
	_player.interactor.hold_changed.emit(fraction)


## Сервер закончил матч: фаза ENDED и итог по участникам, в котором Мила — предатель
## и не дожила до конца.
func _finish_match(winner: Game.Winner, reason: Game.EndReason) -> void:
	var result: MatchResult = MatchResult.new()
	result.winner = winner
	result.reason = reason
	for peer_id: int in Game.participants:
		var index: int = PEER_IDS.find(peer_id)
		var is_traitor: bool = peer_id == MILA
		result.add_entry(peer_id, PEER_NAMES[index], index,
				Game.Role.TRAITOR if is_traitor else Game.Role.CREW, not is_traitor)
	Game.last_result = result
	_set_phase(Game.Phase.ENDED, 10.0)
	Game.match_ended.emit(result)


func _visible_count(parent: Node) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if (child as CanvasItem).visible:
			count += 1
	return count


## Номер клавиши с цифрой в сетке кодовой панели: 1–9 идут подряд, ноль — после «стереть».
func _key_index(digit: String) -> int:
	return KEY_CONFIRM - 1 if digit == KeypadPanel.ZERO else KeypadPanel.DIGITS.find(digit)


func _on_cursor_needed(who: StringName, needed: bool) -> void:
	_cursor_log.append([who, needed])
