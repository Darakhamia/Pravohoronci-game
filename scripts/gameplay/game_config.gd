class_name GameConfig
extends Resource
## Общие настройки матча. Значения лежат в res://resources/game_config.tres и правятся без кода.

## Сколько игроков нужно, чтобы хост мог начать матч.
@export_range(1, 8) var min_players: int = 5
## Карта, которую сервер загружает на старте матча.
@export_file("*.tscn") var map_scene: String = "res://scenes/maps/test_map.tscn"
