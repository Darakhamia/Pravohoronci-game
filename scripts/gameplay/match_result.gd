class_name MatchResult
extends RefCounted
## Итог матча: кто победил и кем был каждый участник. Сервер собирает его в конце матча
## и рассылает всем — только с этого момента роли известны каждому.

## Сколько значений в строке, которой запись передаётся по сети.
const ROW_SIZE: int = 5

## Одна строка итогов.
class Entry:
	var peer_id: int = 0
	## Имя на момент конца матча; у вышедшего — каким оно было на старте.
	var name: String = ""
	## Номер цвета из PlayerPalette.
	var color_slot: int = -1
	var role: Game.Role = Game.Role.NONE
	## Дожил ли до конца матча (вышедший из игры — нет).
	var alive: bool = false


var winner: Game.Winner = Game.Winner.NONE
var reason: Game.EndReason = Game.EndReason.NONE
var entries: Array[Entry] = []


func add_entry(peer_id: int, name: String, color_slot: int, role: Game.Role, alive: bool) -> void:
	var entry: Entry = Entry.new()
	entry.peer_id = peer_id
	entry.name = name
	entry.color_slot = color_slot
	entry.role = role
	entry.alive = alive
	entries.append(entry)


func get_entry(peer_id: int) -> Entry:
	for entry: Entry in entries:
		if entry.peer_id == peer_id:
			return entry
	return null


## Победил ли этот участник. Не участник — false.
func did_win(peer_id: int) -> bool:
	var entry: Entry = get_entry(peer_id)
	if entry == null:
		return false
	if winner == Game.Winner.CREW:
		return entry.role == Game.Role.CREW
	return winner == Game.Winner.TRAITORS and entry.role == Game.Role.TRAITOR


## Записи в виде, пригодном для RPC: массив строк [peer_id, имя, цвет, роль, жив].
func to_rows() -> Array:
	var rows: Array = []
	for entry: Entry in entries:
		rows.append([entry.peer_id, entry.name, entry.color_slot, entry.role, entry.alive])
	return rows


## Собирает итог из того, что пришло по сети. null, если данные не похожи на итог.
static func from_rows(winner_value: int, reason_value: int, rows: Array) -> MatchResult:
	if not Game.Winner.values().has(winner_value) or not Game.EndReason.values().has(reason_value):
		return null
	if rows.size() > Net.MAX_PLAYERS:
		return null
	var result: MatchResult = MatchResult.new()
	result.winner = winner_value as Game.Winner
	result.reason = reason_value as Game.EndReason
	for row: Variant in rows:
		if not row is Array:
			return null
		var values: Array = row
		if values.size() != ROW_SIZE:
			return null
		if not (values[0] is int and values[1] is String and values[2] is int
				and values[3] is int and values[4] is bool):
			return null
		var role_value: int = values[3]
		if not Game.Role.values().has(role_value):
			return null
		var name: String = values[1]
		result.add_entry(values[0] as int, name, values[2] as int, role_value as Game.Role, values[4] as bool)
	return result
