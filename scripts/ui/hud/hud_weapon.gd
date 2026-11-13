class_name HudWeapon
extends PanelContainer
## Оружие в руках: клавиша смены, название и патроны.
## Только показывает то, что ей передали; скрыта, пока её не включит игра.

const TEXT_AMMO: String = "%d"
const AMMO_STYLE: StringName = &"LabelHudNumber"
const AMMO_EMPTY_STYLE: StringName = &"LabelHudNumberDanger"

@onready var _title: Label = %Title
@onready var _switch_key: HudKeyCap = %SwitchKey
@onready var _divider: Control = %Divider
@onready var _ammo: Label = %Ammo


## ammo < 0 — у оружия нет патронов (кулаки, нож): счётчик не показываем.
## can_switch — есть на что переключиться; иначе клавиша смены приглушена.
func set_weapon(title: String, ammo: int, can_switch: bool) -> void:
	_title.text = title
	_switch_key.set_dimmed(not can_switch)
	var has_ammo: bool = ammo >= 0
	_divider.visible = has_ammo
	_ammo.visible = has_ammo
	if has_ammo:
		_ammo.text = TEXT_AMMO % ammo
		_ammo.theme_type_variation = AMMO_EMPTY_STYLE if ammo == 0 else AMMO_STYLE
