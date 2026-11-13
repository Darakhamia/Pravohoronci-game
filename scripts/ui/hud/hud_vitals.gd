class_name HudVitals
extends PanelContainer
## Здоровье игрока и схема повреждений по частям тела.
## Только показывает то, что ей передали; скрыта, пока её не включит игра.

const TEXT_HEALTH: String = "%d"
const BAR_STYLE: StringName = &"ProgressBarSuccess"
const BAR_HURT_STYLE: StringName = &"ProgressBarWarning"
const BAR_LOW_STYLE: StringName = &"ProgressBarDanger"
const NUMBER_STYLE: StringName = &"LabelHudNumber"
const NUMBER_LOW_STYLE: StringName = &"LabelHudNumberDanger"

@onready var _body: HudBodyDiagram = %Body
@onready var _health: Label = %Health
@onready var _bar: ProgressBar = %Bar


## Полоса зелёная, пока здоровья больше UiTokens.HEALTH_HURT, потом оранжевая, у самого дна — красная.
func set_health(health: int, max_health: int) -> void:
	var safe_max: int = maxi(max_health, 1)
	var safe_health: int = clampi(health, 0, safe_max)
	var fraction: float = float(safe_health) / safe_max
	var is_low: bool = fraction <= UiTokens.HEALTH_CRITICAL
	_health.text = TEXT_HEALTH % safe_health
	_health.theme_type_variation = NUMBER_LOW_STYLE if is_low else NUMBER_STYLE
	_bar.max_value = safe_max
	_bar.value = safe_health
	if is_low:
		_bar.theme_type_variation = BAR_LOW_STYLE
	else:
		_bar.theme_type_variation = BAR_HURT_STYLE if fraction <= UiTokens.HEALTH_HURT else BAR_STYLE


## fractions — шесть значений по номерам BodyPart.Part: 1.0 — часть цела, 0.0 — здоровья нет.
## lost_mask — биты BodyPart.bit() отлетевших конечностей.
func set_parts(fractions: PackedFloat32Array, lost_mask: int) -> void:
	_body.set_parts(fractions, lost_mask)
