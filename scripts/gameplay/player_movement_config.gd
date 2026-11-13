class_name PlayerMovementConfig
extends Resource
## Параметры движения игрока. Значения правятся в resources/player/player_movement.tres.

## Скорость бега, м/с.
@export var move_speed: float = 5.0
## Разгон и торможение на земле, м/с².
@export var ground_acceleration: float = 40.0
## Управляемость в воздухе, м/с².
@export var air_acceleration: float = 8.0
## Вертикальная скорость в момент прыжка, м/с.
@export var jump_velocity: float = 5.5
## Ускорение падения, м/с².
@export var gravity: float = 15.0
