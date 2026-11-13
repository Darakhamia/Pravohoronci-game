class_name CmdArgs
extends RefCounted
## Разбор аргументов командной строки: флаги вида "--server" и пары "--key=value".
## Функции с суффиксом _in работают с переданным списком — их удобно тестировать.

const MIN_PORT: int = 1
const MAX_PORT: int = 65535


## Аргументы движка плюс пользовательские (всё, что после "--").
static func get_all() -> PackedStringArray:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return args


static func has_flag(flag: String) -> bool:
	return has_flag_in(get_all(), flag)


static func get_value(key: String, default_value: String = "") -> String:
	return get_value_in(get_all(), key, default_value)


static func get_int(key: String, default_value: int, min_value: int, max_value: int) -> int:
	return get_int_in(get_all(), key, default_value, min_value, max_value)


static func has_flag_in(args: PackedStringArray, flag: String) -> bool:
	return args.has(flag)


static func get_value_in(args: PackedStringArray, key: String, default_value: String = "") -> String:
	var prefix: String = key + "="
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return default_value


## Не число -> default_value, иначе значение зажимается в [min_value, max_value].
static func get_int_in(args: PackedStringArray, key: String, default_value: int, min_value: int, max_value: int) -> int:
	var text: String = get_value_in(args, key).strip_edges()
	if not text.is_valid_int():
		return default_value
	return clampi(text.to_int(), min_value, max_value)


static func is_dedicated_server() -> bool:
	return has_flag("--server") or OS.has_feature("dedicated_server")


## Разбирает "host", "host:port", "[ipv6]:port" и голый ipv6 в {"address": String, "port": int}.
## Пустой текст -> адрес "". Порт не указан или некорректен -> default_port.
static func parse_endpoint(text: String, default_port: int) -> Dictionary:
	var address: String = text.strip_edges()
	var port_text: String = ""
	if address.begins_with("["):
		var closing: int = address.find("]")
		if closing != -1:
			var rest: String = address.substr(closing + 1)
			if rest.begins_with(":"):
				port_text = rest.substr(1)
			address = address.substr(1, closing - 1)
	elif address.count(":") == 1:
		# Больше одного двоеточия без скобок — это голый ipv6, порта в нём нет.
		var colon: int = address.find(":")
		port_text = address.substr(colon + 1)
		address = address.left(colon)
	return {"address": address.strip_edges(), "port": _parse_port(port_text, default_port)}


static func _parse_port(text: String, default_port: int) -> int:
	var clean: String = text.strip_edges()
	if not clean.is_valid_int():
		return default_port
	var port: int = clean.to_int()
	if port < MIN_PORT or port > MAX_PORT:
		return default_port
	return port
