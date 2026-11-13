extends TestCase
## Тема интерфейса не задана в настройках проекта (gui/theme/custom): её несёт корень каждой
## сцены в scenes/ui. Так сцена выглядит одинаково в редакторе, в игре и в чужой сцене, а
## свежий клон не ругается при первом импорте. Сцена без темы молча получила бы серый
## стандартный вид движка, поэтому каждую проверяем здесь.

const UI_DIR: String = "res://scenes/ui"
const SCENE_EXTENSION: String = "tscn"
const THEME: Theme = preload("res://resources/ui/theme.tres")
const SETTING_CUSTOM_THEME: String = "gui/theme/custom"


func test_every_ui_scene_root_carries_project_theme() -> void:
	var scenes: PackedStringArray = _collect(UI_DIR)
	assert_true(not scenes.is_empty(), "в %s найдены сцены" % UI_DIR)
	for path: String in scenes:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			assert_true(false, "%s не загружается" % path)
			continue
		var root: Node = packed.instantiate()
		var control: Control = root as Control
		# Корень не Control (например, Node3D) темы не носит.
		if control != null:
			assert_true(control.theme == THEME, "%s: у корня нет theme = resources/ui/theme.tres" % path)
		root.free()


func test_project_setting_does_not_set_theme() -> void:
	var value: String = ProjectSettings.get_setting(SETTING_CUSTOM_THEME, "")
	assert_eq(value, "", "настройка %s должна быть пустой" % SETTING_CUSTOM_THEME)


func test_theme_has_variations_used_by_scripts() -> void:
	# Скрипты переключают варианты темы по имени: опечатка молча дала бы стандартный вид.
	var used: Array[StringName] = [
		HudKeyCap.ACTIVE_STYLE, HudKeyCap.DIMMED_STYLE,
		HudVitals.BAR_STYLE, HudVitals.BAR_HURT_STYLE, HudVitals.BAR_LOW_STYLE,
		HudVitals.NUMBER_STYLE, HudVitals.NUMBER_LOW_STYLE,
		HudWeapon.AMMO_STYLE, HudWeapon.AMMO_EMPTY_STYLE,
		HudAbility.TITLE_STYLE, HudAbility.TITLE_COOLDOWN_STYLE,
		HudRole.CREW_STYLE, HudRole.TRAITOR_STYLE,
		HudTaskRow.TODO_STYLE, HudTaskRow.DONE_STYLE,
		MainMenu.CONNECT_STYLE, MainMenu.CONNECT_BUSY_STYLE,
		LobbyPlayerRow.NAME_STYLE, LobbyPlayerRow.EMPTY_STYLE,
		MeetingScreen.DECK_STYLE, MeetingScreen.DECK_VERDICT_STYLE, MeetingScreen.SKIP_CHOSEN_STYLE,
		MeetingVoteCard.CARD_STYLE, MeetingVoteCard.CARD_CHOSEN_STYLE, MeetingVoteCard.CARD_EJECTED_STYLE,
		MeetingVoteCard.CARD_DEAD_STYLE, MeetingVoteCard.NAME_STYLE, MeetingVoteCard.NAME_DEAD_STYLE,
		MeetingVoteCard.TAG_OWN_VOTE_STYLE, MeetingVoteCard.TAG_EJECTED_STYLE,
		MeetingVoteCard.COUNT_STYLE, MeetingVoteCard.COUNT_EJECTED_STYLE,
		RoleReveal.CREW_STYLE, RoleReveal.TRAITOR_STYLE, RoleReveal.PARTNER_NAME_STYLE,
		ResultsScreen.WON_STYLE, ResultsScreen.LOST_STYLE, ResultsScreen.EMPTY_STYLE,
		ResultsPlayerRow.NAME_STYLE, ResultsPlayerRow.NAME_OUT_STYLE,
		KeypadPanel.HINT_STYLE, KeypadPanel.HINT_ERROR_STYLE, KeypadPanel.KEY_STYLE, KeypadPanel.CONFIRM_STYLE,
		KeypadPanel.CELL_STYLE, KeypadPanel.CELL_ACTIVE_STYLE, KeypadPanel.CELL_ERROR_STYLE,
	]
	for variation: StringName in used:
		assert_true(not THEME.get_type_variation_base(variation).is_empty(), "в теме нет варианта %s" % variation)


func _collect(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() == SCENE_EXTENSION:
			result.append(dir_path.path_join(file))
	for dir_name: String in DirAccess.get_directories_at(dir_path):
		result.append_array(_collect(dir_path.path_join(dir_name)))
	return result
