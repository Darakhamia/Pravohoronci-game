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


## Настоящие пороги из resources/game_config.tres: правило записано в CLAUDE.md, раздел 3.
func test_project_config_keeps_traitor_thresholds() -> void:
	var config: GameConfig = Game.config
	assert_eq(MatchRules.traitor_count(2, config), 0, "до двух игроков предателей нет")
	assert_eq(MatchRules.traitor_count(3, config), 1, "с трёх игроков предатель один")
	assert_eq(MatchRules.traitor_count(6, config), 1, "шесть игроков — один предатель")
	assert_eq(MatchRules.traitor_count(7, config), 2, "с семи игроков предателей двое")
	assert_eq(MatchRules.traitor_count(Net.MAX_PLAYERS, config), 2, "полный сервер — двое")


func test_combat_and_perception_settings() -> void:
	var config: GameConfig = Game.config
	assert_near(config.attack_lock_seconds, 5.0, "запрет атак после начала игры и собрания")
	assert_near(config.perception_near_radius, 2.5, "вплотную чужие руки заметны и через стену")
	assert_near(config.perception_sight_range, 45.0, "дальность, на которой видно чужие руки")
	assert_true(config.perception_near_radius < config.perception_sight_range, "вплотную — ближе, чем издалека")
	var copy: GameConfig = GameConfig.new()
	assert_true(copy.override_from_text("attack_lock_seconds", "0"), "запрет атак отключается флагом --set")
	assert_near(copy.attack_lock_seconds, 0.0, "attack_lock_seconds")
	assert_true(copy.override_from_text("perception_sight_range", "12.5"), "дальность обзора меняется флагом --set")
	assert_near(copy.perception_sight_range, 12.5, "perception_sight_range")
