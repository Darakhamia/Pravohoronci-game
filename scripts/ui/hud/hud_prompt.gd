class_name HudPrompt
extends HBoxContainer
## Подсказка действия под прицелом: один элемент — клавиша и действие. Удержание клавиши
## показывает рамка вокруг самой клавиши.
## Только показывает то, что ей передали; скрыта, пока её не вызовут.

@onready var _key: HudKeyCap = %Key
@onready var _action: Label = %Action


func _ready() -> void:
	set_hold_progress(0.0)


## Например show_prompt("E", "Починить проводку").
func show_prompt(key_text: String, action_text: String) -> void:
	_key.set_key(key_text)
	_action.text = action_text
	if not visible:
		visible = true
		UiMotion.fade_in(self)


## Доля удержания клавиши от 0 до 1; 0 прячет рамку удержания.
func set_hold_progress(fraction: float) -> void:
	_key.set_hold(fraction)


func hide_prompt() -> void:
	visible = false
	set_hold_progress(0.0)
