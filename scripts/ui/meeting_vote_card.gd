class_name MeetingVoteCard
extends Button
## Карточка игрока на собрании. Вся карточка — кнопка голоса за этого игрока.
## Что показывать, решает MeetingScreen; карточка сообщает наверх только о нажатии.

signal chosen(peer_id: int)

## Особая отметка карточки.
enum Mark { NONE, OWN_VOTE, EJECTED }

const TEXT_OWN_VOTE: String = "Твой голос"
const TEXT_EJECTED: String = "За борт"
const TEXT_DEAD: String = "выбыл"
const TEXT_COUNT: String = "%d"
const CARD_STYLE: StringName = &"VoteCard"
const CARD_CHOSEN_STYLE: StringName = &"VoteCardChosen"
const CARD_EJECTED_STYLE: StringName = &"VoteCardEjected"
const CARD_DEAD_STYLE: StringName = &"VoteCardDead"
const NAME_STYLE: StringName = &"LabelStrong"
const NAME_DEAD_STYLE: StringName = &"LabelStrongDim"
const TAG_OWN_VOTE_STYLE: StringName = &"LabelTagAccent"
const TAG_EJECTED_STYLE: StringName = &"LabelTagDanger"
const COUNT_STYLE: StringName = &"LabelHeadingDim"
const COUNT_EJECTED_STYLE: StringName = &"LabelHeading"
## Сторона мини-шлема голосовавшего.
const VOTER_SIZE: float = 28.0
## Ширина строки имени: карточка без полей, шлема и промежутка. Имя шире обрезается многоточием,
## а метка «ты» и число голосов забирают у него своё место.
const NAME_ROW_WIDTH: float = 368.0

var _peer_id: int = 0
var _alive: bool = true
var _mark: Mark = Mark.NONE

@onready var _row: HBoxContainer = %Row
@onready var _name_row: HBoxContainer = %NameRow
@onready var _helmet: HelmetAvatar = %Helmet
@onready var _name: Label = %Name
@onready var _self_tag: Label = %SelfTag
@onready var _state: Label = %State
@onready var _voters: HBoxContainer = %Voters
@onready var _count: Label = %Count
@onready var _tag: Label = %Tag


func _ready() -> void:
	pressed.connect(_on_pressed)
	set_mark(Mark.NONE)
	set_voters([])


## voted — показать на шлеме отметку «уже проголосовал».
func show_player(peer_id: int, player_name: String, color: Color, alive: bool, is_self: bool, voted: bool) -> void:
	_peer_id = peer_id
	_alive = alive
	_helmet.set_player_color(color)
	_helmet.set_style(HelmetAvatar.Style.NORMAL if alive else HelmetAvatar.Style.DEAD)
	_helmet.set_checked(voted and alive)
	_name.text = player_name
	_name.theme_type_variation = NAME_STYLE if alive else NAME_DEAD_STYLE
	_self_tag.visible = is_self
	_state.text = TEXT_DEAD
	_refresh()


## Можно ли сейчас нажать карточку.
func set_votable(votable: bool) -> void:
	disabled = not votable
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if votable else Control.CURSOR_ARROW


func set_mark(mark: Mark) -> void:
	_mark = mark
	_tag.visible = mark != Mark.NONE
	if mark == Mark.OWN_VOTE:
		_tag.text = TEXT_OWN_VOTE
		_tag.theme_type_variation = TAG_OWN_VOTE_STYLE
	elif mark == Mark.EJECTED:
		_tag.text = TEXT_EJECTED
		_tag.theme_type_variation = TAG_EJECTED_STYLE
	_refresh()


## Цвета тех, кто голосовал за этого игрока: по мини-шлему на каждого под именем и число справа.
func set_voters(colors: Array[Color]) -> void:
	fill_voters(_voters, colors)
	_count.text = TEXT_COUNT % colors.size()
	_refresh()


## Заполняет ряд мини-шлемами цветов colors. Общий помощник карточки и блока «Пропустили».
static func fill_voters(row: Container, colors: Array[Color]) -> void:
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for color: Color in colors:
		var helmet: HelmetAvatar = HelmetAvatar.new()
		helmet.custom_minimum_size = Vector2(VOTER_SIZE, VOTER_SIZE)
		helmet.set_player_color(color)
		row.add_child(helmet)


func _refresh() -> void:
	var has_voters: bool = _voters.get_child_count() > 0
	_voters.visible = has_voters
	_count.visible = has_voters
	_count.theme_type_variation = COUNT_EJECTED_STYLE if _mark == Mark.EJECTED else COUNT_STYLE
	_fit_name()
	# Под именем — что-то одно: шлемы голосовавших или «выбыл».
	_state.visible = not _alive and not has_voters
	if _mark == Mark.EJECTED:
		theme_type_variation = CARD_EJECTED_STYLE
	elif _mark == Mark.OWN_VOTE:
		theme_type_variation = CARD_CHOSEN_STYLE
	elif not _alive:
		theme_type_variation = CARD_DEAD_STYLE
	else:
		theme_type_variation = CARD_STYLE


## Надпись с многоточием сама ширины не просит: даём ей ширину текста, но не больше того,
## что остаётся в строке рядом с меткой «ты» и числом голосов.
func _fit_name() -> void:
	var available: float = NAME_ROW_WIDTH
	if _self_tag.visible:
		available -= _self_tag.get_combined_minimum_size().x + _name_row.get_theme_constant(&"separation")
	if _count.visible:
		available -= _count.get_combined_minimum_size().x + _row.get_theme_constant(&"separation")
	var font: Font = _name.get_theme_font(&"font")
	var font_size: int = _name.get_theme_font_size(&"font_size")
	var text_width: float = font.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_name.custom_minimum_size.x = minf(ceilf(text_width), maxf(available, 0.0))


func _on_pressed() -> void:
	chosen.emit(_peer_id)
