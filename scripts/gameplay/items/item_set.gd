class_name ItemSet
extends Resource
## Все предметы, которые игрок может держать в руках (resources/items/item_set.tres).
## По сети ходит номер предмета в этом списке (Player.held_item). Первый — пустые руки.
## Новые предметы добавляй в конец и увеличивай Net.PROTOCOL_VERSION.

@export var items: Array[ItemConfig] = []


## Предмет по номеру; null, если такого номера нет.
func get_item(index: int) -> ItemConfig:
	return items[index] if index >= 0 and index < items.size() else null


## Номер предмета; -1, если его нет в наборе.
func index_of(item: ItemConfig) -> int:
	return items.find(item)
