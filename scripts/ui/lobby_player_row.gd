class_name LobbyPlayerRow
extends VBoxContainer
## Одна строка списка лобби: шлем цвета игрока, имя и метки «ты» / «хост».
## Свободное место — шлем без хозяина и тихая подпись. Данные приходят от Lobby.

const TEXT_EMPTY: String = "свободно"
const NAME_STYLE: StringName = &"LabelStrong"
const EMPTY_STYLE: StringName = &"LabelFaint"

@onready var _helmet: HelmetAvatar = %Helmet
@onready var _name: Label = %Name
@onready var _host_tag: Label = %HostTag
@onready var _self_tag: Label = %SelfTag


func set_player(player_name: String, color: Color, is_host: bool, is_self: bool) -> void:
	_helmet.set_style(HelmetAvatar.Style.NORMAL)
	_helmet.set_player_color(color)
	_name.theme_type_variation = NAME_STYLE
	_name.text = player_name
	_host_tag.visible = is_host
	_self_tag.visible = is_self


func set_empty() -> void:
	_helmet.set_style(HelmetAvatar.Style.EMPTY)
	_name.theme_type_variation = EMPTY_STYLE
	_name.text = TEXT_EMPTY
	_host_tag.visible = false
	_self_tag.visible = false
