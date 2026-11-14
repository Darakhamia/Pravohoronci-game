class_name LimbBurst
extends Node3D
## Вспышка на месте разъёма, когда сегмент скафандра отстёгивается: сноп раскалённых искр,
## струя белого пара из разгерметизированного разъёма, несколько металлических обломков и
## короткий блик. Чисто визуальная и разовая: создаётся только на клиентах (PlayerVisuals не
## создаёт её без окна) и сама себя удаляет.
##
## Искры ярче единицы (цвет в HDR), поэтому их подхватывает свечение кадра. Часть искр и
## обломки долетают до пола, отскакивают и гаснут: пол для частиц — своя плита столкновений,
## которую вспышка кладёт на высоту floor_height.

## Через сколько секунд узел удаляется: к этому времени все частицы погасли.
const LIFETIME_SEC: float = 1.7
const FLASH_SEC: float = 0.25
## Плита пола для частиц: её верх — на высоте пола.
const FLOOR_HALF_THICKNESS: float = 0.5

@onready var _sparks: GPUParticles3D = $Sparks
@onready var _bits: GPUParticles3D = $Bits
@onready var _vapor: GPUParticles3D = $Vapor
@onready var _flash: OmniLight3D = $Flash
@onready var _floor: GPUParticlesCollisionBox3D = $Floor


## Запускает вспышку в точке origin (в мире); искры летят в сторону direction.
## floor_height — высота пола под игроком в мире: об него искры отскакивают (NAN — пола нет).
## Вызывать после добавления в дерево.
func play(origin: Vector3, direction: Vector3, floor_height: float = NAN) -> void:
	var forward: Vector3 = direction.normalized() if direction.length() > 0.001 else Vector3.UP
	# Частицы летят вдоль локальной оси -Z узла.
	var up: Vector3 = Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(forward, up), origin)
	if is_finite(floor_height):
		_floor.global_transform = Transform3D(Basis.IDENTITY, Vector3(origin.x, floor_height - FLOOR_HALF_THICKNESS, origin.z))
	else:
		_floor.queue_free()
	_sparks.restart()
	_bits.restart()
	_vapor.restart()
	var tween: Tween = create_tween()
	tween.tween_property(_flash, ^"light_energy", 0.0, FLASH_SEC)
	tween.tween_callback(_flash.hide)
	tween.tween_interval(LIFETIME_SEC - FLASH_SEC)
	tween.tween_callback(queue_free)
