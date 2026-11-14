class_name WeaponLoadout
extends RefCounted
## Оружие одного игрока: что у него есть и сколько патронов. Чистые правила без узлов:
## PlayerWeapons хранит такой объект на сервере и (копию с сервера) на клиенте-владельце.
## Номера оружия — номера в ItemSet; пустые руки (кулаки) есть всегда.
## Здесь же правила смены: круг клавиши Q (next_index, без оружия предателя) и цифровые
## клавиши (slot_index). Когда оружием можно ударить и когда его можно убрать — WeaponTiming.
## По сети хозяину идёт массив to_data(): [owned_mask: int, ammo: PackedInt32Array],
## где бит i маски — «оружие i есть», а ammo[i] — патроны оружия i (0 у оружия без патронов).

## Номер пустых рук (кулаков) в наборе.
const EMPTY_HANDS: int = 0
## Больше патронов одного вида игрок не носит.
const MAX_AMMO: int = 999
## get_ammo(): у оружия нет счётчика патронов (или игрок им не владеет).
const NO_AMMO_COUNTER: int = -1
## Сколько полей в массиве to_data().
const DATA_FIELD_COUNT: int = 2
## slot_index(): такую клавишу сейчас нажимать бесполезно.
const NO_SLOT: int = -1

var _items: ItemSet = null
## Биты имеющегося оружия по номерам в наборе.
var _owned: int = 1 << EMPTY_HANDS
var _ammo: PackedInt32Array = []


func _init(items: ItemSet) -> void:
	_items = items
	_ammo.resize(items.items.size())


## Может ли игрок с такой ролью и такими потерями взять это оружие со стойки.
## Нельзя: без обеих рук, двуручное без одной руки, оружие предателя — не предателю.
static func can_take(weapon: WeaponConfig, role: Game.Role, limbs_lost: int) -> bool:
	if weapon == null:
		return false
	var lost_arms: int = BodyPart.lost_arms(limbs_lost)
	if lost_arms >= BodyPart.ARM_COUNT or (lost_arms > 0 and weapon.two_handed):
		return false
	return not weapon.traitor_only or role == Game.Role.TRAITOR


## Начало раунда: кулаки у всех, оружие предателя (нож) — у предателя, патронов нет.
func reset(role: Game.Role) -> void:
	_owned = 1 << EMPTY_HANDS
	_ammo.fill(0)
	for index: int in _items.items.size():
		var weapon: WeaponConfig = _get_weapon(index)
		if weapon != null and weapon.traitor_only and role == Game.Role.TRAITOR:
			_owned |= 1 << index


## Есть ли у игрока оружие с этим номером.
func owns(index: int) -> bool:
	return _get_weapon(index) != null and _owned & (1 << index) != 0


## Патроны оружия; NO_AMMO_COUNTER — оружие их не тратит или его у игрока нет.
func get_ammo(index: int) -> int:
	var weapon: WeaponConfig = _get_weapon(index)
	if weapon == null or not weapon.uses_ammo or not owns(index):
		return NO_AMMO_COUNTER
	return _ammo[index]


## Выдать оружие: нового ещё нет — появляется, уже есть — добавляются патроны.
## false — ничего не изменилось: в наборе нет такого оружия или оно уже есть и патронов
## не тратит. Можно ли игроку его взять, решает can_take().
func give(index: int, ammo: int) -> bool:
	var weapon: WeaponConfig = _get_weapon(index)
	if weapon == null or (owns(index) and not weapon.uses_ammo):
		return false
	_owned |= 1 << index
	if weapon.uses_ammo:
		_ammo[index] = clampi(_ammo[index] + maxi(ammo, 0), 0, MAX_AMMO)
	return true


## Потратить один патрон. false — патронов нет или оружия нет; оружию без патронов —
## всегда true.
func spend_ammo(index: int) -> bool:
	var weapon: WeaponConfig = _get_weapon(index)
	if weapon == null or not owns(index):
		return false
	if not weapon.uses_ammo:
		return true
	if _ammo[index] <= 0:
		return false
	_ammo[index] -= 1
	return true


## Может ли игрок с такими потерями держать это оружие. Без обеих рук остаются только
## «кулаки» (тогда это пинок), без одной руки нельзя держать двуручное.
func can_hold(index: int, limbs_lost: int) -> bool:
	var weapon: WeaponConfig = _get_weapon(index)
	if weapon == null or not owns(index):
		return false
	var lost_arms: int = BodyPart.lost_arms(limbs_lost)
	if lost_arms >= BodyPart.ARM_COUNT:
		return index == EMPTY_HANDS
	return lost_arms == 0 or not weapon.two_handed


## Следующее по порядку набора оружие, которое игрок может держать (клавиша Q).
## Оружие предателя (нож) в этот круг не входит: его достают только цифрой, иначе предатель
## с пистолетом не мог бы убрать пистолет, не показав всем нож. С оружия предателя Q убирает
## его — в руках остаются кулаки.
## Возвращает held, если переключаться не на что; EMPTY_HANDS — если и held держать нельзя.
func next_index(held: int, limbs_lost: int) -> int:
	var held_weapon: WeaponConfig = _get_weapon(held)
	if held_weapon != null and held_weapon.traitor_only:
		return EMPTY_HANDS
	var count: int = _items.items.size()
	for offset: int in range(1, count):
		var index: int = posmod(held + offset, count)
		if can_hold(index, limbs_lost) and not _get_weapon(index).traitor_only:
			return index
	return held if can_hold(held, limbs_lost) else EMPTY_HANDS


## Оружие под цифровой клавишей: клавиша N — предмет N-1 набора (1 — кулаки, 2 — пистолет,
## 3 — нож). NO_SLOT — под этой клавишей не оружие или игрок не может его сейчас держать
## (нет такого, нет рук).
func slot_index(slot: int, limbs_lost: int) -> int:
	var index: int = slot - 1
	return index if can_hold(index, limbs_lost) else NO_SLOT


## Оружие игрока по порядку набора.
func get_owned_weapons() -> Array[WeaponConfig]:
	var result: Array[WeaponConfig] = []
	for index: int in _items.items.size():
		if owns(index):
			result.append(_get_weapon(index))
	return result


## Сервер: данные для личного сообщения хозяину (раскладка — в описании класса).
func to_data() -> Array:
	return [_owned, _ammo.duplicate()]


## Клиент-владелец: принять данные с сервера. false — данные не годятся, ничего не меняется.
func apply_data(data: Array) -> bool:
	if data.size() != DATA_FIELD_COUNT or not (data[0] is int and data[1] is PackedInt32Array):
		return false
	var owned: int = data[0]
	var ammo: PackedInt32Array = data[1]
	var count: int = _items.items.size()
	if ammo.size() != count or owned < 0 or owned >= 1 << count or owned & (1 << EMPTY_HANDS) == 0:
		return false
	for index: int in count:
		var weapon: WeaponConfig = _get_weapon(index)
		var is_owned: bool = owned & (1 << index) != 0
		# Владеть можно только оружием, патроны — только у своего оружия с патронами.
		if is_owned and weapon == null:
			return false
		if ammo[index] < 0 or ammo[index] > MAX_AMMO:
			return false
		if ammo[index] > 0 and (not is_owned or not weapon.uses_ammo):
			return false
	_owned = owned
	_ammo = ammo.duplicate()
	return true


func _get_weapon(index: int) -> WeaponConfig:
	return _items.get_item(index) as WeaponConfig
