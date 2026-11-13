class_name PlayerVisuals
extends Node3D
## Внешний вид игрока. Сейчас заглушка: капсула с визором. Модель персонажа заменит
## эту сцену, сохранив два метода ниже, — player.tscn при этом не меняется.

## Дальше визор уезжает внутрь капсулы.
const MAX_VISOR_TILT: float = deg_to_rad(30.0)

@onready var _visor_pivot: Node3D = $VisorPivot
@onready var _name_label: Label3D = $NameLabel


func set_display_name(text: String) -> void:
	_name_label.text = text


## Наклон «головы» по взгляду игрока, радианы (вверх — плюс).
func set_look_pitch(pitch: float) -> void:
	_visor_pivot.rotation.x = clampf(pitch, -MAX_VISOR_TILT, MAX_VISOR_TILT)
