class_name PlayerName
extends RefCounted
## Правила для имён игроков. Сервер прогоняет через них любое имя, пришедшее от клиента.

const MAX_LENGTH: int = 16
const FALLBACK: String = "Игрок"

const FIRST_DUPLICATE_NUMBER: int = 2

## Диапазоны кодов (включительно), которые из имени выбрасываются.
const REMOVED_RANGES: Array[Vector2i] = [
	Vector2i(0x0000, 0x001F),  # управляющие C0
	Vector2i(0x007F, 0x009F),  # DEL и управляющие C1
	Vector2i(0x00AD, 0x00AD),  # мягкий перенос
	Vector2i(0x034F, 0x034F),  # combining grapheme joiner
	Vector2i(0x061C, 0x061C),  # арабская метка направления
	Vector2i(0x115F, 0x1160),  # пустые символы хангыля
	Vector2i(0x17B4, 0x17B5),  # невидимые кхмерские гласные
	Vector2i(0x180B, 0x180F),  # монгольские селекторы и разделитель
	Vector2i(0x200B, 0x200F),  # нулевая ширина и метки направления
	Vector2i(0x202A, 0x202E),  # встраивание и разворот текста
	Vector2i(0x2060, 0x206F),  # word joiner, невидимые операторы, изоляторы
	Vector2i(0x2800, 0x2800),  # пустой символ Брайля
	Vector2i(0x3164, 0x3164),  # пустой символ хангыля
	Vector2i(0xFE00, 0xFE0F),  # селекторы начертания
	Vector2i(0xFEFF, 0xFEFF),  # BOM
	Vector2i(0xFFA0, 0xFFA0),  # пустой полуширинный символ хангыля
	Vector2i(0xFFF9, 0xFFFB),  # межстрочные аннотации
	Vector2i(0xE0000, 0xE0FFF),  # теги и дополнительные селекторы
]

## Отдельные пробельные символы Юникода; диапазоны проверяет _is_whitespace().
const WHITESPACE_CODES: PackedInt32Array = [0x0020, 0x00A0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]


## Убирает управляющие и невидимые символы, схлопывает пробелы, режет до MAX_LENGTH.
## Пустой результат -> FALLBACK.
static func sanitize(raw: String) -> String:
	var result: String = ""
	var space_pending: bool = false
	for index: int in raw.length():
		var code: int = raw.unicode_at(index)
		# Сначала пробелы: табуляция и перевод строки — тоже разделители слов.
		if _is_whitespace(code):
			space_pending = not result.is_empty()
			continue
		if _is_removed(code):
			continue
		if space_pending:
			result += " "
			space_pending = false
		result += raw[index]
		if result.length() >= MAX_LENGTH:
			break
	# После обрезки на конце мог остаться пробел.
	result = result.left(MAX_LENGTH).strip_edges()
	return FALLBACK if result.is_empty() else result


## base_name, если оно свободно, иначе "имя 2", "имя 3", ... — всегда не длиннее MAX_LENGTH.
static func make_unique(base_name: String, taken: PackedStringArray) -> String:
	var candidate: String = base_name
	var number: int = FIRST_DUPLICATE_NUMBER
	while taken.has(candidate):
		var suffix: String = " %d" % number
		candidate = base_name.left(MAX_LENGTH - suffix.length()).strip_edges() + suffix
		number += 1
	return candidate


## Управляющие, невидимые и меняющие направление текста символы: ими можно подделать
## чужое имя или сделать своё пустым.
static func _is_removed(code: int) -> bool:
	for code_range: Vector2i in REMOVED_RANGES:
		if code >= code_range.x and code <= code_range.y:
			return true
	return false


static func _is_whitespace(code: int) -> bool:
	return (
		(code >= 0x0009 and code <= 0x000D)
		or (code >= 0x2000 and code <= 0x200A)
		or WHITESPACE_CODES.has(code)
	)
