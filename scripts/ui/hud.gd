class_name Hud
extends Control
## Экран матча: следит за картой и своим аватаром, ведёт паузу и режим мыши. Всё, что
## показывает сам матч (элементы HUD, роль, собрание, итоги, кодовая панель), наполняет
## ведущий матча — узел %Match (MatchPresenter): ему Hud сообщает карту, аватар и паузу.
## Единственный хозяин режима мыши: она захвачена, только пока HUD виден, паузы нет,
## у нас есть свой аватар и курсор никому не нужен. То же условие включает управление
## аватаром. Другие экраны матча Input.mouse_mode сами не трогают, а просят курсор
## через set_cursor_needed().

var _map: GameMap = null
var _local_player: Player = null
var _paused: bool = false
## Кому из других экранов матча сейчас нужен курсор.
var _cursor_requests: Dictionary[StringName, bool] = {}

@onready var _match: MatchPresenter = %Match
@onready var _pause_menu: Control = %PauseMenu
@onready var _pause_page: Control = %PausePage
@onready var _resume_button: Button = %ResumeButton
@onready var _end_match_button: Button = %EndMatchButton
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	# Хост мог смениться посреди матча — от этого зависит кнопка «Завершить матч».
	Net.lobby_changed.connect(_refresh)
	_resume_button.pressed.connect(_set_paused.bind(false))
	_end_match_button.pressed.connect(Game.request_end_match)
	_leave_button.pressed.connect(Net.leave)
	_match.cursor_needed.connect(set_cursor_needed)
	# HUD мог появиться уже посреди матча: теперь, когда просьбы о курсоре есть кому
	# слушать, ведущий сверяет экран с состоянием игры.
	_match.sync()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		_set_paused(not _paused)
		get_viewport().set_input_as_handled()


## Вызывает Main при каждой смене карты. null — карты нет.
func set_map(map: GameMap) -> void:
	if is_instance_valid(_map):
		_map.player_added.disconnect(_on_player_added)
		_map.player_removed.disconnect(_on_player_removed)
	_map = map
	_local_player = null
	if map != null:
		map.player_added.connect(_on_player_added)
		map.player_removed.connect(_on_player_removed)
		# Свой аватар мог появиться раньше, чем карта дошла до HUD.
		_local_player = map.get_player(Net.local_id())
	_match.set_map(map)
	_refresh()


## Экран поверх матча (голосование, итоги) берёт и отдаёт курсор: пока есть хоть одна
## заявка, мышь свободна, а аватар не управляется. who — имя просящего экрана.
func set_cursor_needed(who: StringName, needed: bool) -> void:
	# Пока HUD скрыт, мышь и так свободна: заявка не должна дожить до следующего матча.
	if needed and is_visible_in_tree():
		_cursor_requests[who] = true
	else:
		_cursor_requests.erase(who)
	_refresh()


func _on_player_added(player: Player) -> void:
	if player.is_local():
		_local_player = player
		_refresh()


func _on_player_removed(peer_id: int) -> void:
	# Сверяем с самим аватаром: после конца сессии Net.local_id() уже 0.
	if is_instance_valid(_local_player) and _local_player.peer_id == peer_id:
		_local_player = null
		_refresh()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_paused = false
		_cursor_requests.clear()
	_refresh()


func _set_paused(value: bool) -> void:
	_paused = value
	_refresh()


func _refresh() -> void:
	var has_player: bool = is_instance_valid(_local_player)
	# Сначала ведущий: закрывая свои экраны, он отдаёт курсор, и заявки ниже уже свежие.
	# Под паузой он прячет прицел и углы HUD: они не должны спорить с окном.
	_match.set_local_player(_local_player if has_player else null)
	_match.set_paused(_paused)
	var playing: bool = is_visible_in_tree() and has_player and not _paused and _cursor_requests.is_empty()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if playing else Input.MOUSE_MODE_VISIBLE
	if has_player:
		_local_player.set_input_enabled(playing)
	if _paused and not _pause_menu.visible:
		UiMotion.fade_in(_pause_page)
	_pause_menu.visible = _paused
	_end_match_button.visible = Net.is_local_host()
