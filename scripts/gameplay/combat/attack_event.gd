class_name AttackEvent
extends RefCounted
## Событие «игрок атаковал» (Player.Event.ATTACK): сервер рассылает его всем игрокам после
## каждой состоявшейся атаки — и при попадании, и при промахе. Клиенты рисуют по нему
## взмах, трассер и вспышку. По сети идёт массив:
##   [item_index: int, from: Vector3, to: Vector3, impact: int]
## item_index — номер оружия в ItemSet; from — откуда атаковали (глаза игрока);
## to — где атака закончилась (точка попадания, стена или конец дальности);
## impact — во что она упёрлась (Impact).
## Клиент не доверяет массиву вслепую: decode() проверяет размер, типы и значения.

## Во что упёрлась атака.
enum Impact {
	## Ни во что: кончилась дальность.
	NONE,
	## В стену или предмет карты.
	WORLD,
	## В игрока.
	PLAYER,
}

## Сколько полей в массиве события.
const FIELD_COUNT: int = 4
## Насколько отрезок from–to может быть длиннее дальности оружия (погрешность чисел).
const LENGTH_TOLERANCE: float = 0.5

## Номер оружия в ItemSet.
var item_index: int = 0
## Само оружие.
var weapon: WeaponConfig = null
## Откуда атаковали, мировые координаты.
var from: Vector3 = Vector3.ZERO
## Где атака закончилась, мировые координаты.
var to: Vector3 = Vector3.ZERO
## Во что она упёрлась.
var impact: Impact = Impact.NONE


## Сервер: собрать массив для Player.send_event().
static func encode(index: int, start: Vector3, end: Vector3, hit: Impact) -> Array:
	return [index, start, end, hit]


## Клиент: разобрать массив из сети; null — данные не годятся.
static func decode(data: Array, items: ItemSet) -> AttackEvent:
	if data.size() != FIELD_COUNT or items == null:
		return null
	if not (data[0] is int and data[1] is Vector3 and data[2] is Vector3 and data[3] is int):
		return null
	var event: AttackEvent = AttackEvent.new()
	event.item_index = data[0]
	event.weapon = items.get_item(event.item_index) as WeaponConfig
	event.from = data[1]
	event.to = data[2]
	var impact_value: int = data[3]
	if event.weapon == null or not Impact.values().has(impact_value):
		return null
	if not event.from.is_finite() or not event.to.is_finite():
		return null
	if event.from.distance_to(event.to) > event.weapon.attack_range + LENGTH_TOLERANCE:
		return null
	event.impact = impact_value as Impact
	return event
