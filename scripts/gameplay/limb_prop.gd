class_name LimbProp
extends RigidBody3D
## Отлетевшая конечность: игрушечная деталь, которая кувыркается по полу и вскоре исчезает.
## Чисто визуальная: создаётся только на клиентах, сталкивается только с миром (слой world).

## Через сколько секунд деталь начинает исчезать.
const LIFETIME_SEC: float = 10.0
const SHRINK_SEC: float = 0.35
## Коробка столкновений чуть меньше габаритов меша: круглая деталь не висит над полом на углах.
const SHAPE_FILL: float = 0.86
const MIN_SHAPE_SIZE: float = 0.04
## До нуля не сжимаем: вырожденный масштаб даёт ошибки в движке.
const VANISH_SCALE: float = 0.01

@onready var _mesh_instance: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $CollisionShape3D


## Запускает деталь. Вызывать после добавления в дерево.
## mesh задан в осях модели (поза покоя); origin — где сейчас находится начало координат модели
## для этой конечности; suit — материал костюма игрока.
func launch(mesh: Mesh, suit: Material, origin: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	var bounds: AABB = mesh.get_aabb()
	var center: Vector3 = bounds.get_center()
	_mesh_instance.mesh = mesh
	_mesh_instance.position = -center
	PlayerVisuals.apply_suit_material(_mesh_instance, suit)
	var box: BoxShape3D = _collision.shape as BoxShape3D
	box.size = (bounds.size * SHAPE_FILL).max(Vector3.ONE * MIN_SHAPE_SIZE)
	global_transform = (origin * Transform3D(Basis.IDENTITY, center)).orthonormalized()
	linear_velocity = velocity
	angular_velocity = spin
	var tween: Tween = create_tween()
	tween.tween_interval(LIFETIME_SEC)
	tween.tween_property(_mesh_instance, ^"scale", Vector3.ONE * VANISH_SCALE, SHRINK_SEC)
	tween.tween_callback(queue_free)
