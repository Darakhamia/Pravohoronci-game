extends TestCase
## Переопределение настроек матча флагом сервера --set.


func test_override_sets_numbers_and_flags() -> void:
	var config: GameConfig = GameConfig.new()
	assert_true(config.override_from_text("tasks_per_player", "7"), "целое число")
	assert_eq(config.tasks_per_player, 7, "tasks_per_player")
	assert_true(config.override_from_text("role_reveal_seconds", "0.5"), "дробное число")
	assert_near(config.role_reveal_seconds, 0.5, "role_reveal_seconds")
	assert_true(config.override_from_text("results_seconds", "3"), "целое в дробное свойство")
	assert_near(config.results_seconds, 3.0, "results_seconds")
	assert_true(config.override_from_text("reveal_role_on_eject", "true"), "флаг")
	assert_eq(config.reveal_role_on_eject, true, "reveal_role_on_eject")
	assert_true(config.override_from_text("reveal_role_on_eject", "false"), "флаг обратно")
	assert_eq(config.reveal_role_on_eject, false, "reveal_role_on_eject")


func test_override_rejects_wrong_input() -> void:
	var config: GameConfig = GameConfig.new()
	var tasks_before: int = config.tasks_per_player
	assert_true(not config.override_from_text("tasks_per_player", "много"), "текст вместо числа")
	assert_true(not config.override_from_text("tasks_per_player", "1.5"), "дробь в целое свойство")
	assert_true(not config.override_from_text("tasks_per_player", ""), "пустое значение")
	assert_eq(config.tasks_per_player, tasks_before, "значение не изменилось")
	assert_true(not config.override_from_text("reveal_role_on_eject", "1"), "флаг не словом")
	assert_true(not config.override_from_text("no_such_property", "1"), "неизвестное свойство")
	assert_true(not config.override_from_text("map_scene", "res://x.tscn"), "строки менять нельзя")
	assert_true(not config.override_from_text("resource_name", "x"), "встроенные свойства менять нельзя")
	assert_true(not config.override_from_text("", "1"), "пустое имя")


func test_project_config_has_sane_values() -> void:
	var config: GameConfig = Game.config
	assert_true(config.min_players >= 1 and config.min_players <= Net.MAX_PLAYERS, "min_players в пределах сервера")
	assert_true(config.players_for_one_traitor <= config.players_for_two_traitors, "пороги предателей по возрастанию")
	assert_true(World.find_map_scenes().has(config.map_scene), "основная карта лежит в папке карт")
	assert_true(config.meeting_voting_seconds > 0.0, "на голосование есть время")
	assert_true(config.sabotage_countdown_seconds > 0.0, "на починку саботажа есть время")
