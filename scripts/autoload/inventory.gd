extends Node
## Косметика игрока. Заготовка: на клиенте это только кэш того, что позже пришлёт сервер.
## Источник правды — сервер (CLAUDE.md, раздел 4), поэтому сети и сохранения здесь нет.

signal inventory_changed

var owned_items: Array[StringName] = []
## Слот -> id надетого предмета.
var equipped: Dictionary[StringName, StringName] = {}


func apply_snapshot(new_owned: Array[StringName], new_equipped: Dictionary[StringName, StringName]) -> void:
	owned_items = new_owned.duplicate()
	equipped = new_equipped.duplicate()
	inventory_changed.emit()


func clear() -> void:
	owned_items.clear()
	equipped.clear()
	inventory_changed.emit()
