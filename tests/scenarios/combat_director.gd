extends Node
## Серверный помощник сценариев боя: сам в игру не вмешивается, только следит за сервером
## и пишет в лог каждую атаку и каждый урон. Нарушение правила — строка ERROR в логе
## сервера, по ней сценарий считается проваленным:
## - атаковать может только живой игрок и только пока идёт игра;
## - между атаками одного игрока проходит не меньше паузы его оружия (в тиках сервера);
## - урон получает только живой игрок, от живого атакующего, не дальше дальности оружия.

const WORLD_PATH: NodePath = ^"Main/World"
const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
## Запас к дальности: толщина удара и размер тела цели.
const RANGE_MARGIN: float = 1.0
const TICK_EPSILON: float = 0.001

var _world: World = null
## Тик, раньше которого игрок не может атаковать снова: peer_id -> тик.
var _next_attack_tick: Dictionary[int, int] = {}


func _process(_delta: float) -> void:
	if _world != null:
		return
	_world = get_tree().root.get_node_or_null(WORLD_PATH) as World
	if _world != null:
		_world.map_changed.connect(_on_map_changed)


func _on_map_changed(map: GameMap) -> void:
	_next_attack_tick.clear()
	if map != null:
		map.player_added.connect(_on_player_added)


func _on_player_added(player: Player) -> void:
	player.event_sent.connect(_on_event_sent.bind(player))
	player.body.damaged.connect(_on_damaged.bind(player))


func _on_event_sent(kind: Player.Event, data: Array, player: Player) -> void:
	if kind != Player.Event.ATTACK:
		return
	var attack: AttackEvent = AttackEvent.decode(data, ITEMS)
	if attack == null:
		push_error("[director] сервер разослал негодное событие атаки: %s" % var_to_str(data))
		return
	var tick: int = Engine.get_physics_frames()
	print("[director] attack by=%s item=%d impact=%s tick=%d" % [
			player.display_name, attack.item_index, AttackEvent.Impact.find_key(attack.impact), tick])
	if player.life != Player.Life.ALIVE or not Game.is_playing():
		push_error("[director] %s атаковал, хотя не мог: life=%s playing=%s" % [
				player.display_name, Player.Life.find_key(player.life), Game.is_playing()])
	if tick < _next_attack_tick.get(player.peer_id, 0):
		push_error("[director] %s атаковал на %d тиков раньше паузы оружия" % [
				player.display_name, _next_attack_tick[player.peer_id] - tick])
	_next_attack_tick[player.peer_id] = tick + ceili(
			attack.weapon.attack_interval * Engine.physics_ticks_per_second - TICK_EPSILON)


func _on_damaged(part: BodyPart.Part, amount: int, attacker_id: int, victim: Player) -> void:
	var attacker: Player = _world.current_map.get_player(attacker_id) if _world.current_map != null else null
	print("[director] damage victim=%s part=%s amount=%d attacker=%s" % [
			victim.display_name, BodyPart.Part.find_key(part), amount,
			attacker.display_name if attacker != null else "-"])
	if attacker == null:
		return
	var weapon: WeaponConfig = attacker.weapons.get_held_weapon()
	if weapon == null or attacker.life != Player.Life.ALIVE:
		push_error("[director] урон от игрока %s, который не мог атаковать" % attacker.display_name)
		return
	if amount != weapon.damage:
		push_error("[director] урон %d не равен урону оружия «%s»" % [amount, weapon.title])
	var distance: float = attacker.get_eye_position().distance_to(victim.global_position + Vector3.UP)
	if distance > weapon.attack_range + RANGE_MARGIN:
		push_error("[director] урон оружием «%s» с %.1f м" % [weapon.title, distance])
