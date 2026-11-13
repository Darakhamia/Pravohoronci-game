class_name RoleReveal
extends Control
## Экран начала матча: «Ты — экипаж» или «Ты — предатель». Слева — что это значит и что
## делать, у предателя ещё и напарники; справа — отсчёт до начала и шлем игрока, который
## выглядывает из-за нижнего края (у предателя глаза бегают — как в главном меню).
## Сам ничего не решает: роль, имена и время приходят через методы.

const TEXT_CREW: String = "Экипаж"
const TEXT_TRAITOR: String = "Предатель"
## Сколько предателей в матче, экипаж не знает — поэтому без числа.
const TEXT_LEAD_CREW: String = "Среди вас есть предатель."
const TEXT_LEAD_TRAITOR: String = "Экипаж не знает, кто ты."
const TEXT_LEAD_TRAITOR_ALONE: String = "Экипаж не знает, кто ты. Напарников нет."
## Две строки; перед тире стоит неразрывный пробел, чтобы строка не начиналась с тире.
const TEXT_HINT_CREW: String = "Выполняй задания и смотри по сторонам.\nТело или подозрение\u00a0— созывай собрание."
const TEXT_HINT_TRAITOR: String = "Убивай без свидетелей: нож\u00a0— Q. Саботаж реактора\u00a0— F.\nНа собраниях голосуй как все."
const TEXT_PARTNER: String = "Напарник"
const TEXT_PARTNERS: String = "Напарники"
const CREW_STYLE: StringName = &"LabelDisplayXLCyan"
const TRAITOR_STYLE: StringName = &"LabelDisplayXLDanger"
const PARTNER_NAME_STYLE: StringName = &"LabelStrong"
## Сторона шлема в строке напарника.
const PARTNER_HELMET_SIZE: float = 48.0
## Предатель косится в сторону.
const TRAITOR_LOOK: float = -1.0

var _is_traitor: bool = false
var _partner_names: PackedStringArray = []

@onready var _page: Control = %Page
@onready var _role_name: Label = %RoleName
@onready var _partners: Control = %Partners
@onready var _partners_caption: Label = %PartnersCaption
@onready var _partner_list: VBoxContainer = %PartnerList
@onready var _lead: Label = %Lead
@onready var _hint: Label = %Hint
@onready var _countdown: Control = %Countdown
@onready var _timer: Label = %Timer
@onready var _portrait: HelmetAvatar = %Portrait


## Показывает роль. own_color — цвет игрока; partner_names и partner_colors — остальные
## предатели (по одним номерам), экипажу передают пустые списки.
func show_role(is_traitor: bool, own_color: Color, partner_names: PackedStringArray,
		partner_colors: Array[Color]) -> void:
	_is_traitor = is_traitor
	_partner_names = partner_names if is_traitor else PackedStringArray()
	_role_name.text = TEXT_TRAITOR if is_traitor else TEXT_CREW
	_role_name.theme_type_variation = TRAITOR_STYLE if is_traitor else CREW_STYLE
	_portrait.set_player_color(own_color)
	_portrait.set_look(TRAITOR_LOOK if is_traitor else 0.0)
	_fill_partners(partner_colors)
	if not is_traitor:
		_lead.text = TEXT_LEAD_CREW
	else:
		_lead.text = TEXT_LEAD_TRAITOR_ALONE if _partner_names.is_empty() else TEXT_LEAD_TRAITOR
	_hint.text = TEXT_HINT_TRAITOR if is_traitor else TEXT_HINT_CREW
	if not visible:
		visible = true
		UiMotion.fade_in(_page)


## Вызывают при каждом изменении таймера. 0 и меньше — отсчёта нет (пауза на чтение роли
## выключена): блок с таймером скрыт.
func set_seconds_left(seconds_left: float) -> void:
	_countdown.visible = seconds_left > 0.0
	_timer.text = MatchText.time(seconds_left)


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Что сейчас показано — для ведущего матча и тестов.
func is_traitor_shown() -> bool:
	return _is_traitor


func get_partner_names() -> PackedStringArray:
	return _partner_names


func _fill_partners(colors: Array[Color]) -> void:
	for child: Node in _partner_list.get_children():
		_partner_list.remove_child(child)
		child.queue_free()
	_partners.visible = not _partner_names.is_empty()
	_partners_caption.text = TEXT_PARTNER if _partner_names.size() == 1 else TEXT_PARTNERS
	for index: int in _partner_names.size():
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var helmet: HelmetAvatar = HelmetAvatar.new()
		helmet.custom_minimum_size = Vector2(PARTNER_HELMET_SIZE, PARTNER_HELMET_SIZE)
		helmet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		helmet.set_player_color(colors[index] if index < colors.size() else PlayerPalette.FALLBACK)
		row.add_child(helmet)
		var name_label: Label = Label.new()
		name_label.theme_type_variation = PARTNER_NAME_STYLE
		name_label.text = _partner_names[index]
		row.add_child(name_label)
		_partner_list.add_child(row)
