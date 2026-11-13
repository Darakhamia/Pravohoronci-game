class_name TaskMarker
extends MeshInstance3D
## Светящаяся метка над предметом карты: «это твоё задание». Показывает и прячет её
## хозяин (станция, стеллаж, пульт) свойством visible — и только на клиенте того игрока,
## которому она нужна. Сама метка лишь крутится и покачивается, пока видна.
## На сервере и в запуске без окна стоит неподвижно.

## Размеры ромба, м.
const RADIUS: float = 0.11
const HEIGHT: float = 0.34
## Четыре грани и одно кольцо — из сферы получается ромб.
const RADIAL_SEGMENTS: int = 4
const RINGS: int = 1
## Скорость вращения, рад/с.
const SPIN_SPEED: float = 2.4
## Размах (м) и частота (рад/с) покачивания вверх-вниз.
const BOB_HEIGHT: float = 0.06
const BOB_SPEED: float = 3.0
## Яркость свечения.
const GLOW_ENERGY: float = 2.0

## Цвет метки.
@export var color: Color = Color(1.0, 0.85, 0.2)

var _base_y: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_base_y = position.y
	var diamond: SphereMesh = SphereMesh.new()
	diamond.radius = RADIUS
	diamond.height = HEIGHT
	diamond.radial_segments = RADIAL_SEGMENTS
	diamond.rings = RINGS
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = GLOW_ENERGY
	diamond.material = material
	mesh = diamond
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var is_animated: bool = not Net.is_server() and DisplayServer.get_name() != "headless"
	set_process(is_animated and visible)
	if is_animated:
		visibility_changed.connect(_on_visibility_changed)


func _process(delta: float) -> void:
	_time += delta
	rotate_y(SPIN_SPEED * delta)
	position.y = _base_y + sin(_time * BOB_SPEED) * BOB_HEIGHT


func _on_visibility_changed() -> void:
	set_process(visible)
