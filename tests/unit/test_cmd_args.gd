extends TestCase
## CmdArgs: разбор аргументов запуска и адреса сервера из поля ввода.

const DEFAULT_PORT: int = 7777
const ARGS: PackedStringArray = ["--headless", "--server", "--port=9000", "--name=Вася Пупкин", "--empty=", "--join=[::1]:8000"]


func test_has_flag_in() -> void:
	assert_true(CmdArgs.has_flag_in(ARGS, "--server"), "флаг из списка найден")
	assert_true(not CmdArgs.has_flag_in(ARGS, "--serve"), "часть флага — не флаг")
	assert_true(not CmdArgs.has_flag_in(ARGS, "--port"), "ключ со значением — не флаг")
	assert_true(not CmdArgs.has_flag_in(PackedStringArray(), "--server"), "в пустом списке флагов нет")


func test_get_value_in() -> void:
	assert_eq(CmdArgs.get_value_in(ARGS, "--port"), "9000", "значение ключа")
	assert_eq(CmdArgs.get_value_in(ARGS, "--name"), "Вася Пупкин", "значение с пробелом и кириллицей")
	assert_eq(CmdArgs.get_value_in(ARGS, "--join"), "[::1]:8000", "значение с двоеточиями")
	assert_eq(CmdArgs.get_value_in(ARGS, "--empty", "запас"), "", "пустое значение — это значение, а не запасное")
	assert_eq(CmdArgs.get_value_in(ARGS, "--missing"), "", "нет ключа и нет запасного")
	assert_eq(CmdArgs.get_value_in(ARGS, "--missing", "запас"), "запас", "нет ключа — запасное")
	assert_eq(CmdArgs.get_value_in(ARGS, "--server", "запас"), "запас", "флаг без '=' значения не имеет")
	assert_eq(CmdArgs.get_value_in(ARGS, "--po", "запас"), "запас", "начало ключа — другой ключ")
	assert_eq(CmdArgs.get_value_in(["--port=1", "--port=2"], "--port"), "1", "при повторе берётся первый")


func test_get_int_in() -> void:
	assert_eq(CmdArgs.get_int_in(ARGS, "--port", DEFAULT_PORT, 1, 65535), 9000, "число из аргумента")
	assert_eq(CmdArgs.get_int_in(ARGS, "--missing", DEFAULT_PORT, 1, 65535), DEFAULT_PORT, "нет ключа")
	assert_eq(CmdArgs.get_int_in(ARGS, "--empty", DEFAULT_PORT, 1, 65535), DEFAULT_PORT, "пустое значение")
	assert_eq(CmdArgs.get_int_in(ARGS, "--name", DEFAULT_PORT, 1, 65535), DEFAULT_PORT, "текст вместо числа")
	assert_eq(CmdArgs.get_int_in(["--port=80.5"], "--port", DEFAULT_PORT, 1, 65535), DEFAULT_PORT, "дробное — не целое")
	assert_eq(CmdArgs.get_int_in(["--port=80abc"], "--port", DEFAULT_PORT, 1, 65535), DEFAULT_PORT, "число с мусором")
	assert_eq(CmdArgs.get_int_in(["--port=0x50"], "--port", DEFAULT_PORT, 1, 65535), DEFAULT_PORT, "шестнадцатеричное не принимаем")
	assert_eq(CmdArgs.get_int_in(["--port=70000"], "--port", DEFAULT_PORT, 1, 65535), 65535, "больше максимума")
	assert_eq(CmdArgs.get_int_in(["--port=0"], "--port", DEFAULT_PORT, 1, 65535), 1, "меньше минимума")
	assert_eq(CmdArgs.get_int_in(["--min-players=-3"], "--min-players", 5, 1, 8), 1, "отрицательное зажимается")
	assert_eq(CmdArgs.get_int_in(["--min-players=2"], "--min-players", 5, 1, 8), 2, "значение внутри границ")


func test_parse_endpoint_host_only() -> void:
	_assert_endpoint("127.0.0.1", "127.0.0.1", DEFAULT_PORT)
	_assert_endpoint("example.com", "example.com", DEFAULT_PORT)
	_assert_endpoint("  example.com \n", "example.com", DEFAULT_PORT)


func test_parse_endpoint_host_and_port() -> void:
	_assert_endpoint("127.0.0.1:9000", "127.0.0.1", 9000)
	_assert_endpoint("example.com:1", "example.com", 1)
	_assert_endpoint("example.com:65535", "example.com", 65535)
	_assert_endpoint(" example.com : 9000 ", "example.com", 9000)


func test_parse_endpoint_bad_port() -> void:
	_assert_endpoint("example.com:", "example.com", DEFAULT_PORT)
	_assert_endpoint("example.com:abc", "example.com", DEFAULT_PORT)
	_assert_endpoint("example.com:80abc", "example.com", DEFAULT_PORT)
	_assert_endpoint("example.com:0", "example.com", DEFAULT_PORT)
	_assert_endpoint("example.com:-1", "example.com", DEFAULT_PORT)
	_assert_endpoint("example.com:65536", "example.com", DEFAULT_PORT)
	_assert_endpoint("example.com:99999999999999999999", "example.com", DEFAULT_PORT)
	_assert_endpoint("example.com:7.5", "example.com", DEFAULT_PORT)


func test_parse_endpoint_ipv6() -> void:
	_assert_endpoint("[::1]:9000", "::1", 9000)
	_assert_endpoint("[::1]", "::1", DEFAULT_PORT)
	_assert_endpoint("[2001:db8::1]:abc", "2001:db8::1", DEFAULT_PORT)
	_assert_endpoint("[2001:db8::1]:70000", "2001:db8::1", DEFAULT_PORT)
	# Без скобок двоеточий больше одного: весь текст — адрес, порта нет.
	_assert_endpoint("::1", "::1", DEFAULT_PORT)
	_assert_endpoint("2001:db8::1", "2001:db8::1", DEFAULT_PORT)
	_assert_endpoint("fe80::1:9000", "fe80::1:9000", DEFAULT_PORT)


func test_parse_endpoint_blank() -> void:
	_assert_endpoint("", "", DEFAULT_PORT)
	_assert_endpoint("   \t", "", DEFAULT_PORT)
	# Порт без адреса: адрес пустой, меню должно показать ошибку.
	_assert_endpoint(":9000", "", 9000)


func _assert_endpoint(text: String, address: String, port: int) -> void:
	var endpoint: Dictionary = CmdArgs.parse_endpoint(text, DEFAULT_PORT)
	assert_eq(endpoint.get("address"), address, "адрес из \"%s\"" % text)
	assert_eq(endpoint.get("port"), port, "порт из \"%s\"" % text)
