extends Node
## Запускает бота сценарного теста:
##   godot --headless res://tests/scenarios/scenario_bot.tscn -- --scenario=<имя> --name=Bot1 --players=<N> --port=<порт>
## Сценарий — скрипт tests/scenarios/<имя>.gd, класс которого наследует ScenarioBot.

const SCENARIO_DIR: String = "res://tests/scenarios"


func _ready() -> void:
	var scenario_name: String = CmdArgs.get_value("--scenario")
	var path: String = SCENARIO_DIR.path_join(scenario_name + ".gd")
	var script: GDScript = load(path) as GDScript if ResourceLoader.exists(path) else null
	var bot: ScenarioBot = null
	if script != null and script.can_instantiate():
		bot = script.new() as ScenarioBot
	if bot == null:
		print("SCENARIO FAIL %s: нет сценария %s или он не наследует ScenarioBot" % [scenario_name, path])
		get_tree().quit(1)
		return
	bot.scenario_name = scenario_name
	add_child(bot)
