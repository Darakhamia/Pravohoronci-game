class_name Lobby
extends Control
## Экран лобби: список игроков, подсказка, «Старт» для хоста.
## Только показывает то, что знают Net и Game; старт матча — просьба к серверу.

const HOST_MARK: String = " — хост"
const SELF_MARK: String = " (ты)"
const SELF_COLOR: Color = Color(1.0, 0.82, 0.25)

const TEXT_COUNT: String = "Игроки: %d / %d"
const TEXT_NEED_PLAYERS: String = "Нужно минимум %d %s (сейчас %d)"
const TEXT_CAN_START: String = "Можно начинать"
const TEXT_WAIT_HOST: String = "Ждём, пока %s начнёт игру"
## До этого числа включительно — «игрока», дальше — «игроков».
const FEW_PLAYERS_MAX: int = 4

@onready var _count_label: Label = %CountLabel
@onready var _player_list: ItemList = %PlayerList
@onready var _hint_label: Label = %HintLabel
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	Net.lobby_changed.connect(_refresh)
	Game.state_changed.connect(_refresh.unbind(1))
	Game.min_players_changed.connect(_refresh.unbind(1))
	visibility_changed.connect(_refresh)
	_start_button.pressed.connect(Game.request_start_match)
	_leave_button.pressed.connect(Net.leave)
	_refresh()


func _refresh() -> void:
	# Экран существует и без сессии (скрытым): тогда показывать нечего.
	if not is_visible_in_tree() or not Net.is_joined():
		return
	var local_id: int = Net.local_id()
	var count: int = Net.players.size()
	_count_label.text = TEXT_COUNT % [count, Net.MAX_PLAYERS]
	_player_list.clear()
	for peer_id: int in Net.players:
		var text: String = Net.players[peer_id]
		if Net.is_host(peer_id):
			text += HOST_MARK
		if peer_id == local_id:
			text += SELF_MARK
		var index: int = _player_list.add_item(text, null, false)
		if peer_id == local_id:
			_player_list.set_item_custom_fg_color(index, SELF_COLOR)
	var can_start: bool = Game.can_start_match()
	# Сервер всё равно проверит и хоста, и число игроков.
	_start_button.visible = Net.is_local_host()
	_start_button.disabled = not can_start
	if not Net.is_local_host():
		_hint_label.text = TEXT_WAIT_HOST % Net.get_player_name(Net.host_id)
	elif can_start:
		_hint_label.text = TEXT_CAN_START
	else:
		_hint_label.text = TEXT_NEED_PLAYERS % [Game.min_players, _players_word(Game.min_players), count]


## «минимум 3 игрока», но «минимум 5 игроков». Минимум не больше Net.MAX_PLAYERS,
## поэтому правила для 11–14 и 21+ не нужны.
static func _players_word(count: int) -> String:
	return "игрока" if count <= FEW_PLAYERS_MAX else "игроков"
