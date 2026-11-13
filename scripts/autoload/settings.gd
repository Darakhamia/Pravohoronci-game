extends Node
## Локальные настройки игрока в user://settings.cfg.
## Сервер и запуски без окна (боты, тесты) файл не читают и не пишут: им личные настройки
## не нужны, а тесты не должны зависеть от того, что лежит на машине разработчика.

## Для будущего экрана настроек: сейчас значения читаются один раз, сигнал никто не слушает.
signal changed(key: StringName)

const FILE_PATH: String = "user://settings.cfg"
const BROKEN_FILE_PATH: String = "user://settings.cfg.bad"
const HEADLESS_DISPLAY: String = "headless"
const SECTION: String = "settings"
const MASTER_BUS: StringName = &"Master"

const DEFAULT_ADDRESS: String = "127.0.0.1"
const DEFAULT_MOUSE_SENSITIVITY: float = 0.0025
const MIN_MOUSE_SENSITIVITY: float = 0.0002
const MAX_MOUSE_SENSITIVITY: float = 0.02
const DEFAULT_FOV: float = 70.0
const MIN_FOV: float = 55.0
const MAX_FOV: float = 90.0
const DEFAULT_MASTER_VOLUME: float = 1.0

## Всегда хранится очищенным через PlayerName.sanitize().
var player_name: String = PlayerName.FALLBACK:
	set(value):
		player_name = PlayerName.sanitize(value)
		changed.emit(&"player_name")

## Текст поля адреса, может содержать ":порт".
var last_address: String = DEFAULT_ADDRESS:
	set(value):
		var clean: String = value.strip_edges()
		last_address = DEFAULT_ADDRESS if clean.is_empty() else clean
		changed.emit(&"last_address")

## Радианы поворота на пиксель движения мыши.
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY:
	set(value):
		mouse_sensitivity = _sane(value, DEFAULT_MOUSE_SENSITIVITY, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
		changed.emit(&"mouse_sensitivity")

## Вертикальный угол обзора камеры, градусы. 70° — это около 103° по горизонтали на 16:9.
var fov: float = DEFAULT_FOV:
	set(value):
		fov = _sane(value, DEFAULT_FOV, MIN_FOV, MAX_FOV)
		changed.emit(&"fov")

## 0..1, применяется к шине Master.
var master_volume: float = DEFAULT_MASTER_VOLUME:
	set(value):
		master_volume = _sane(value, DEFAULT_MASTER_VOLUME, 0.0, 1.0)
		_apply_master_volume()
		changed.emit(&"master_volume")


func _ready() -> void:
	if not _uses_file():
		return
	_load()
	_apply_master_volume()


func save() -> void:
	if not _uses_file():
		return
	var config := ConfigFile.new()
	config.set_value(SECTION, "player_name", player_name)
	config.set_value(SECTION, "last_address", last_address)
	config.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION, "fov", fov)
	config.set_value(SECTION, "master_volume", master_volume)
	var error: Error = config.save(FILE_PATH)
	if error != OK:
		push_warning("Не удалось сохранить настройки: %s" % error_string(error))


func _load() -> void:
	if not FileAccess.file_exists(FILE_PATH):
		return
	var config := ConfigFile.new()
	if config.load(FILE_PATH) != OK:
		# Испорченный файл убираем в сторону, иначе движок ругался бы на него при каждом запуске.
		DirAccess.remove_absolute(BROKEN_FILE_PATH)
		DirAccess.rename_absolute(FILE_PATH, BROKEN_FILE_PATH)
		push_warning("Файл настроек испорчен и переименован в %s, взяты значения по умолчанию" % BROKEN_FILE_PATH)
		return
	player_name = _read_string(config, "player_name", player_name)
	last_address = _read_string(config, "last_address", last_address)
	mouse_sensitivity = _read_float(config, "mouse_sensitivity", mouse_sensitivity)
	fov = _read_float(config, "fov", fov)
	master_volume = _read_float(config, "master_volume", master_volume)


static func _uses_file() -> bool:
	return not CmdArgs.is_dedicated_server() and DisplayServer.get_name() != HEADLESS_DISPLAY


func _apply_master_volume() -> void:
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index(MASTER_BUS), master_volume)


## Значение чужого типа (файл правили руками) заменяем запасным.
static func _read_string(config: ConfigFile, key: String, fallback: String) -> String:
	var value: Variant = config.get_value(SECTION, key, fallback)
	return value as String if value is String else fallback


static func _read_float(config: ConfigFile, key: String, fallback: float) -> float:
	var value: Variant = config.get_value(SECTION, key, fallback)
	return value as float if value is float or value is int else fallback


static func _sane(value: float, fallback: float, min_value: float, max_value: float) -> float:
	return clampf(value, min_value, max_value) if is_finite(value) else fallback
