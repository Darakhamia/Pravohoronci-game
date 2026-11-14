class_name BodyConfig
extends Resource
## Параметры здоровья и частей тела. Сами значения лежат в resources/player/body_config.tres
## и правятся там; здесь заглушки, чтобы редактор сохранял в ресурс каждое число.

@export_group("Здоровье")
## Общее здоровье игрока.
@export_range(1, 1000) var max_health: int = 1
## Здоровье одной конечности: кончилось — конечность отлетает.
@export_range(1, 1000) var limb_health: int = 1

@export_group("Урон")
## Во сколько раз попадание в голову сильнее попадания в торс.
@export_range(0.0, 10.0, 0.05) var head_multiplier: float = 0.0
## Какая доля урона по конечности уходит ещё и из общего здоровья.
@export_range(0.0, 10.0, 0.05) var limb_multiplier: float = 0.0

@export_group("Потеря конечностей")
## Скорость без одной ноги (доля обычной).
@export_range(0.0, 1.0, 0.05) var one_leg_speed_factor: float = 0.0
## Скорость ползком, без обеих ног.
@export_range(0.0, 1.0, 0.05) var crawl_speed_factor: float = 0.0
## Высота глаз стоя и ползком, м.
@export_range(0.1, 2.5, 0.05) var stand_eye_height: float = 0.1
@export_range(0.1, 2.5, 0.05) var crawl_eye_height: float = 0.1
## Во сколько раз растёт разброс оружия без одной руки.
@export_range(1.0, 10.0, 0.1) var one_arm_spread_factor: float = 1.0
