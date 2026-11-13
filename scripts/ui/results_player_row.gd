class_name ResultsPlayerRow
extends VBoxContainer
## Строка участника на экране итогов: шлем, имя, метка «ты» и «вне игры» для тех, кто не дожил.
## Роль видна по колонке, в которой стоит строка. Данные приходят от ResultsScreen.

const TEXT_OUT: String = "вне игры"
const NAME_STYLE: StringName = &"LabelStrong"
const NAME_OUT_STYLE: StringName = &"LabelStrongDim"
## Ширина строки: колонка команды на экране итогов. Имя шире обрезается многоточием,
## а шлем, метка «ты» и «вне игры» забирают у него своё место.
const ROW_WIDTH: float = 480.0

@onready var _content: HBoxContainer = %Content
@onready var _helmet: HelmetAvatar = %Helmet
@onready var _name: Label = %Name
@onready var _self_tag: Label = %SelfTag
@onready var _state: Label = %State


func set_player(player_name: String, color: Color, alive: bool, is_self: bool) -> void:
	_helmet.set_player_color(color)
	_helmet.set_style(HelmetAvatar.Style.NORMAL if alive else HelmetAvatar.Style.DEAD)
	_name.text = player_name
	_name.theme_type_variation = NAME_STYLE if alive else NAME_OUT_STYLE
	_self_tag.visible = is_self
	_state.text = TEXT_OUT
	_state.visible = not alive
	_fit_name()


func get_player_name() -> String:
	return _name.text


func is_marked_out() -> bool:
	return _state.visible


func is_marked_self() -> bool:
	return _self_tag.visible


## Надпись с многоточием сама ширины не просит: даём ей ширину текста, но не больше того,
## что остаётся в строке рядом со шлемом и метками.
func _fit_name() -> void:
	var separation: float = _content.get_theme_constant(&"separation")
	# Шлем, имя и распорка есть всегда: между ними два промежутка.
	var available: float = ROW_WIDTH - _helmet.custom_minimum_size.x - separation * 2.0
	if _self_tag.visible:
		available -= _self_tag.get_combined_minimum_size().x + separation
	if _state.visible:
		available -= _state.get_combined_minimum_size().x + separation
	var font: Font = _name.get_theme_font(&"font")
	var font_size: int = _name.get_theme_font_size(&"font_size")
	var text_width: float = font.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_name.custom_minimum_size.x = minf(ceilf(text_width), maxf(available, 0.0))
