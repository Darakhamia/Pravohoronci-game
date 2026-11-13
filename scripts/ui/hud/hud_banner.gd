class_name HudBanner
extends PanelContainer
## Строка сведений внизу экрана: наблюдатель, призрак. Значок глаза — «ты только смотришь».
## Только показывает то, что ей передали; скрыта, пока её не вызовут.

@onready var _text: Label = %Text


func show_banner(text: String) -> void:
	_text.text = text
	visible = true


func hide_banner() -> void:
	visible = false
