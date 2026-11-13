class_name MainMenu
extends Control
## Главное меню: имя игрока, адрес сервера, подключение.
## Саму сессию ведёт Net; об исходе подключения меню узнаёт от Main через show_status().

const TEXT_CONNECTING: String = "Подключение..."
const TEXT_NO_ADDRESS: String = "Введи адрес сервера"
const TEXT_JOIN_ERROR: String = "Не удалось начать подключение: %s"

@onready var _name_edit: LineEdit = %NameEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _connect_button: Button = %ConnectButton
@onready var _quit_button: Button = %QuitButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_name_edit.max_length = PlayerName.MAX_LENGTH
	_name_edit.text = Settings.player_name
	_address_edit.text = Settings.last_address
	# Enter в любом поле — то же, что кнопка «Подключиться».
	_name_edit.text_submitted.connect(_connect_to_server.unbind(1))
	_address_edit.text_submitted.connect(_connect_to_server.unbind(1))
	_connect_button.pressed.connect(_connect_to_server)
	_quit_button.pressed.connect(_on_quit_pressed)


## Сообщение под формой (ошибка подключения, причина кика). Заодно снова включает форму.
func show_status(text: String) -> void:
	_status_label.text = text
	_set_form_enabled(true)


func _connect_to_server() -> void:
	if Net.status != Net.Status.OFFLINE:
		# Подключение уже идёт (например, запущено через --join): просто показываем это.
		_show_connecting()
		return
	var endpoint: Dictionary = CmdArgs.parse_endpoint(_address_edit.text, Net.DEFAULT_PORT)
	var address: String = endpoint["address"]
	var port: int = endpoint["port"]
	if address.is_empty():
		show_status(TEXT_NO_ADDRESS)
		return
	Settings.player_name = _name_edit.text
	Settings.last_address = _address_edit.text
	Settings.save()
	# Settings хранит имя очищенным — показываем его таким, каким его увидят остальные.
	_name_edit.text = Settings.player_name
	var error: Error = Net.join_server(address, port, Settings.player_name)
	if error != OK:
		show_status(TEXT_JOIN_ERROR % error_string(error))
		return
	_show_connecting()


## Форма выключена до ответа: его передаст Main через show_status() или спрячет меню.
func _show_connecting() -> void:
	_status_label.text = TEXT_CONNECTING
	_set_form_enabled(false)


func _set_form_enabled(enabled: bool) -> void:
	_name_edit.editable = enabled
	_address_edit.editable = enabled
	_connect_button.disabled = not enabled


func _on_quit_pressed() -> void:
	get_tree().quit()
