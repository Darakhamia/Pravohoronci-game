class_name HudAbility
extends PanelContainer
## Способность предателя (саботаж): клавиша, название и перезарядка.
## Только показывает то, что ей передали; скрыта, пока её не включит игра.

const TEXT_COOLDOWN: String = "%d с"
const TITLE_STYLE: StringName = &"LabelHud"
const TITLE_COOLDOWN_STYLE: StringName = &"LabelHudDim"

@onready var _key: HudKeyCap = %Key
@onready var _title: Label = %Title
@onready var _divider: Control = %Divider
@onready var _cooldown: Label = %Cooldown


## cooldown_left > 0 — способность перезаряжается: показываем секунды и приглушаем клавишу.
## available == false — сейчас её нельзя включить и без перезарядки (например, саботаж уже идёт):
## клавиша и название тоже приглушены.
func set_ability(key_text: String, title: String, cooldown_left: float, available: bool = true) -> void:
	var on_cooldown: bool = cooldown_left > 0.0
	var dimmed: bool = on_cooldown or not available
	_key.set_key(key_text)
	_key.set_dimmed(dimmed)
	_title.text = title
	_title.theme_type_variation = TITLE_COOLDOWN_STYLE if dimmed else TITLE_STYLE
	_divider.visible = on_cooldown
	_cooldown.visible = on_cooldown
	if on_cooldown:
		_cooldown.text = TEXT_COOLDOWN % ceili(cooldown_left)
