class_name GameConfig
extends Resource
## Общие настройки матча. Сами значения лежат в res://resources/game_config.tres и правятся
## там без кода; здесь заглушки, чтобы редактор сохранял в ресурс каждое значение.
## Сервер может переопределить любое число при запуске: --set=<имя>=<значение>.
## Клиент по этим числам ничего не решает: длительности ему присылает сервер.

@export_group("Лобби")
## Сколько игроков нужно, чтобы хост мог начать матч.
@export_range(1, 8) var min_players: int = 1
## Карта, которую сервер загружает на старте матча.
@export_file("*.tscn") var map_scene: String = ""

@export_group("Роли")
## С какого числа игроков в матче есть предатель. Меньше — предателей нет (отладка).
@export_range(1, 9) var players_for_one_traitor: int = 1
## С какого числа игроков предателей двое.
@export_range(1, 9) var players_for_two_traitors: int = 1
## Сколько секунд игроки стоят и читают свою роль в начале матча. 0 — без паузы.
@export_range(0.0, 30.0) var role_reveal_seconds: float = 0.0
## Сколько секунд показываем итоги перед возвратом в лобби.
@export_range(0.0, 60.0) var results_seconds: float = 0.0

@export_group("Задания")
## Сколько заданий получает каждый игрок.
@export_range(0, 12) var tasks_per_player: int = 0

@export_group("Собрание")
@export_range(0.0, 120.0) var meeting_discussion_seconds: float = 0.0
@export_range(1.0, 300.0) var meeting_voting_seconds: float = 1.0
@export_range(0.0, 30.0) var meeting_verdict_seconds: float = 0.0
## Сколько раз за матч один игрок может нажать тревожную кнопку.
@export_range(0, 9) var emergency_meetings_per_player: int = 0
## Пауза перед тем, как кнопку можно нажать: с начала матча и после каждого собрания.
@export_range(0.0, 120.0) var emergency_cooldown_seconds: float = 0.0
## Показывать ли роль изгнанного.
@export var reveal_role_on_eject: bool = false

@export_group("Саботаж")
## Сколько секунд есть на починку, прежде чем победят предатели.
@export_range(1.0, 300.0) var sabotage_countdown_seconds: float = 1.0
## Пауза между саботажами.
@export_range(0.0, 300.0) var sabotage_cooldown_seconds: float = 0.0
## Пауза перед первым саботажем с начала матча.
@export_range(0.0, 300.0) var sabotage_first_delay_seconds: float = 0.0

@export_group("Бой")
## Сколько секунд после начала игры (после показа ролей) и после каждого собрания никто
## не может атаковать: иначе предатель с ножом в руке убивал бы соседа по столу в ту же
## секунду. Менять оружие в это время можно.
@export_range(0.0, 60.0, 0.1) var attack_lock_seconds: float = 0.0

@export_group("Видимость")
## Ближе этого (от глаз, м) игрок замечает, что у другого в руках и что тот атаковал,
## даже через стену. Правило целиком — в Perception.
@export_range(0.0, 20.0, 0.1) var perception_near_radius: float = 0.0
## Дальше этого (м) чужие руки и атаки не различить, даже если между игроками нет стен.
@export_range(0.0, 500.0, 0.5) var perception_sight_range: float = 0.0


## Сервер: переопределить число или флаг по имени свойства (флаг запуска --set).
## Возвращает false, если такого свойства нет или текст не подходит по типу.
func override_from_text(property: String, text: String) -> bool:
	var script: Script = get_script()
	for info: Dictionary in script.get_script_property_list():
		var usage: int = info["usage"]
		if info["name"] != property or usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		match info["type"] as int:
			TYPE_INT:
				if not text.is_valid_int():
					return false
				set(property, text.to_int())
			TYPE_FLOAT:
				if not text.is_valid_float():
					return false
				set(property, text.to_float())
			TYPE_BOOL:
				if text != "true" and text != "false":
					return false
				set(property, text == "true")
			_:
				return false
		return true
	return false
