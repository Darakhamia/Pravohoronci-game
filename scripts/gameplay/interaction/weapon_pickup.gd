class_name WeaponPickup
extends Interactable
## Стойка с оружием (scenes/items/weapon_pickup.tscn). Игрок рядом жмёт E и забирает оружие
## с патронами: если такого у него ещё не было — берёт в руки, если было — получает патроны.
## Стойка одноразовая: state 0 — оружие лежит, 1 — забрали (модель исчезает у всех).
## Отдаёт оружие сервер через PlayerWeapons.server_give(): там же правила, кому нельзя.

## state: оружие лежит на стойке.
const STATE_AVAILABLE: int = 0
## state: оружие забрали.
const STATE_TAKEN: int = 1
## Подсказка: «Взять пистолет».
const PROMPT_TAKE: String = "Взять %s"
## Подсказка тому, у кого такое оружие уже есть.
const PROMPT_AMMO: String = "Взять патроны"
## Зазор между оружием и стойкой, м: чтобы грани не мерцали.
const REST_GAP: float = 0.005

## Оружие на стойке (ресурс из resources/items).
@export var weapon: WeaponConfig = null
## Сколько патронов игрок получает вместе с оружием.
@export_range(0, 999) var ammo: int = 0

@onready var _weapon_slot: Node3D = $WeaponSlot


func _ready() -> void:
	# Серверу без окна модель не нужна: он знает только state.
	if weapon == null or weapon.model == null or Net.is_server():
		return
	var model: Node3D = weapon.model.instantiate() as Node3D
	if model == null:
		return
	# WeaponSlot стоит на верхней грани стойки и кладёт модель на бок. Поднимаем его так,
	# чтобы оружие любой толщины лежало на стойке, а не тонуло в ней.
	var stand_top: float = _weapon_slot.position.y
	_weapon_slot.add_child(model)
	var lowest: float = _get_lowest_point(model)
	if is_finite(lowest):
		_weapon_slot.position.y += stand_top + REST_GAP - lowest


## Все пиры: лежит ли оружие на стойке.
func is_available() -> bool:
	return state == STATE_AVAILABLE


## Клиент-владелец: «Взять пистолет», а тому, у кого он уже есть, — «Взять патроны».
## Текст, заданный на карте в поле prompt, важнее.
func get_prompt(player: Player) -> String:
	if not prompt.is_empty():
		return prompt
	if weapon == null:
		return ""
	# Своё оружие знает только клиент-владелец: подсказку он строит про себя.
	if weapon.uses_ammo and player.weapons.owns(weapon):
		return PROMPT_AMMO
	return PROMPT_TAKE % weapon.title.to_lower()


## Опирается на то, что знают и сервер, и клиент про своего игрока: состояние стойки,
## потерянные руки и роль (чужих ролей клиент не знает, но спрашивает только про себя).
func can_interact(player: Player) -> bool:
	return (is_available() and player.life == Player.Life.ALIVE
			and WeaponLoadout.can_take(weapon, Game.get_role(player.peer_id), player.limbs_lost))


## Сервер: игрок нажал E у стойки. Оружие уходит, только если игрок его действительно взял.
func server_interact(player: Player) -> void:
	if is_available() and player.weapons.server_give(weapon, ammo):
		server_set_state(STATE_TAKEN)


func _on_state_changed() -> void:
	_weapon_slot.visible = is_available()


## Нижняя точка модели в координатах стойки (по габаритам её сеток); INF — сеток нет.
func _get_lowest_point(node: Node) -> float:
	var lowest: float = INF
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var to_stand: Transform3D = global_transform.affine_inverse() * mesh_instance.global_transform
		var bounds: AABB = mesh_instance.mesh.get_aabb()
		for corner: int in 8:
			lowest = minf(lowest, (to_stand * bounds.get_endpoint(corner)).y)
	for child: Node in node.get_children():
		lowest = minf(lowest, _get_lowest_point(child))
	return lowest
