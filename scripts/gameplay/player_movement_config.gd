class_name PlayerMovementConfig
extends Resource
## Параметры движения игрока. Сами значения лежат в resources/player/player_movement.tres
## и правятся там; здесь нули, чтобы редактор сохранял в ресурс каждое число.

## Скорость бега, м/с.
@export var move_speed: float = 0.0
## Разгон и торможение на земле, м/с².
@export var ground_acceleration: float = 0.0
## Управляемость в воздухе, м/с².
@export var air_acceleration: float = 0.0
## Вертикальная скорость в момент прыжка, м/с.
@export var jump_velocity: float = 0.0
## Ускорение падения, м/с².
@export var gravity: float = 0.0
