class_name Lobby
extends Control
## Экран лобби: восемь мест экипажа, счётчик, строка состояния, «Старт» для хоста.
## Только показывает то, что знают Net и Game; старт матча — просьба к серверу.

const ROW_SCENE: PackedScene = preload("res://scenes/ui/lobby_player_row.tscn")

const TEXT_COUNT: String = "%d"
const TEXT_COUNT_MAX: String = "/%d"
## Сколько игроков не хватает до старта: счётчик рядом уже говорит, сколько есть.
const TEXT_NEED_PLAYERS: String = "Не хватает %d %s"
const TEXT_NEED_ONE: String = "игрока"
const TEXT_NEED_MANY: String = "игроков"
const TEXT_CAN_START: String = "Можно начинать"
const TEXT_WAIT_HOST: String = "Ждём хоста"

var _rows: Array[LobbyPlayerRow] = []

@onready var _page: Control = %Page
@onready var _count_label: Label = %CountLabel
@onready var _count_max_label: Label = %CountMaxLabel
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _hint_dot: UiIcon = %HintDot
@onready var _hint_label: Label = %HintLabel
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	# Мест всегда столько, сколько игроков пускает сервер: строки создаём один раз.
	for slot: int in Net.MAX_PLAYERS:
		var row: LobbyPlayerRow = ROW_SCENE.instantiate() as LobbyPlayerRow
		_player_list.add_child(row)
		row.set_empty()
		_rows.append(row)
	_count_max_label.text = TEXT_COUNT_MAX % Net.MAX_PLAYERS
	Net.lobby_changed.connect(_refresh)
	Game.state_changed.connect(_refresh.unbind(1))
	Game.min_players_changed.connect(_refresh.unbind(1))
	visibility_changed.connect(_on_visibility_changed)
	_start_button.pressed.connect(Game.request_start_match)
	_leave_button.pressed.connect(Net.leave)
	_refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		UiMotion.fade_in(_page)
	_refresh()


func _refresh() -> void:
	# Экран существует и без сессии (скрытым): тогда показывать нечего.
	if not is_visible_in_tree() or not Net.is_joined():
		return
	var local_id: int = Net.local_id()
	var count: int = Net.players.size()
	_count_label.text = TEXT_COUNT % count
	var peer_ids: Array[int] = []
	peer_ids.assign(Net.players.keys())
	for slot: int in _rows.size():
		var row: LobbyPlayerRow = _rows[slot]
		if slot >= peer_ids.size():
			row.set_empty()
			continue
		var peer_id: int = peer_ids[slot]
		row.set_player(Net.players[peer_id], PlayerPalette.color(Net.get_player_color(peer_id)),
				Net.is_host(peer_id), peer_id == local_id)
	var can_start: bool = Game.can_start_match()
	# Сервер всё равно проверит и хоста, и число игроков.
	_start_button.visible = Net.is_local_host()
	_start_button.disabled = not can_start
	# Строка состояния: пустая точка — игроков мало, голубая — ждём хоста, зелёная — можно начинать.
	if not can_start:
		var missing: int = maxi(Game.min_players - count, 1)
		_hint_label.text = TEXT_NEED_PLAYERS % [missing, _players_word(missing)]
		_hint_dot.set_icon(UiIcon.Kind.RING, UiTokens.TEXT_DIM)
	elif Net.is_local_host():
		_hint_label.text = TEXT_CAN_START
		_hint_dot.set_icon(UiIcon.Kind.DOT, UiTokens.SUCCESS)
	else:
		_hint_label.text = TEXT_WAIT_HOST
		_hint_dot.set_icon(UiIcon.Kind.DOT, UiTokens.CYAN)


## «не хватает 1 игрока», но «не хватает 2 игроков». Мест не больше Net.MAX_PLAYERS,
## поэтому правило для 21 и дальше не нужно.
static func _players_word(count: int) -> String:
	return TEXT_NEED_ONE if count == 1 else TEXT_NEED_MANY
