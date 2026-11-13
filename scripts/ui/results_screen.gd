class_name ResultsScreen
extends Control
## Экран итогов матча. Заголовок — кто победил и почему; слева — участники по командам
## (с этого момента роли открыты всем), справа — личный исход («Победа» или «Поражение»)
## и отсчёт до возврата в лобби. Наблюдатель видит то же самое без личного исхода.
## Сам ничего не решает: итог и время приходят через методы.

## Команда-победитель.
enum Team { NONE, CREW, TRAITORS }
## Исход для самого игрока. WATCHED — он не участвовал в матче.
enum Outcome { WATCHED, WON, LOST }

## Один участник матча.
class Entry:
	var name: String = ""
	var color: Color = PlayerPalette.FALLBACK
	var is_traitor: bool = false
	## Дожил ли до конца матча.
	var alive: bool = true
	var is_self: bool = false


const ROW_SCENE: PackedScene = preload("res://scenes/ui/results_player_row.tscn")

const TEXT_WON: String = "Победа"
const TEXT_LOST: String = "Поражение"
const TEXT_ROLE_CREW: String = "Ты — экипаж"
const TEXT_ROLE_TRAITOR: String = "Ты — предатель"
const TEXT_NOBODY: String = "никого"
const WON_STYLE: StringName = &"LabelVerdictAccent"
const LOST_STYLE: StringName = &"LabelVerdictDanger"
const EMPTY_STYLE: StringName = &"LabelFaint"

var _entries: Array[Entry] = []

@onready var _page: Control = %Page
@onready var _title: Label = %Title
@onready var _reason: Label = %Reason
@onready var _crew_list: VBoxContainer = %CrewList
@onready var _crew_won: Label = %CrewWon
@onready var _traitor_list: VBoxContainer = %TraitorList
@onready var _traitors_won: Label = %TraitorsWon
@onready var _personal: Control = %Personal
@onready var _outcome: Label = %Outcome
@onready var _outcome_caption: Label = %OutcomeCaption
@onready var _timer: Label = %Timer


## title — «Победа экипажа», reason — причина одной строкой, winner — чья колонка получает
## метку «Победа», outcome — исход для самого игрока, entries — участники в порядке лобби.
func open(title: String, reason: String, winner: Team, outcome: Outcome, entries: Array[Entry]) -> void:
	_entries = entries
	_title.text = title
	_reason.text = reason
	_crew_won.visible = winner == Team.CREW
	_traitors_won.visible = winner == Team.TRAITORS
	_fill(_crew_list, false)
	_fill(_traitor_list, true)
	_personal.visible = outcome != Outcome.WATCHED
	_outcome.text = TEXT_WON if outcome == Outcome.WON else TEXT_LOST
	_outcome.theme_type_variation = WON_STYLE if outcome == Outcome.WON else LOST_STYLE
	_outcome_caption.text = TEXT_ROLE_TRAITOR if _is_self_traitor() else TEXT_ROLE_CREW
	set_seconds_left(0.0)
	if not visible:
		visible = true
		UiMotion.fade_in(_page)


## Вызывают при каждом изменении таймера: сколько осталось до возврата в лобби.
func set_seconds_left(seconds_left: float) -> void:
	_timer.text = MatchText.time(seconds_left)


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _fill(list: VBoxContainer, traitors: bool) -> void:
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for entry: Entry in _entries:
		if entry.is_traitor != traitors:
			continue
		var row: ResultsPlayerRow = ROW_SCENE.instantiate() as ResultsPlayerRow
		list.add_child(row)
		row.set_player(entry.name, entry.color, entry.alive, entry.is_self)
	if list.get_child_count() == 0:
		# Матч без предателей (отладка) или без экипажа: колонка не должна выглядеть сломанной.
		var empty: Label = Label.new()
		empty.theme_type_variation = EMPTY_STYLE
		empty.text = TEXT_NOBODY
		list.add_child(empty)


func _is_self_traitor() -> bool:
	for entry: Entry in _entries:
		if entry.is_self:
			return entry.is_traitor
	return false
