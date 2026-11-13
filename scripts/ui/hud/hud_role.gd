class_name HudRole
extends PanelContainer
## Плашка роли в углу HUD: «ЭКИПАЖ» или «ПРЕДАТЕЛЬ» и напарник предателя.
## Только показывает то, что ей передали; скрыта, пока её не включит игра.

const TEXT_CREW: String = "Экипаж"
const TEXT_TRAITOR: String = "Предатель"
const TEXT_PARTNER: String = "напарник: %s"
const TEXT_PARTNERS: String = "напарники: %s"
const NAME_SEPARATOR: String = ", "
const CREW_STYLE: StringName = &"LabelOverlineCyan"
const TRAITOR_STYLE: StringName = &"LabelOverlineDanger"
## Строка напарников шире этого обрезается многоточием: справа от роли стоит тревога.
const MAX_PARTNER_WIDTH: float = 360.0

@onready var _title: Label = %Title
@onready var _divider: Control = %Divider
@onready var _partner: Label = %Partner


## partner_names — имена остальных предателей; экипажу передают пустой список.
func set_role(is_traitor: bool, partner_names: PackedStringArray) -> void:
	_title.text = TEXT_TRAITOR if is_traitor else TEXT_CREW
	_title.theme_type_variation = TRAITOR_STYLE if is_traitor else CREW_STYLE
	var has_partner: bool = is_traitor and not partner_names.is_empty()
	_divider.visible = has_partner
	_partner.visible = has_partner
	if has_partner:
		var template: String = TEXT_PARTNER if partner_names.size() == 1 else TEXT_PARTNERS
		_partner.text = template % NAME_SEPARATOR.join(partner_names)
		# Надпись с многоточием сама ширины не просит: даём ей ширину текста, но не больше предела.
		var font: Font = _partner.get_theme_font(&"font")
		var font_size: int = _partner.get_theme_font_size(&"font_size")
		var text_width: float = font.get_string_size(_partner.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		_partner.custom_minimum_size.x = minf(ceilf(text_width), MAX_PARTNER_WIDTH)
