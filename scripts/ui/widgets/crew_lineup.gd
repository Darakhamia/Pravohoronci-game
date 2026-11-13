class_name CrewLineup
extends Control
## Знак игры на главном меню: экипаж выглядывает из-за нижнего края экрана. Все шлемы
## одинаковые, один — жёлтый, и глаза у него бегают. Один из вас врёт.

const CREW_COUNT: int = 8
## Какой по счёту шлем «не такой».
const TRAITOR_INDEX: int = 5
## Сторона шлема; промежутки делят остаток ширины поровну.
const HELMET_SIZE: float = 144.0
## Предатель косится на соседей.
const TRAITOR_LOOK: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Шлемы выше контрола: нижнюю часть срезает край.
	clip_contents = true


func _draw() -> void:
	var gap: float = (size.x - HELMET_SIZE * CREW_COUNT) / (CREW_COUNT - 1)
	for index: int in CREW_COUNT:
		var rect: Rect2 = Rect2(Vector2(roundf(index * (HELMET_SIZE + gap)), 0.0), Vector2(HELMET_SIZE, HELMET_SIZE))
		if index == TRAITOR_INDEX:
			HelmetAvatar.draw_helmet(self, rect, UiTokens.ACCENT, UiTokens.VISOR, UiTokens.EYES, TRAITOR_LOOK)
		else:
			HelmetAvatar.draw_helmet(self, rect, UiTokens.HELMET_EMPTY, UiTokens.BG, UiTokens.TEXT_DIM)
