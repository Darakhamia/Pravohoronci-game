class_name GameConfig
extends Resource
## Общие настройки матча. Сами значения лежат в res://resources/game_config.tres и правятся
## там без кода; здесь заглушки, чтобы редактор сохранял в ресурс каждое значение.

## Сколько игроков нужно, чтобы хост мог начать матч.
@export_range(1, 8) var min_players: int = 1
## Карта, которую сервер загружает на старте матча.
@export_file("*.tscn") var map_scene: String = ""
