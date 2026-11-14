class_name MeetingScreen
extends Control
## Экран собрания: обсуждение, голосование, итог. Полноэкранный и управляется одной мышью.
## Слева — карточки игроков, справа — таймер этапа, подсказка и «Пропустить» (как в лобби:
## список слева, главное число справа). Кто проголосовал — отметка на шлеме; в итоге под
## именем стоят мини-шлемы голосовавших, а вердикт занимает место заголовка.
## Сам ничего не решает и ни к чему не обращается: данные приходят через методы,
## наверх уходит только сигнал vote_pressed. Курсор для него просят у Hud.set_cursor_needed().

## Игрок нажал карточку (target_id — peer_id игрока) или «Пропустить» (SKIP_ID).
signal vote_pressed(target_id: int)

enum Stage { DISCUSSION, VOTING, VERDICT }

## Один игрок на собрании.
class Entry:
	var peer_id: int = 0
	var name: String = ""
	var color: Color = PlayerPalette.FALLBACK
	## false — игрок вне игры: погиб до собрания или вышел из игры уже во время него.
	## Голосовать за такого нельзя.
	var alive: bool = true
	var is_self: bool = false
	var has_voted: bool = false


const CARD_SCENE: PackedScene = preload("res://scenes/ui/meeting_vote_card.tscn")
const MAX_CARDS: int = 8
## target_id голоса «пропустить».
const SKIP_ID: int = 0
## Игрок ещё не выбирал.
const NO_VOTE: int = -1

const TEXT_STAGE: Dictionary[Stage, String] = {
	Stage.DISCUSSION: "Обсуждение",
	Stage.VOTING: "Голосование",
	Stage.VERDICT: "Итог",
}
const TEXT_TIMER_CAPTION: Dictionary[Stage, String] = {
	Stage.DISCUSSION: "До голосования",
	Stage.VOTING: "До конца голосования",
	Stage.VERDICT: "Продолжаем через",
}
const TEXT_HINT_DISCUSSION: String = "Спорьте в Discord. Голосование откроется само."
const TEXT_HINT_CAN_VOTE: String = "Выбери, кого изгнать, или пропусти."
const TEXT_HINT_VOTED: String = "Голос принят. Ждём остальных."
const TEXT_HINT_VOTE_LOST: String = "Игрок вышел из игры\u00a0— твой голос пропал."
const TEXT_HINT_WATCHING: String = "Ты наблюдаешь: голосуют только живые."
const TEXT_HINT_VERDICT: String = "Возвращаемся на станцию."

const DECK_STYLE: StringName = &"LabelDim"
const DECK_VERDICT_STYLE: StringName = &"LabelVerdict"
const SKIP_STYLE: StringName = &"Button"
const SKIP_CHOSEN_STYLE: StringName = &"ButtonChosen"

var _stage: Stage = Stage.DISCUSSION
var _entries: Array[Entry] = []
var _can_vote: bool = false
var _own_vote: int = NO_VOTE
## Мой голос пропал: игрок, за которого он отдан, вышел из игры.
var _vote_lost: bool = false
## Итог: кто за кого голосовал (peer_id -> peer_id цели или SKIP_ID) и кого изгнали.
var _votes: Dictionary[int, int] = {}
var _ejected_id: int = SKIP_ID
var _subtitle: String = ""
var _verdict: String = ""
var _cards: Array[MeetingVoteCard] = []

@onready var _page: Control = %Page
@onready var _stage_label: Label = %Stage
@onready var _title: Label = %Title
@onready var _timer_caption: Label = %TimerCaption
@onready var _timer: Label = %Timer
@onready var _deck: Label = %Deck
@onready var _card_grid: GridContainer = %Cards
@onready var _skip_button: Button = %SkipButton
@onready var _skip_result: Control = %SkipResult
@onready var _skip_voters: HBoxContainer = %SkipVoters
@onready var _hint: Label = %Hint


func _ready() -> void:
	for index: int in MAX_CARDS:
		var card: MeetingVoteCard = CARD_SCENE.instantiate() as MeetingVoteCard
		_card_grid.add_child(card)
		card.chosen.connect(_on_card_chosen)
		_cards.append(card)
	_skip_button.pressed.connect(_on_card_chosen.bind(SKIP_ID))
	_refresh()


## Открывает собрание с этапа обсуждения. subtitle — повод: «Тело: Оля. Сообщает Ваня.»
func open(title: String, subtitle: String, entries: Array[Entry]) -> void:
	_title.text = title
	_subtitle = subtitle
	_entries = entries
	_stage = Stage.DISCUSSION
	_can_vote = false
	_own_vote = NO_VOTE
	_vote_lost = false
	_votes = {}
	_ejected_id = SKIP_ID
	_verdict = ""
	_set_time(0.0)
	_refresh()
	if not visible:
		visible = true
		UiMotion.fade_in(_page)


## Вызывают при каждом изменении таймера. DISCUSSION — голосовать ещё нельзя,
## VOTING — карточки нажимаются, VERDICT — показан итог.
func set_stage(stage: Stage, seconds_left: float) -> void:
	_set_time(seconds_left)
	if stage != _stage:
		_stage = stage
		_refresh()


## Обновляет игроков: кто-то проголосовал или вышел.
func set_entries(entries: Array[Entry]) -> void:
	_entries = entries
	_refresh()


## false — мёртвым, наблюдателям и после того, как голос отдан.
func set_can_vote(can_vote: bool) -> void:
	_can_vote = can_vote
	_refresh()


## Подсвечивает мой выбор: peer_id игрока или SKIP_ID; NO_VOTE — выбора нет.
func mark_own_vote(target_id: int) -> void:
	_own_vote = target_id
	_refresh()


## true — мой голос пропал вместе с игроком, за которого был отдан (он вышел из игры):
## второго голоса нет, подсказка объясняет, что случилось.
func set_vote_lost(vote_lost: bool) -> void:
	_vote_lost = vote_lost
	_refresh()


## Подсказка под таймером, как её видит игрок.
func get_hint() -> String:
	return _hint.text


## Показывает итог. votes: peer_id голосовавшего -> peer_id цели (SKIP_ID — пропуск),
## ejected_id — кого изгнали (SKIP_ID — никого).
func show_verdict(text: String, votes: Dictionary[int, int], ejected_id: int) -> void:
	_verdict = text
	_votes = votes
	_ejected_id = ejected_id
	_stage = Stage.VERDICT
	_refresh()


func close() -> void:
	visible = false


func _set_time(seconds_left: float) -> void:
	_timer.text = MatchText.time(seconds_left)


func _refresh() -> void:
	var is_verdict: bool = _stage == Stage.VERDICT
	var voting_open: bool = _stage == Stage.VOTING and _can_vote
	_stage_label.text = TEXT_STAGE[_stage]
	_timer_caption.text = TEXT_TIMER_CAPTION[_stage]
	# Итог занимает место заголовка: на этом этапе он — главное на экране.
	_title.visible = not is_verdict
	_deck.text = _verdict if is_verdict else _subtitle
	_deck.theme_type_variation = DECK_VERDICT_STYLE if is_verdict else DECK_STYLE
	for index: int in _cards.size():
		var card: MeetingVoteCard = _cards[index]
		card.visible = index < _entries.size()
		if card.visible:
			_show_card(card, _entries[index], voting_open)

	# «Пропустить» — только пока им можно голосовать или это мой выбор; в обсуждении его нет.
	var skip_chosen: bool = _stage == Stage.VOTING and _own_vote == SKIP_ID
	_skip_button.visible = voting_open or skip_chosen
	_skip_button.disabled = not voting_open
	_skip_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if voting_open else Control.CURSOR_ARROW
	_skip_button.theme_type_variation = SKIP_CHOSEN_STYLE if skip_chosen else SKIP_STYLE
	# В итоге пропустившие стоят отдельным блоком: это счёт, а не кнопка.
	var skip_colors: Array[Color] = _voter_colors(SKIP_ID if is_verdict else NO_VOTE)
	MeetingVoteCard.fill_voters(_skip_voters, skip_colors)
	_skip_result.visible = not skip_colors.is_empty()
	_hint.text = _hint_text()


func _show_card(card: MeetingVoteCard, entry: Entry, voting_open: bool) -> void:
	var is_verdict: bool = _stage == Stage.VERDICT
	card.show_player(entry.peer_id, entry.name, entry.color, entry.alive, entry.is_self,
			_stage == Stage.VOTING and entry.has_voted)
	card.set_votable(voting_open and entry.alive)
	card.set_voters(_voter_colors(entry.peer_id if is_verdict else NO_VOTE))
	if is_verdict and entry.peer_id == _ejected_id:
		card.set_mark(MeetingVoteCard.Mark.EJECTED)
	elif not is_verdict and entry.peer_id == _own_vote and entry.alive:
		card.set_mark(MeetingVoteCard.Mark.OWN_VOTE)
	else:
		card.set_mark(MeetingVoteCard.Mark.NONE)


func _hint_text() -> String:
	match _stage:
		Stage.DISCUSSION:
			return TEXT_HINT_DISCUSSION
		Stage.VOTING:
			if _can_vote:
				return TEXT_HINT_CAN_VOTE
			if _vote_lost:
				return TEXT_HINT_VOTE_LOST
			return TEXT_HINT_VOTED if _own_vote != NO_VOTE else TEXT_HINT_WATCHING
	return TEXT_HINT_VERDICT


## Цвета игроков, голосовавших за target_id, в порядке списка игроков.
func _voter_colors(target_id: int) -> Array[Color]:
	var colors: Array[Color] = []
	for entry: Entry in _entries:
		if _votes.has(entry.peer_id) and _votes[entry.peer_id] == target_id:
			colors.append(entry.color)
	return colors


func _on_card_chosen(target_id: int) -> void:
	vote_pressed.emit(target_id)
