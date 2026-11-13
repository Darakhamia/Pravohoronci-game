class_name AttackEffects
extends Node3D
## Клиент: эффекты атак одного аватара (узел AttackEffects внутри Player). Слушает события
## Player.event_received и на каждую атаку этого игрока показывает взмах или отдачу
## (PlayerVisuals.play_attack()), след пули у стрелкового оружия и вспышку там, где атака
## во что-то упёрлась. Данные события пришли по сети — их проверяет AttackEvent.decode().
## На сервере узел ничего не делает; без окна (боты тестов) следов и вспышек нет.

const TRACER_SCENE: PackedScene = preload("res://scenes/effects/tracer.tscn")
const FLASH_SCENE: PackedScene = preload("res://scenes/effects/impact_flash.tscn")
## Имя «дисплея» у процесса без окна.
const HEADLESS_DISPLAY: String = "headless"
## След начинается не из глаз, а примерно от оружия в правой руке: вправо, вниз и вперёд
## от точки выстрела (в осях взгляда), м.
const MUZZLE_OFFSET: Vector3 = Vector3(0.18, -0.16, -0.5)
## Вспышку ставим чуть ближе точки попадания, чтобы её не съела стена.
const FLASH_PULLBACK: float = 0.05
const PLAYER_HIT_COLOR: Color = Color(1.0, 0.92, 0.3)
const WORLD_HIT_COLOR: Color = Color(1.0, 0.6, 0.2)

## Внешний вид того же аватара (соседний узел Visuals).
@export var visuals_path: NodePath = ^"../Visuals"

var _visuals: PlayerVisuals = null
var _shows_effects: bool = false


func _ready() -> void:
	var player: Player = get_parent() as Player
	if player == null or Net.is_server():
		return
	_visuals = get_node_or_null(visuals_path) as PlayerVisuals
	_shows_effects = DisplayServer.get_name() != HEADLESS_DISPLAY
	player.event_received.connect(_on_event_received)


## Точка, из которой рисуется след: около оружия, а не из глаз стрелка.
static func get_muzzle_position(from: Vector3, to: Vector3) -> Vector3:
	var offset: Vector3 = to - from
	# В упор сдвигать некуда: след начался бы за целью.
	if offset.length() <= -MUZZLE_OFFSET.z:
		return from
	var forward: Vector3 = offset.normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.is_zero_approx():
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(forward)
	return from + right * MUZZLE_OFFSET.x + up * MUZZLE_OFFSET.y - forward * MUZZLE_OFFSET.z


func _on_event_received(kind: Player.Event, data: Array) -> void:
	if kind != Player.Event.ATTACK:
		return
	var attack: AttackEvent = AttackEvent.decode(data, PlayerWeapons.ITEMS)
	if attack == null:
		return
	if _visuals != null:
		_visuals.play_attack()
	if not _shows_effects:
		return
	if attack.weapon.kind == WeaponConfig.Kind.HITSCAN:
		var tracer: Tracer = TRACER_SCENE.instantiate() as Tracer
		add_child(tracer)
		tracer.play(get_muzzle_position(attack.from, attack.to), attack.to)
	if attack.impact != AttackEvent.Impact.NONE:
		var flash: ImpactFlash = FLASH_SCENE.instantiate() as ImpactFlash
		add_child(flash)
		var back: Vector3 = (attack.from - attack.to).limit_length(FLASH_PULLBACK)
		var color: Color = PLAYER_HIT_COLOR if attack.impact == AttackEvent.Impact.PLAYER else WORLD_HIT_COLOR
		flash.play(attack.to + back, color)
