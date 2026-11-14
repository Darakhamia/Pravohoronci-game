extends Node
## Корень игры. Дерево одинаковое на клиенте и сервере, чтобы пути реплицируемых узлов совпадали.
## Клиент: показывает ровно один экран. Выделенный сервер: убирает UI и запускает DedicatedServer.

@onready var _world: World = $World
@onready var _ui: CanvasLayer = $UI
@onready var _main_menu: MainMenu = %MainMenu
@onready var _lobby: Lobby = %Lobby
@onready var _hud: Hud = %Hud


func _ready() -> void:
	if CmdArgs.is_dedicated_server():
		_ui.free()
		add_child(DedicatedServer.new())
		return
	Net.connected.connect(_refresh_screens)
	Net.disconnected.connect(_on_session_ended)
	Net.connection_failed.connect(_on_session_ended)
	Game.state_changed.connect(_refresh_screens.unbind(1))
	_world.map_changed.connect(_hud.set_map)
	_refresh_screens()
	_join_from_command_line()


func _refresh_screens() -> void:
	var joined: bool = Net.is_joined()
	var in_match: bool = Game.state == Game.State.MATCH
	_main_menu.visible = not joined
	_lobby.visible = joined and not in_match
	_hud.visible = joined and in_match


func _on_session_ended(reason: String) -> void:
	_refresh_screens()
	_main_menu.show_status(reason)


## Помощник для разработки: --join=<адрес[:порт]> [--name=<имя>] подключает сразу, минуя меню.
func _join_from_command_line() -> void:
	var target: String = CmdArgs.get_value("--join")
	if target.is_empty():
		return
	var endpoint: Dictionary = CmdArgs.parse_endpoint(target, Net.DEFAULT_PORT)
	if not endpoint["port_valid"]:
		_main_menu.show_status(MainMenu.TEXT_BAD_PORT)
		return
	var address: String = endpoint["address"]
	var port: int = endpoint["port"]
	var error: Error = Net.join_server(address, port, CmdArgs.get_value("--name", Settings.player_name))
	if error == OK:
		_main_menu.show_connecting()
	else:
		_main_menu.show_status(MainMenu.describe_join_error(error))
