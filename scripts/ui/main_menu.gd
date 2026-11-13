class_name MainMenu
extends Control
## Главное меню: имя игрока, адрес сервера, подключение.
## Саму сессию ведёт Net; об исходе подключения меню узнаёт от Main через show_status().
## Пока идёт подключение, главная кнопка сама становится индикатором: «Подключение...»
## и вращающаяся дуга. Ошибка — строка со значком под кнопками, не длиннее трёх строк.

const TEXT_CONNECT: String = "Подключиться"
const TEXT_CONNECTING: String = "Подключение..."
const TEXT_NO_ADDRESS: String = "Введи адрес сервера"
const TEXT_BAD_PORT: String = "Неверный порт в адресе сервера"
const TEXT_BAD_ADDRESS: String = "Не удалось открыть соединение. Проверь адрес сервера"
const TEXT_JOIN_ERROR: String = "Не удалось начать подключение: %s"

## Варианты темы главной кнопки: обычная и «идёт подключение».
const CONNECT_STYLE: StringName = &"ButtonPrimary"
const CONNECT_BUSY_STYLE: StringName = &"ButtonBusy"

@onready var _name_edit: LineEdit = %NameEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _connect_button: Button = %ConnectButton
@onready var _quit_button: Button = %QuitButton
@onready var _spinner: Control = %Spinner
@onready var _status: Control = %Status
@onready var _status_label: Label = %StatusLabel
@onready var _page: Control = %Page
## Стрелка на кнопке: на время подключения её место занимает индикатор.
@onready var _connect_icon: Texture2D = _connect_button.icon


func _ready() -> void:
	_name_edit.max_length = PlayerName.MAX_LENGTH
	_name_edit.text = Settings.player_name
	_address_edit.text = Settings.last_address
	# Enter в любом поле — то же, что кнопка «Подключиться».
	_name_edit.text_submitted.connect(_connect_to_server.unbind(1))
	_address_edit.text_submitted.connect(_connect_to_server.unbind(1))
	_connect_button.pressed.connect(_connect_to_server)
	_quit_button.pressed.connect(_on_quit_pressed)
	visibility_changed.connect(_on_visibility_changed)


## Сообщение под формой (ошибка подключения, причина кика). Заодно снова включает форму.
## Пустой текст убирает сообщение.
func show_status(text: String) -> void:
	_status_label.text = text
	_status.visible = not text.is_empty()
	_set_form_enabled(true)


## Подключение началось не из меню (запуск с --join): показываем это и выключаем форму.
func show_connecting() -> void:
	_status.visible = false
	_set_form_enabled(false)


## Текст для игрока по коду ошибки Net.join_server().
static func describe_join_error(error: Error) -> String:
	# ENet так отвечает на адрес, который не удалось разобрать или найти.
	if error == ERR_CANT_CREATE:
		return TEXT_BAD_ADDRESS
	return TEXT_JOIN_ERROR % error_string(error)


func _connect_to_server() -> void:
	if Net.status != Net.Status.OFFLINE:
		return
	var endpoint: Dictionary = CmdArgs.parse_endpoint(_address_edit.text, Net.DEFAULT_PORT)
	var address: String = endpoint["address"]
	var port: int = endpoint["port"]
	if address.is_empty():
		show_status(TEXT_NO_ADDRESS)
		return
	if not endpoint["port_valid"]:
		show_status(TEXT_BAD_PORT)
		return
	Settings.player_name = _name_edit.text
	Settings.last_address = _address_edit.text
	Settings.save()
	# Settings хранит имя очищенным — показываем его таким, каким его увидят остальные.
	_name_edit.text = Settings.player_name
	var error: Error = Net.join_server(address, port, Settings.player_name)
	if error != OK:
		show_status(describe_join_error(error))
		return
	# Форма выключена до ответа: его передаст Main через show_status() или спрячет меню.
	show_connecting()


func _set_form_enabled(enabled: bool) -> void:
	_name_edit.editable = enabled
	_address_edit.editable = enabled
	_connect_button.disabled = not enabled
	_connect_button.text = TEXT_CONNECT if enabled else TEXT_CONNECTING
	_connect_button.icon = _connect_icon if enabled else null
	_connect_button.theme_type_variation = CONNECT_STYLE if enabled else CONNECT_BUSY_STYLE
	_spinner.visible = not enabled


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		UiMotion.fade_in(_page)


func _on_quit_pressed() -> void:
	get_tree().quit()
