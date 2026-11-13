class_name WeaponPickup
extends Interactable
## Стойка с оружием на карте: игрок подбирает его клавишей E.
## Заготовка: карта уже может расставлять стойки, сама выдача оружия — в модуле боя.

## Какое оружие лежит на стойке.
@export var weapon: WeaponConfig = null
## Сколько патронов получает подобравший.
@export_range(0, 999) var ammo: int = 0
