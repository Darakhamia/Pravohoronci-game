class_name WeaponConfig
extends ItemConfig
## Параметры оружия. Значения лежат в resources/items/*.tres и правятся там без кода;
## здесь заглушки, чтобы редактор сохранял в ресурс каждое число.

enum Kind { MELEE, HITSCAN }

## Ближний бой (кулаки, нож) или выстрел лучом (пистолет).
@export var kind: Kind = Kind.MELEE
## Урон за одно попадание в торс; голова и конечности считаются по BodyConfig.
@export_range(0, 1000) var damage: int = 0
## Дальность удара или выстрела, м.
@export_range(0.0, 500.0, 0.1) var attack_range: float = 0.0
## Пауза между атаками, с. Столько же после атаки оружие нельзя убрать из рук.
@export_range(0.05, 60.0, 0.05) var attack_interval: float = 0.05
## Сколько секунд оружие достают: пока оно не пробыло в руках столько, им нельзя атаковать
## (после смены оружия, подбора со стойки и когда руки освободились от груза).
@export_range(0.0, 5.0, 0.05) var draw_seconds: float = 0.0
## Разброс выстрела, градусы (половина угла конуса).
@export_range(0.0, 45.0, 0.1) var spread_degrees: float = 0.0
## Толщина удара, м: на столько раздуваются хитбоксы цели. У пули 0, у кулака и ножа
## больше — в ближнем бою не нужно целиться в пиксель.
@export_range(0.0, 1.0, 0.01) var hit_radius: float = 0.0
## Нужны обе руки: без одной руки такое оружие держать нельзя.
@export var two_handed: bool = false
## Тратит ли патроны.
@export var uses_ammo: bool = false
## Есть только у предателя.
@export var traitor_only: bool = false
