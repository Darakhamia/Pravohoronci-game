class_name MatchPresenter
extends Control
## Ведущий матча (узел Match в hud.tscn): единственное место интерфейса, которое читает
## состояние игры — Game и его части (tasks, meeting, sabotage), Net и свой аватар — и
## раздаёт его экранам и элементам HUD. Сами они «глупые»: получают готовые данные.
## Все они — дети этого узла; наверх уходит только просьба о курсоре (cursor_needed).
##
## Карту, свой аватар и паузу сообщает Hud. Порядок событий может быть любым (роль раньше
## фазы, HUD появился посреди собрания, у наблюдателя аватара нет), поэтому каждое событие
## заново сверяет нужную часть экрана с состоянием, а не достраивает её по шагам.
## Таймеры читаются из полей Game каждый кадр — своих часов для них тут нет. Пока HUD
## скрыт и без окна (сервер, боты, тесты) покадровой работы нет вовсе: надписи обновляются
## по событиям.

## Экрану поверх матча нужен (или больше не нужен) курсор. Слушает Hud.
signal cursor_needed(who: StringName, needed: bool)

const CURSOR_MEETING: StringName = &"meeting"
const CURSOR_RESULTS: StringName = &"results"
const CURSOR_KEYPAD: StringName = &"keypad"
## Роль остаётся на экране не меньше этого, даже если пауза на чтение роли выключена.
const REVEAL_MIN_SEC: float = 2.5
const NO_STATION: int = Interactable.NO_ID
## Станцию-калибратор узнаём по этим свойствам: начало и конец зелёной зоны в долях удержания.
const ZONE_START_PROPERTY: StringName = &"zone_start"
const ZONE_END_PROPERTY: StringName = &"zone_end"
const HEADLESS_DISPLAY: String = "headless"
const FULL: float = 1.0

var _map: GameMap = null
var _player: Player = null
## Привязан ли сейчас аватар: сам _player мог быть удалён раньше, чем нам о нём сообщили.
var _player_bound: bool = false
var _paused: bool = false
## Имена и номера цветов игроков, какими мы их видели: вышедший остаётся на собрании.
var _names: Dictionary[int, String] = {}
var _colors: Dictionary[int, int] = {}
var _meeting_open: bool = false
## Собрание уже объявлено закрытым, хотя его стадия ещё не сброшена: заново не открываем.
var _meeting_dismissed: bool = false
## За кого мы проголосовали на этом собрании (MeetingScreen.NO_VOTE — ещё нет).
var _own_vote: int = MeetingScreen.NO_VOTE
var _results_open: bool = false
## Станция, чью кодовую панель мы открыли.
var _keypad_station: int = NO_STATION
## Какие задания были сделаны при прошлой сверке — чтобы сообщить о новых.
var _done_seen: Dictionary[int, bool] = {}
## Потерянные конечности при прошлой сверке.
var _limbs_seen: int = 0

@onready var _alert: HudAlert = %Alert
@onready var _crosshair: Control = %Crosshair
@onready var _views: Control = %Views
@onready var _prompt: HudPrompt = %Prompt
@onready var _gauge: HudGauge = %Gauge
@onready var _role: HudRole = %Role
@onready var _tasks: HudTasks = %Tasks
@onready var _banner: HudBanner = %Banner
@onready var _vitals: HudVitals = %Vitals
@onready var _ability: HudAbility = %Ability
@onready var _weapon: HudWeapon = %Weapon
@onready var _toasts: HudToasts = %Toasts
@onready var _keypad: KeypadPanel = %Keypad
@onready var _reveal: RoleReveal = %RoleReveal
@onready var _meeting: MeetingScreen = %Meeting
@onready var _results: ResultsScreen = %Results
@onready var _reveal_hold: Timer = %RevealHold


func _ready() -> void:
	set_process(false)
	visibility_changed.connect(_on_visibility_changed)
	Net.lobby_changed.connect(_on_lobby_changed)
	Game.phase_changed.connect(_on_phase_changed)
	Game.role_assigned.connect(_on_role_assigned)
	Game.match_ended.connect(_sync_results.unbind(1))
	Game.tasks.progress_changed.connect(_sync_tasks)
	Game.tasks.local_tasks_changed.connect(_sync_tasks)
	Game.tasks.task_opened.connect(_on_task_opened)
	Game.tasks.task_feedback.connect(_on_task_feedback)
	Game.meeting.started.connect(_on_meeting_started)
	Game.meeting.stage_changed.connect(_sync_meeting.unbind(1))
	Game.meeting.vote_cast.connect(_sync_meeting.unbind(1))
	Game.meeting.verdict_ready.connect(_sync_meeting)
	Game.meeting.closed.connect(_on_meeting_closed)
	Game.sabotage.started.connect(_sync_sabotage)
	Game.sabotage.ended.connect(_sync_sabotage.unbind(1))
	Game.sabotage.cooldown_changed.connect(_sync_ability)
	_meeting.vote_pressed.connect(_on_vote_pressed)
	_keypad.submitted.connect(_on_keypad_submitted)
	_keypad.cancelled.connect(_close_keypad)
	_reveal_hold.timeout.connect(_sync_reveal)
	# Сверку здесь не делаем: Hud ещё не слушает cursor_needed. Он вызовет sync() сам.
	_update_processing()


## Раз в кадр, только пока HUD виден и есть окно: таймеры экранов из полей игры.
func _process(_delta: float) -> void:
	refresh_timers()


# --- Что сообщает Hud ---


## Карта матча сменилась или исчезла (null). По ней находятся станции заданий.
func set_map(map: GameMap) -> void:
	if map == _map:
		return
	_map = map
	if map == null:
		_close_keypad()
	_sync_tasks()


## Свой аватар появился или исчез (null — мы наблюдатель или карта выгружена).
func set_local_player(player: Player) -> void:
	if is_instance_valid(_player):
		if player == _player:
			return
	elif player == null and not _player_bound:
		return
	_unbind_player()
	_player = player
	_player_bound = player != null
	if player != null:
		player.life_changed.connect(_on_life_changed)
		player.limbs_changed.connect(_on_limbs_changed)
		player.held_item_changed.connect(_on_held_item_changed)
		player.body.vitals_changed.connect(_sync_vitals)
		player.weapons.loadout_changed.connect(_sync_weapon)
		player.interactor.focus_changed.connect(_on_focus_changed)
		player.interactor.hold_changed.connect(_on_hold_changed)
		player.input.fire_pressed.connect(_on_fire_pressed)
		_limbs_seen = player.limbs_lost
	else:
		_limbs_seen = 0
		_close_keypad()
	_sync_player()


## Под паузой углы HUD и уведомления спрятаны; тревога и экраны поверх матча остаются.
func set_paused(paused: bool) -> void:
	if paused == _paused:
		return
	_paused = paused
	_sync_layers()


## Обновляет все таймеры на экране из полей игры. С окном вызывается каждый кадр, без окна —
## по событиям.
func refresh_timers() -> void:
	if _reveal.is_open():
		_reveal.set_seconds_left(_reveal_seconds_left())
	if _meeting_open:
		_meeting.set_stage(_meeting_stage(), Game.meeting.stage_seconds_left)
	if _results_open:
		_results.set_seconds_left(Game.phase_seconds_left)
	if _alert.visible:
		_alert.show_alert(MatchText.ALERT_REACTOR, Game.sabotage.seconds_left)
	if _ability.visible:
		_show_ability()


# --- Общая сверка ---


## Сверяет с состоянием игры весь экран матча. Hud вызывает это один раз, когда готов
## слушать cursor_needed; дальше ведущий сверяется сам — по событиям игры и при появлении HUD.
func sync() -> void:
	if not is_visible_in_tree():
		return
	_remember_players()
	_sync_role()
	_sync_tasks()
	_sync_player()
	_sync_sabotage()
	_sync_reveal()
	_sync_meeting()
	_sync_results()
	_sync_layers()


## Матч закончился или HUD скрыт: всё закрыть и забыть.
func _reset() -> void:
	_close_keypad()
	_close_meeting()
	_close_results()
	_reveal_hold.stop()
	_reveal.close()
	_toasts.clear()
	_alert.hide_alert()
	_prompt.hide_prompt()
	_gauge.hide_gauge()
	_banner.hide_banner()
	_role.visible = false
	_tasks.visible = false
	_vitals.visible = false
	_weapon.visible = false
	_ability.visible = false
	_names.clear()
	_colors.clear()
	_done_seen.clear()
	_meeting_dismissed = false


func _on_visibility_changed() -> void:
	_update_processing()
	if is_visible_in_tree():
		sync()
	else:
		_reset()


## Покадровая работа нужна только видимому HUD и только с окном.
func _update_processing() -> void:
	set_process(is_visible_in_tree() and DisplayServer.get_name() != HEADLESS_DISPLAY)


func _on_phase_changed(phase: Game.Phase) -> void:
	if phase == Game.Phase.NONE:
		_reset()
	if phase != Game.Phase.PLAYING:
		_close_keypad()
	sync()


func _on_lobby_changed() -> void:
	_remember_players()
	if not is_visible_in_tree():
		return
	_sync_role()
	_sync_meeting()
	_sync_banner()


## Экраны поверх матча закрывают HUD целиком, пауза прячет его углы.
func _sync_layers() -> void:
	_views.visible = not _paused
	_toasts.visible = not _paused
	var covered: bool = _keypad.is_open() or _reveal.is_open() or _meeting_open or _results_open
	_crosshair.visible = _is_alive() and not _paused and not covered


func _in_match() -> bool:
	return is_visible_in_tree() and Game.phase != Game.Phase.NONE


# --- Игроки ---


func _remember_players() -> void:
	for peer_id: int in Net.players:
		_names[peer_id] = Net.players[peer_id]
		_colors[peer_id] = Net.get_player_color(peer_id)


func _name_of(peer_id: int) -> String:
	return _names[peer_id] if _names.has(peer_id) else Net.get_player_name(peer_id)


func _color_of(peer_id: int) -> Color:
	return PlayerPalette.color(_colors[peer_id] if _colors.has(peer_id) else Net.get_player_color(peer_id))


# --- Роль ---


func _on_role_assigned(_role_value: Game.Role) -> void:
	# Отсчёт идёт и при скрытом HUD: роль могла прийти раньше, чем экран матча.
	_reveal_hold.start(REVEAL_MIN_SEC)
	_sync_role()
	_sync_reveal()
	_sync_ability()
	_sync_layers()


func _sync_role() -> void:
	var known: bool = _in_match() and Game.local_role != Game.Role.NONE
	_role.visible = known
	if known:
		_role.set_role(Game.local_role == Game.Role.TRAITOR, _partner_names())


func _partner_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for peer_id: int in Game.get_fellow_traitors():
		var partner_name: String = _name_of(peer_id)
		if not partner_name.is_empty():
			names.append(partner_name)
	return names


## Экран роли: всю фазу ROLE_REVEAL, а если её нет — пока не истечёт REVEAL_MIN_SEC.
func _sync_reveal() -> void:
	var known: bool = _in_match() and Game.local_role != Game.Role.NONE
	var holding: bool = Game.phase == Game.Phase.PLAYING and not _reveal_hold.is_stopped()
	if known and (Game.phase == Game.Phase.ROLE_REVEAL or holding):
		var names: PackedStringArray = []
		var colors: Array[Color] = []
		for peer_id: int in Game.get_fellow_traitors():
			names.append(MatchText.player_name(_name_of(peer_id)))
			colors.append(_color_of(peer_id))
		_reveal.show_role(Game.local_role == Game.Role.TRAITOR, _color_of(Net.local_id()), names, colors)
		_reveal.set_seconds_left(_reveal_seconds_left())
	else:
		_reveal.close()
	_sync_layers()


func _reveal_seconds_left() -> float:
	return Game.phase_seconds_left if Game.phase == Game.Phase.ROLE_REVEAL else 0.0


# --- Задания ---


func _sync_tasks() -> void:
	if not _in_match():
		_tasks.visible = false
		return
	var station_ids: PackedInt32Array = Game.tasks.get_local_tasks()
	var titles: PackedStringArray = []
	var done: Array[bool] = []
	var seen: Dictionary[int, bool] = {}
	for station_id: int in station_ids:
		var is_done: bool = Game.tasks.is_local_done(station_id)
		titles.append(_task_title(station_id))
		done.append(is_done)
		# Сообщаем только о том, что стало сделанным на наших глазах.
		if is_done and _done_seen.has(station_id) and not _done_seen[station_id]:
			_toasts.show_toast(MatchText.task_done(_station_title(station_id)), HudToast.Kind.SUCCESS)
		seen[station_id] = is_done
	_done_seen = seen
	_tasks.set_tasks(titles, done)
	_tasks.set_progress(Game.tasks.done_count, Game.tasks.total_count)
	_tasks.visible = not station_ids.is_empty() or Game.tasks.total_count > 0


func _station(station_id: int) -> TaskStation:
	if not is_instance_valid(_map):
		return null
	return _map.get_interactable(station_id) as TaskStation


func _station_title(station_id: int) -> String:
	var station: TaskStation = _station(station_id)
	return station.title if station != null else ""


func _task_title(station_id: int) -> String:
	var station: TaskStation = _station(station_id)
	if station == null:
		return MatchText.task_title("", "")
	return MatchText.task_title(station.title, station.location)


func _on_task_opened(station_id: int, data: Dictionary) -> void:
	var code: Variant = data.get("code")
	# Задание без кода — не кодовая панель: показывать нечего.
	if not _in_match() or not Game.is_playing() or not _is_alive() or not (code is String or code is int):
		return
	var title: String = _station_title(station_id)
	_keypad_station = station_id
	_keypad.open(MatchText.KEYPAD_TITLE if title.is_empty() else title, str(code))
	cursor_needed.emit(CURSOR_KEYPAD, true)
	_sync_prompt()
	_sync_layers()


func _on_keypad_submitted(text: String) -> void:
	if _keypad.is_open():
		Game.tasks.request_answer(_keypad_station, text)


func _on_task_feedback(station_id: int, success: bool) -> void:
	if not _in_match():
		return
	var is_keypad: bool = _keypad.is_open() and station_id == _keypad_station
	if success:
		# О выполненном задании сообщит _sync_tasks, когда придёт обновлённый список.
		if is_keypad:
			_close_keypad()
	elif is_keypad:
		_keypad.show_error()
		_toasts.show_toast(MatchText.TOAST_WRONG_CODE, HudToast.Kind.DANGER)
	elif _has_zone(_station(station_id)):
		_toasts.show_toast(MatchText.TOAST_MISSED_ZONE, HudToast.Kind.WARNING)
	else:
		_toasts.show_toast(MatchText.TOAST_TASK_FAILED, HudToast.Kind.WARNING)


func _close_keypad() -> void:
	if not _keypad.is_open():
		return
	_keypad.close()
	_keypad_station = NO_STATION
	cursor_needed.emit(CURSOR_KEYPAD, false)
	_sync_prompt()
	_sync_layers()


# --- Свой аватар ---


func _unbind_player() -> void:
	if not is_instance_valid(_player):
		return
	_player.life_changed.disconnect(_on_life_changed)
	_player.limbs_changed.disconnect(_on_limbs_changed)
	_player.held_item_changed.disconnect(_on_held_item_changed)
	_player.body.vitals_changed.disconnect(_sync_vitals)
	_player.weapons.loadout_changed.disconnect(_sync_weapon)
	_player.interactor.focus_changed.disconnect(_on_focus_changed)
	_player.interactor.hold_changed.disconnect(_on_hold_changed)
	_player.input.fire_pressed.disconnect(_on_fire_pressed)


func _is_alive() -> bool:
	return is_instance_valid(_player) and _player.life == Player.Life.ALIVE


## Боевой HUD (здоровье, оружие, подсказка, способность) виден, только пока игрок жив.
func _sync_player() -> void:
	if not _is_alive():
		_close_keypad()
	_sync_vitals()
	_sync_weapon()
	_sync_prompt()
	_sync_ability()
	_sync_banner()
	_sync_layers()


func _on_life_changed(_life: Player.Life) -> void:
	_sync_player()


func _on_limbs_changed(mask: int) -> void:
	if _in_match():
		for message: String in MatchText.limbs_lost(_limbs_seen, mask):
			_toasts.show_toast(message, HudToast.Kind.DANGER)
	_limbs_seen = mask
	_sync_vitals()


func _on_held_item_changed(_item_id: int) -> void:
	_sync_weapon()


func _on_focus_changed(_target: Interactable) -> void:
	_sync_prompt()


func _on_hold_changed(_fraction: float) -> void:
	_sync_hold()


func _on_fire_pressed() -> void:
	if _in_match() and _is_alive() and _player.weapons.get_ammo() == 0:
		_toasts.show_toast(MatchText.TOAST_NO_AMMO, HudToast.Kind.WARNING)


func _sync_vitals() -> void:
	var shown: bool = _in_match() and _is_alive()
	_vitals.visible = shown
	if not shown:
		return
	var body: PlayerBody = _player.body
	_vitals.set_health(body.health, PlayerBody.CONFIG.max_health)
	# У головы и торса отдельного запаса нет: на схеме они всегда целые.
	var fractions: PackedFloat32Array = []
	fractions.resize(BodyPart.Part.size())
	fractions.fill(FULL)
	for part: BodyPart.Part in BodyPart.LIMBS:
		if part < body.part_health.size():
			fractions[part] = clampf(float(body.part_health[part]) / maxi(PlayerBody.CONFIG.limb_health, 1), 0.0, FULL)
	_vitals.set_parts(fractions, _player.limbs_lost)


func _sync_weapon() -> void:
	var item: ItemConfig = _player.weapons.get_held_item() if _is_alive() else null
	var shown: bool = _in_match() and item != null
	_weapon.visible = shown
	if shown:
		_weapon.set_weapon(item.title, _player.weapons.get_ammo(), _player.weapons.can_switch())


## Подсказка под прицелом; у калибратора под ней шкала с зелёной зоной.
func _sync_prompt() -> void:
	var target: Interactable = null
	if _in_match() and _is_alive() and Game.is_playing() and not _keypad.is_open():
		target = _player.interactor.focus
	var text: String = target.get_prompt(_player) if is_instance_valid(target) else ""
	if text.is_empty():
		_prompt.hide_prompt()
		_gauge.hide_gauge()
		return
	_prompt.show_prompt(MatchText.KEY_INTERACT, text)
	if _has_zone(target):
		_gauge.show_gauge(_zone_value(target, ZONE_START_PROPERTY), _zone_value(target, ZONE_END_PROPERTY))
	else:
		_gauge.hide_gauge()
	_sync_hold()


## Удержание E: у калибратора заполняет шкалу, у остальных предметов — рамку вокруг клавиши.
func _sync_hold() -> void:
	if not _prompt.visible or not is_instance_valid(_player):
		return
	var fraction: float = _player.interactor.hold_fraction
	if _gauge.visible:
		_gauge.set_fraction(fraction)
		_prompt.set_hold_progress(0.0)
	else:
		_prompt.set_hold_progress(fraction)


## Есть ли у предмета зелёная зона (числовые свойства zone_start и zone_end) — так выглядит
## калибратор. От класса станции ведущий не зависит.
func _has_zone(target: Interactable) -> bool:
	if not is_instance_valid(target):
		return false
	return is_finite(_zone_value(target, ZONE_START_PROPERTY)) and is_finite(_zone_value(target, ZONE_END_PROPERTY))


## Числовое свойство предмета; NAN, если такого свойства нет или оно не число.
func _zone_value(target: Interactable, property: StringName) -> float:
	var value: Variant = target.get(property)
	if value is float or value is int:
		return value
	return NAN


func _sync_banner() -> void:
	if not _in_match():
		_banner.hide_banner()
	elif is_instance_valid(_player):
		if _player.life == Player.Life.ALIVE:
			_banner.hide_banner()
		else:
			_banner.show_banner(MatchText.BANNER_GHOST)
	elif Game.is_participant(Net.local_id()):
		# Наш аватар ещё не появился или уже убран: молчим.
		_banner.hide_banner()
	else:
		_banner.show_banner(MatchText.BANNER_SPECTATOR)


# --- Саботаж ---


func _sync_sabotage() -> void:
	if _in_match() and Game.sabotage.active and Game.phase != Game.Phase.ENDED:
		_alert.show_alert(MatchText.ALERT_REACTOR, Game.sabotage.seconds_left)
	else:
		_alert.hide_alert()
	_sync_ability()


## Плашка саботажа у живого предателя.
func _sync_ability() -> void:
	var shown: bool = _in_match() and _is_alive() and Game.local_role == Game.Role.TRAITOR \
			and Game.phase != Game.Phase.ENDED
	_ability.visible = shown
	if shown:
		_show_ability()


func _show_ability() -> void:
	_ability.set_ability(MatchText.KEY_SABOTAGE, MatchText.ABILITY_SABOTAGE, Game.sabotage.cooldown_left,
			Game.sabotage.can_trigger(Net.local_id()))


# --- Собрание ---


func _on_meeting_started() -> void:
	_meeting_dismissed = false
	_sync_meeting()


func _on_meeting_closed() -> void:
	_meeting_dismissed = true
	_sync_meeting()


func _sync_meeting() -> void:
	if not Game.meeting.is_active():
		_meeting_dismissed = false
	var active: bool = _in_match() and Game.meeting.is_active() and not _meeting_dismissed \
			and (Game.phase == Game.Phase.PLAYING or Game.phase == Game.Phase.MEETING)
	if not active:
		_close_meeting()
		return
	var module: Meeting = Game.meeting
	_remember_players()
	var entries: Array[MeetingScreen.Entry] = _meeting_entries()
	if not _meeting_open:
		_meeting_open = true
		_own_vote = MeetingScreen.NO_VOTE
		_close_keypad()
		_meeting.open(MatchText.meeting_title(module.reason), MatchText.meeting_subtitle(module.reason,
				_name_of(module.caller_id), _name_of(module.victim_id)), entries)
		cursor_needed.emit(CURSOR_MEETING, true)
	else:
		_meeting.set_entries(entries)
	if module.stage == Meeting.Stage.VERDICT:
		var is_ejected: bool = module.ejected_id != MatchRules.SKIP_VOTE
		_meeting.show_verdict(MatchText.verdict(is_ejected, _name_of(module.ejected_id), module.ejected_role),
				module.votes, module.ejected_id)
	_meeting.set_stage(_meeting_stage(), module.stage_seconds_left)
	_meeting.mark_own_vote(_own_vote)
	_meeting.set_can_vote(_can_vote())
	_sync_layers()


func _close_meeting() -> void:
	if not _meeting_open:
		return
	_meeting_open = false
	_own_vote = MeetingScreen.NO_VOTE
	_meeting.close()
	cursor_needed.emit(CURSOR_MEETING, false)
	_sync_layers()


func _meeting_stage() -> MeetingScreen.Stage:
	match Game.meeting.stage:
		Meeting.Stage.VOTING:
			return MeetingScreen.Stage.VOTING
		Meeting.Stage.VERDICT:
			return MeetingScreen.Stage.VERDICT
	return MeetingScreen.Stage.DISCUSSION


## Участники матча в порядке лобби; мёртвые — те, кого нет среди пришедших на собрание.
func _meeting_entries() -> Array[MeetingScreen.Entry]:
	var module: Meeting = Game.meeting
	var peer_ids: PackedInt32Array = Game.participants.duplicate()
	for peer_id: int in module.attendees:
		if not peer_ids.has(peer_id):
			peer_ids.append(peer_id)
	var entries: Array[MeetingScreen.Entry] = []
	for peer_id: int in peer_ids:
		var entry: MeetingScreen.Entry = MeetingScreen.Entry.new()
		entry.peer_id = peer_id
		entry.name = MatchText.player_name(_name_of(peer_id))
		entry.color = _color_of(peer_id)
		entry.alive = module.attendees.has(peer_id)
		entry.is_self = peer_id == Net.local_id()
		entry.has_voted = module.voted.has(peer_id) and module.voted[peer_id]
		entries.append(entry)
	return entries


## Голосует только пришедший на собрание, только на стадии голосования и только один раз.
func _can_vote() -> bool:
	var module: Meeting = Game.meeting
	var local_id: int = Net.local_id()
	return module.stage == Meeting.Stage.VOTING and module.attendees.has(local_id) \
			and _own_vote == MeetingScreen.NO_VOTE and not (module.voted.has(local_id) and module.voted[local_id])


func _on_vote_pressed(target_id: int) -> void:
	if not _meeting_open or not _can_vote():
		return
	# Свой выбор помним сами: до вердикта сервер не говорит, кто за кого.
	_own_vote = target_id
	_meeting.mark_own_vote(target_id)
	_meeting.set_can_vote(false)
	Game.meeting.request_vote(target_id)


# --- Итоги ---


func _sync_results() -> void:
	var result: MatchResult = Game.last_result
	if not _in_match() or Game.phase != Game.Phase.ENDED or result == null:
		_close_results()
		return
	if not _results_open:
		_results_open = true
		_close_keypad()
		_results.open(MatchText.winner_title(result.winner), MatchText.end_reason(result.reason),
				_result_team(result.winner), _result_outcome(result), _result_entries(result))
		cursor_needed.emit(CURSOR_RESULTS, true)
	_results.set_seconds_left(Game.phase_seconds_left)
	_sync_layers()


func _close_results() -> void:
	if not _results_open:
		return
	_results_open = false
	_results.close()
	cursor_needed.emit(CURSOR_RESULTS, false)
	_sync_layers()


func _result_team(winner: Game.Winner) -> ResultsScreen.Team:
	match winner:
		Game.Winner.CREW:
			return ResultsScreen.Team.CREW
		Game.Winner.TRAITORS:
			return ResultsScreen.Team.TRAITORS
	return ResultsScreen.Team.NONE


func _result_outcome(result: MatchResult) -> ResultsScreen.Outcome:
	var local_id: int = Net.local_id()
	if result.get_entry(local_id) == null:
		return ResultsScreen.Outcome.WATCHED
	return ResultsScreen.Outcome.WON if result.did_win(local_id) else ResultsScreen.Outcome.LOST


func _result_entries(result: MatchResult) -> Array[ResultsScreen.Entry]:
	var entries: Array[ResultsScreen.Entry] = []
	for source: MatchResult.Entry in result.entries:
		var entry: ResultsScreen.Entry = ResultsScreen.Entry.new()
		entry.name = MatchText.player_name(source.name)
		entry.color = PlayerPalette.color(source.color_slot)
		entry.is_traitor = source.role == Game.Role.TRAITOR
		entry.alive = source.alive
		entry.is_self = source.peer_id == Net.local_id()
		entries.append(entry)
	return entries
