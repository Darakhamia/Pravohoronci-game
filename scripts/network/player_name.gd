class_name PlayerName
extends RefCounted
## Правила для имён игроков. Сервер прогоняет через них любое имя, пришедшее от клиента.

const MAX_LENGTH: int = 16
const FALLBACK: String = "Игрок"

const FIRST_DUPLICATE_NUMBER: int = 2

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


## Управляющие символы и невидимые/двунаправленные метки: ими можно подделать чужое имя.
static func _is_removed(code: int) -> bool:
	return (
		code < 0x0020
		or (code >= 0x007F and code <= 0x009F)
		or (code >= 0x200B and code <= 0x200F)
		or (code >= 0x202A and code <= 0x202E)
		or (code >= 0x2060 and code <= 0x2069)
		or code == 0xFEFF
	)


static func _is_whitespace(code: int) -> bool:
	return (
		(code >= 0x0009 and code <= 0x000D)
		or (code >= 0x2000 and code <= 0x200A)
		or WHITESPACE_CODES.has(code)
	)
