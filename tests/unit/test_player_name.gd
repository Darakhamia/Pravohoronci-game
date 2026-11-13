extends TestCase
## PlayerName: имя приходит от клиента, поэтому проверяем враждебные варианты.

const TAB: int = 0x0009
const LINE_FEED: int = 0x000A
const DELETE: int = 0x007F
const NEXT_LINE: int = 0x0085
const NO_BREAK_SPACE: int = 0x00A0
const ZERO_WIDTH_SPACE: int = 0x200B
const ZERO_WIDTH_JOINER: int = 0x200D
const RIGHT_TO_LEFT_OVERRIDE: int = 0x202E
const WORD_JOINER: int = 0x2060
const IDEOGRAPHIC_SPACE: int = 0x3000
const BYTE_ORDER_MARK: int = 0xFEFF
const EMOJI: int = 0x1F600

const LONG_NAME: String = "1234567890123456"


func test_sanitize_keeps_normal_names() -> void:
	assert_eq(PlayerName.sanitize("Вася"), "Вася", "кириллица")
	assert_eq(PlayerName.sanitize("xX_Killer_Xx"), "xX_Killer_Xx", "латиница и знаки")
	assert_eq(PlayerName.sanitize("Вася Пупкин"), "Вася Пупкин", "один пробел внутри остаётся")
	assert_eq(PlayerName.sanitize(char(EMOJI) + "ok"), char(EMOJI) + "ok", "эмодзи — обычный символ")
	assert_eq(PlayerName.sanitize(LONG_NAME), LONG_NAME, "ровно MAX_LENGTH символов")


func test_sanitize_empty_gives_fallback() -> void:
	assert_eq(PlayerName.sanitize(""), PlayerName.FALLBACK, "пустая строка")
	assert_eq(PlayerName.sanitize("     "), PlayerName.FALLBACK, "одни пробелы")
	assert_eq(PlayerName.sanitize(char(TAB) + char(LINE_FEED)), PlayerName.FALLBACK, "одни управляющие")
	assert_eq(
			PlayerName.sanitize(char(ZERO_WIDTH_SPACE) + char(ZERO_WIDTH_JOINER) + char(BYTE_ORDER_MARK)),
			PlayerName.FALLBACK, "одни невидимые")
	assert_eq(
			PlayerName.sanitize(" " + char(RIGHT_TO_LEFT_OVERRIDE) + char(NO_BREAK_SPACE)),
			PlayerName.FALLBACK, "пробелы вперемешку с невидимыми")


func test_sanitize_removes_control_and_invisible() -> void:
	assert_eq(PlayerName.sanitize("Ва" + char(DELETE) + char(NEXT_LINE) + "ся"), "Вася", "DEL и управляющие C1")
	assert_eq(PlayerName.sanitize("Ва" + char(ZERO_WIDTH_SPACE) + "ся"), "Вася", "пробел нулевой ширины")
	assert_eq(PlayerName.sanitize(char(BYTE_ORDER_MARK) + "Вася"), "Вася", "BOM в начале")
	assert_eq(PlayerName.sanitize("Вася" + char(WORD_JOINER)), "Вася", "word joiner в конце")
	# Разворот текста: так подделывают чужой ник.
	assert_eq(PlayerName.sanitize(char(RIGHT_TO_LEFT_OVERRIDE) + "ясаВ"), "ясаВ", "RLO")


## Символы, которые не видны на экране: с ними имя выглядело бы как чужое или как пустое.
func test_sanitize_removes_every_invisible_character() -> void:
	var invisible: PackedInt32Array = [
		0x00AD, 0x034F, 0x061C, 0x115F, 0x1160, 0x17B4, 0x180E, 0x200B, 0x200D, 0x200F, 0x202E,
		0x2060, 0x2066, 0x2800, 0x3164, 0xFE0F, 0xFEFF, 0xFFA0, 0xFFF9, 0xE0020,
	]
	for code: int in invisible:
		assert_eq(PlayerName.sanitize("Ва" + char(code) + "ся"), "Вася", "U+%04X внутри имени" % code)
		assert_eq(PlayerName.sanitize(char(code) + char(code)), PlayerName.FALLBACK, "имя из одних U+%04X" % code)


func test_sanitize_collapses_whitespace() -> void:
	assert_eq(PlayerName.sanitize("  Вася  "), "Вася", "пробелы по краям")
	assert_eq(PlayerName.sanitize("Вася     Пупкин"), "Вася Пупкин", "несколько пробелов подряд")
	assert_eq(PlayerName.sanitize("Вася" + char(TAB) + "Пупкин"), "Вася Пупкин", "табуляция — разделитель слов")
	assert_eq(PlayerName.sanitize("Вася" + char(LINE_FEED) + "Пупкин"), "Вася Пупкин", "перевод строки — разделитель слов")
	assert_eq(
			PlayerName.sanitize("Вася" + char(NO_BREAK_SPACE) + char(IDEOGRAPHIC_SPACE) + "Пупкин"),
			"Вася Пупкин", "юникодные пробелы")
	assert_eq(
			PlayerName.sanitize("Вася " + char(ZERO_WIDTH_SPACE) + " Пупкин"),
			"Вася Пупкин", "пробелы, разделённые невидимым символом")
	assert_eq(PlayerName.sanitize(char(NO_BREAK_SPACE) + "Вася" + char(NO_BREAK_SPACE)), "Вася", "юникодные пробелы по краям")


func test_sanitize_limits_length() -> void:
	assert_eq(PlayerName.sanitize(LONG_NAME + "789"), LONG_NAME, "лишнее обрезается")
	assert_eq(PlayerName.sanitize("123456789012345 abc"), "123456789012345", "пробел на месте обрезки не остаётся")
	assert_eq(PlayerName.sanitize("я".repeat(1000)).length(), PlayerName.MAX_LENGTH, "очень длинное имя")
	assert_eq(
			PlayerName.sanitize(char(ZERO_WIDTH_SPACE).repeat(100) + "Вася"),
			"Вася", "невидимые символы длину не съедают")


## Чистое имя повторной чисткой не меняется: сервер и Settings могут чистить дважды.
func test_sanitize_is_stable() -> void:
	var hostile: PackedStringArray = [
		"",
		"  a  b  ",
		LONG_NAME + LONG_NAME,
		"123456789012345 abc",
		" " + char(RIGHT_TO_LEFT_OVERRIDE) + " admin " + char(LINE_FEED),
		char(EMOJI).repeat(40),
	]
	for raw: String in hostile:
		var clean: String = PlayerName.sanitize(raw)
		assert_eq(PlayerName.sanitize(clean), clean, "повторная чистка")
		assert_true(clean.length() >= 1 and clean.length() <= PlayerName.MAX_LENGTH, "длина \"%s\" в пределах 1..MAX_LENGTH" % clean)
		assert_eq(clean.strip_edges(), clean, "нет пробелов по краям")


func test_make_unique_free_name() -> void:
	assert_eq(PlayerName.make_unique("Вася", PackedStringArray()), "Вася", "список пуст")
	assert_eq(PlayerName.make_unique("Вася", ["Петя", "Вася 2"]), "Вася", "имя свободно")


func test_make_unique_adds_number() -> void:
	assert_eq(PlayerName.make_unique("Вася", ["Вася"]), "Вася 2", "первый дубль")
	assert_eq(PlayerName.make_unique("Вася", ["Вася", "Вася 2"]), "Вася 3", "второй дубль")
	assert_eq(PlayerName.make_unique("Вася", ["Вася", "Вася 3"]), "Вася 2", "берётся первый свободный номер")


func test_make_unique_respects_max_length() -> void:
	assert_eq(PlayerName.make_unique(LONG_NAME, [LONG_NAME]), "12345678901234 2", "основа укорачивается под номер")
	assert_eq(
			PlayerName.make_unique("1234567890123 56", ["1234567890123 56"]),
			"1234567890123 2", "после укорачивания нет двойного пробела")
	# Полный сервер одинаковых длинных имён: номера доходят до двузначных.
	var taken: PackedStringArray = []
	for index: int in 12:
		var unique: String = PlayerName.make_unique(LONG_NAME, taken)
		assert_true(not taken.has(unique), "имя \"%s\" ещё не занято" % unique)
		assert_true(unique.length() <= PlayerName.MAX_LENGTH, "имя \"%s\" не длиннее MAX_LENGTH" % unique)
		taken.append(unique)
	assert_eq(taken[11], "1234567890123 12", "двузначный номер")
