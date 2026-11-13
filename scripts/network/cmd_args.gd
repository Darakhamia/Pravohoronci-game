class_name CmdArgs
extends RefCounted
## Разбор аргументов командной строки: флаги вида "--server" и пары "--key=value".
## Функции с суффиксом _in работают с переданным списком — их удобно тестировать.

const MIN_PORT: int = 1
const MAX_PORT: int = 65535
## Больше цифр в int64 не помещается: to_int() на таком тексте пишет ошибку движка.
const MAX_INT_TEXT_LENGTH: int = 18


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


## Все значения ключа, который можно указать несколько раз: --set=a=1 --set=b=2.
static func get_values(key: String) -> PackedStringArray:
	return get_values_in(get_all(), key)


static func has_flag_in(args: PackedStringArray, flag: String) -> bool:
	return args.has(flag)


static func get_value_in(args: PackedStringArray, key: String, default_value: String = "") -> String:
	var prefix: String = key + "="
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return default_value


static func get_values_in(args: PackedStringArray, key: String) -> PackedStringArray:
	var prefix: String = key + "="
	var values: PackedStringArray = []
	for arg: String in args:
		if arg.begins_with(prefix):
			values.append(arg.substr(prefix.length()))
	return values


## Не число -> default_value, иначе значение зажимается в [min_value, max_value].
static func get_int_in(args: PackedStringArray, key: String, default_value: int, min_value: int, max_value: int) -> int:
	var text: String = get_value_in(args, key).strip_edges()
	if not _is_int_text(text):
		return default_value
	return clampi(text.to_int(), min_value, max_value)


static func is_dedicated_server() -> bool:
	return has_flag("--server") or OS.has_feature("dedicated_server")


## Разбирает "host", "host:port", "[ipv6]:port" и голый ipv6 в
## {"address": String, "port": int, "port_valid": bool}.
## Пустой текст -> адрес "". Порт не указан -> default_port. Порт указан, но это не число
## 1..65535 -> тоже default_port, но port_valid == false: меню может сказать об опечатке.
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
	port_text = port_text.strip_edges()
	var port: int = port_text.to_int() if _is_int_text(port_text) else 0
	var is_port: bool = port >= MIN_PORT and port <= MAX_PORT
	return {
		"address": address.strip_edges(),
		"port": port if is_port else default_port,
		"port_valid": is_port or port_text.is_empty(),
	}


static func _is_int_text(text: String) -> bool:
	return text.is_valid_int() and text.length() <= MAX_INT_TEXT_LENGTH
