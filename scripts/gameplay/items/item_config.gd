class_name ItemConfig
extends Resource
## Предмет, который игрок держит в руках: оружие (WeaponConfig) или груз вроде канистры.
## Значения лежат в resources/items/*.tres и правятся там без кода.

## Название в интерфейсе: «Пистолет».
@export var title: String = ""
## Модель в руке: начало координат в месте хвата, смотрит вдоль -Z. Пусто — пустые руки.
@export var model: PackedScene = null
