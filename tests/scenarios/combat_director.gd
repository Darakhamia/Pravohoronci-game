extends Node
## Серверный помощник сценариев боя: сам в игру не вмешивается, только следит за сервером
## и пишет в лог каждую атаку и каждый урон. Нарушение правила — строка ERROR в логе
## сервера, по ней сценарий считается проваленным:
## - атаковать может только живой игрок и только пока идёт игра;
## - между атаками одного игрока проходит не меньше паузы его оружия (в тиках сервера);
## - урон получает только живой игрок, от живого атакующего, не дальше дальности оружия;
## - оружием атакуют не раньше, чем его достали (WeaponConfig.draw_seconds в руках);
## - оружие, которым только что атаковали, не убирают из рук раньше его паузы (кроме
##   смерти, собрания и потери рук);
## - после начала игры и после собрания никто не атакует GameConfig.attack_lock_seconds.
## Заодно пишет в лог каждую смену предмета в руках.

const WORLD_PATH: NodePath = ^"Main/World"
const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
## Запас к дальности: толщина удара и размер тела цели.
const RANGE_MARGIN: float = 1.0
const TICK_EPSILON: float = 0.001

var _world: World = null
## Тик, раньше которого игрок не может атаковать снова: peer_id -> тик.
var _next_attack_tick: Dictionary[int, int] = {}
## Тик, на котором игрок взял в руки то, что держит сейчас: peer_id -> тик.
var _held_since_tick: Dictionary[int, int] = {}
## Что игрок держал до последней смены: peer_id -> номер предмета.
var _held_item: Dictionary[int, int] = {}
## Тик, на котором игра началась или продолжилась после собрания.
var _playing_since_tick: int = 0


func _ready() -> void:
	Game.phase_changed.connect(_on_phase_changed)


func _process(_delta: float) -> void:
	if _world != null:
		return
	_world = get_tree().root.get_node_or_null(WORLD_PATH) as World
	if _world != null:
		_world.map_changed.connect(_on_map_changed)


func _on_phase_changed(new_phase: Game.Phase) -> void:
	if new_phase == Game.Phase.PLAYING:
		_playing_since_tick = Engine.get_physics_frames()
		print("[director] playing tick=%d" % _playing_since_tick)


func _on_map_changed(map: GameMap) -> void:
	_next_attack_tick.clear()
	_held_since_tick.clear()
	_held_item.clear()
	if map != null:
		map.player_added.connect(_on_player_added)


func _on_player_added(player: Player) -> void:
	player.event_sent.connect(_on_event_sent.bind(player))
	player.body.damaged.connect(_on_damaged.bind(player))
	player.held_item_changed.connect(_on_held_item_changed.bind(player))
	_held_item[player.peer_id] = player.held_item


func _on_held_item_changed(item_id: int, player: Player) -> void:
	var tick: int = Engine.get_physics_frames()
	var previous: WeaponConfig = ITEMS.get_item(_held_item.get(player.peer_id, 0)) as WeaponConfig
	print("[director] held by=%s item=%d tick=%d" % [player.display_name, item_id, tick])
	# Силой оружие уходит из рук сразу: смерть, собрание, нечем держать.
	var is_forced: bool = (player.life != Player.Life.ALIVE or not Game.is_playing()
			or BodyPart.lost_arms(player.limbs_lost) >= BodyPart.ARM_COUNT)
	if previous != null and not is_forced and tick < _next_attack_tick.get(player.peer_id, 0):
		push_error("[director] %s убрал «%s» на %d тиков раньше паузы после атаки" % [
				player.display_name, previous.title, _next_attack_tick[player.peer_id] - tick])
	_held_item[player.peer_id] = item_id
	_held_since_tick[player.peer_id] = tick


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
	if attack.item_index != player.held_item:
		push_error("[director] %s атаковал предметом %d, а в руках %d" % [
				player.display_name, attack.item_index, player.held_item])
	var draw_ticks: int = ceili(attack.weapon.draw_seconds * Engine.physics_ticks_per_second - TICK_EPSILON)
	if _held_since_tick.has(player.peer_id) and tick - _held_since_tick[player.peer_id] < draw_ticks:
		push_error("[director] %s ударил «%s» через %d тиков после того, как достал (нужно %d)" % [
				player.display_name, attack.weapon.title, tick - _held_since_tick[player.peer_id], draw_ticks])
	var lock_ticks: int = ceili(Game.config.attack_lock_seconds * Engine.physics_ticks_per_second - TICK_EPSILON)
	if tick - _playing_since_tick < lock_ticks:
		push_error("[director] %s атаковал через %d тиков после начала игры (запрет %d)" % [
				player.display_name, tick - _playing_since_tick, lock_ticks])
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
