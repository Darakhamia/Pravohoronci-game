class_name PlayerPalette
extends RefCounted
## Цвета игроков. Номер цвета закрепляет за игроком сервер (Net.get_player_color), по нему
## игроков различают в лобби, на карте и при голосовании.

const COLORS: Array[Color] = [
	Color("ff4d5e"),
	Color("ff9f1c"),
	Color("ffd23f"),
	Color("4ade80"),
	Color("22d3ee"),
	Color("4f7cff"),
	Color("a855f7"),
	Color("ff6fb5"),
]
const NAMES: PackedStringArray = [
	"Красный", "Оранжевый", "Жёлтый", "Зелёный", "Голубой", "Синий", "Фиолетовый", "Розовый",
]
## Цвет для того, у кого номера нет (не должен встречаться в игре).
const FALLBACK: Color = Color("9aa0b8")


static func color(slot: int) -> Color:
	return COLORS[slot] if slot >= 0 and slot < COLORS.size() else FALLBACK


static func color_name(slot: int) -> String:
	return NAMES[slot] if slot >= 0 and slot < NAMES.size() else ""
