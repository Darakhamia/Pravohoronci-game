class_name PlayerWeapons
extends Node
## Оружие и предметы в руках игрока (узел Weapons внутри Player). Решает сервер.
## Всем видно только то, что игрок держит (Player.held_item — номер в наборе ITEMS).
## Что ещё у него есть и сколько патронов, знают сервер и хозяин аватара: сервер шлёт ему
## личное сообщение Player.Private.LOADOUT (раскладка массива — в WeaponLoadout).
##
## Атака. Клиент присылает нажатие и углы взгляда (World -> server_fire), сервер кладёт
## запрос в очередь и разбирает его в физическом тике: игрок жив, идёт игра, в руках
## оружие, а не груз, прошла пауза оружия и есть патроны. Луч идёт из глаз атакующего
## со случайным разбросом и пересекается с хитбоксами живых игроков (PlayerBody.HITBOXES,
## формулой, без физики); ближайшее попадание получает урон, если по пути нет стены
## (один физический луч по слою world). Компенсации задержки нет: сервер считает по
## положению игроков на своём текущем тике — мы играем своей компанией на сервере
## с низким пингом. О каждой состоявшейся атаке (попал или нет) узнают все игроки:
## событие Player.Event.ATTACK, раскладка массива — в AttackEvent.

## Клиент-владелец: изменились набор оружия, патроны, оружие в руках или возможность
## его сменить — HUD перечитывает всё разом.
signal loadout_changed
## Сервер: игрок лишился груза, который нёс (бросил, сменил оружие, умер).
signal carried_lost(item: ItemConfig)

const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
## Номер пустых рук (кулаков) в наборе: они есть у каждого.
const EMPTY_HANDS: int = 0
## Сервер: больше запросов одного вида за тик от клиента не принимаем.
const MAX_QUEUED_REQUESTS: int = 4
## Слой world: стены и предметы карты останавливают пули и удары, игроки — нет.
const WORLD_MASK: int = 1
## Погрешность при переводе паузы оружия в тики: 0.35 с на 60 тиках — ровно 21 тик.
const TICK_EPSILON: float = 0.001

## Сервер: груз в руках (канистра); null — груза нет.
var _carried: ItemConfig = null
## Сервер: что игрок держал до того, как взял груз.
var _held_before_carry: int = EMPTY_HANDS
## Сервер и клиент-владелец: какое оружие есть и сколько патронов.
var _loadout: WeaponLoadout = WeaponLoadout.new(ITEMS)
## Сервер: нажатия атаки, ждут ближайшего физического тика: x — yaw, y — pitch.
var _fire_requests: Array[Vector2] = []
## Сервер: нажатия смены оружия, ждут ближайшего физического тика.
var _switch_requests: int = 0
## Сервер: физический тик, с которого снова можно атаковать.
var _next_attack_tick: int = 0
## Сервер: случайные числа для разброса.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	set_physics_process(Net.is_server())
	if Net.is_server():
		_rng.randomize()
		_player.life_changed.connect(_on_life_changed)
		_player.limbs_changed.connect(_on_limbs_changed)
	elif _player.is_local():
		# HUD хозяина слушает один сигнал: то, что видно всем, тоже меняет его картину.
		_player.held_item_changed.connect(loadout_changed.emit.unbind(1))
		_player.limbs_changed.connect(loadout_changed.emit.unbind(1))


## Сервер: разобрать запросы клиента, пришедшие с прошлого тика.
func _physics_process(_delta: float) -> void:
	for _press: int in _switch_requests:
		_server_switch_once()
	_switch_requests = 0
	for request: Vector2 in _fire_requests:
		_server_attack(request.x, request.y)
	_fire_requests.clear()


## Все пиры: предмет, который игрок держит в руках.
func get_held_item() -> ItemConfig:
	return ITEMS.get_item(_player.held_item)


## Все пиры: оружие в руках; null — игрок несёт груз.
func get_held_weapon() -> WeaponConfig:
	return get_held_item() as WeaponConfig


## Все пиры: несёт ли игрок этот груз.
func is_carrying(item: ItemConfig) -> bool:
	return item != null and get_held_item() == item


## Сервер и клиент-владелец: патроны оружия в руках; -1 — у него нет счётчика.
## У чужих игроков всегда -1: их патроны клиенту неизвестны.
func get_ammo() -> int:
	return _loadout.get_ammo(_player.held_item)


## Сервер и клиент-владелец: патроны этого оружия; -1 — счётчика нет или оружия нет.
func get_weapon_ammo(weapon: WeaponConfig) -> int:
	return _loadout.get_ammo(ITEMS.index_of(weapon))


## Сервер и клиент-владелец: есть ли у игрока это оружие.
func owns(weapon: WeaponConfig) -> bool:
	return weapon != null and _loadout.owns(ITEMS.index_of(weapon))


## Сервер и клиент-владелец: всё оружие игрока по порядку набора ITEMS (первые — кулаки).
func get_owned_weapons() -> Array[WeaponConfig]:
	return _loadout.get_owned_weapons()


## Сервер и клиент-владелец: сделает ли что-нибудь клавиша смены оружия — есть другое
## оружие, которое игрок сейчас может держать, или в руках груз (его можно бросить).
func can_switch() -> bool:
	if get_held_weapon() == null:
		return true
	return _loadout.next_index(_player.held_item, _player.limbs_lost) != _player.held_item


## Сервер: начало раунда — кулаки всем, нож предателю.
func server_reset(role: Game.Role) -> void:
	if not Net.is_server():
		return
	_carried = null
	_held_before_carry = EMPTY_HANDS
	_fire_requests.clear()
	_switch_requests = 0
	_next_attack_tick = 0
	_loadout.reset(role)
	_player.held_item = EMPTY_HANDS
	_send_loadout()


## Сервер: клиент нажал атаку; углы взгляда уже очищены. Сама атака — в физическом тике.
## Пока игрок несёт груз, атаковать нельзя.
func server_fire(yaw: float, pitch: float) -> void:
	if Net.is_server() and _fire_requests.size() < MAX_QUEUED_REQUESTS:
		_fire_requests.append(Vector2(yaw, pitch))


## Сервер: клиент нажал смену оружия. Если игрок нёс груз — он его бросает, иначе берёт
## следующее своё оружие по порядку набора. Сама смена — в физическом тике.
func server_switch() -> void:
	if Net.is_server() and _switch_requests < MAX_QUEUED_REQUESTS:
		_switch_requests += 1


## Сервер: выдать оружие с патронами (подобрал со стойки). Нового оружия ещё не было —
## игрок берёт его в руки, уже было — получает патроны. false — не взял: мёртв, нет обеих
## рук (двуручному нужны обе), оружие предателя — не предателю, предмет не оружие или
## брать незачем (такое оружие без патронов у игрока уже есть).
func server_give(weapon: WeaponConfig, ammo: int) -> bool:
	if not Net.is_server() or _player.life != Player.Life.ALIVE:
		return false
	var index: int = ITEMS.index_of(weapon)
	if index <= EMPTY_HANDS:
		return false
	if not WeaponLoadout.can_take(weapon, Game.get_role(_player.peer_id), _player.limbs_lost):
		return false
	var is_new: bool = not _loadout.owns(index)
	if not _loadout.give(index, ammo):
		return false
	if is_new and _carried != null:
		# Руки заняты грузом: оружие окажется в руках, когда игрок с ним расстанется.
		_held_before_carry = index
	elif is_new:
		_player.held_item = index
	_send_loadout()
	return true


## Сервер: взять груз в руки. Пока игрок его несёт, атаковать нельзя. false — не взял
## (мёртв, уже что-то несёт или предмета нет в наборе ITEMS).
func server_carry(item: ItemConfig) -> bool:
	if not Net.is_server() or _player.life != Player.Life.ALIVE or _carried != null:
		return false
	var index: int = ITEMS.index_of(item)
	if index <= EMPTY_HANDS:
		return false
	_carried = item
	_held_before_carry = _player.held_item
	_player.held_item = index
	return true


## Сервер: забрать груз из рук (игрок его доставил) — без сигнала carried_lost.
func server_take_carried() -> void:
	if not Net.is_server() or _carried == null:
		return
	_carried = null
	_player.held_item = _held_before_carry


## Клиент-владелец: личные данные об оружии пришли с сервера. Вызывает Player.
## Негодные данные (не тот размер, типы, чужие номера) отбрасываются целиком.
func apply_loadout(data: Array) -> void:
	if _loadout.apply_data(data):
		loadout_changed.emit()


## Сервер: игрок бросил груз или потерял его.
func _drop_carried() -> void:
	var item: ItemConfig = _carried
	server_take_carried()
	carried_lost.emit(item)


## Сервер: одно нажатие смены оружия.
func _server_switch_once() -> void:
	if _carried != null:
		_drop_carried()
		return
	if _can_act():
		_player.held_item = _loadout.next_index(_player.held_item, _player.limbs_lost)


## Сервер: одно нажатие атаки. Запрос, который сейчас выполнить нельзя, пропадает.
func _server_attack(yaw: float, pitch: float) -> void:
	var weapon: WeaponConfig = get_held_weapon()
	if weapon == null or _carried != null or _player.map == null or not _can_act():
		return
	var tick: int = Engine.get_physics_frames()
	var index: int = _player.held_item
	if tick < _next_attack_tick or not _loadout.spend_ammo(index):
		return
	_next_attack_tick = tick + ceili(weapon.attack_interval * Engine.physics_ticks_per_second - TICK_EPSILON)
	if weapon.uses_ammo:
		_send_loadout()
	var origin: Vector3 = _player.get_eye_position()
	var spread: float = Aim.spread_radians(weapon.spread_degrees, _player.limbs_lost,
			PlayerBody.CONFIG.one_arm_spread_factor)
	var direction: Vector3 = Aim.spread_direction(yaw, pitch, spread, _rng)
	var victim: Player = null
	var best: BodyHit = null
	for candidate: Player in _player.map.get_players():
		if candidate == _player or candidate.life != Player.Life.ALIVE:
			continue
		var hit: BodyHit = candidate.body.intersect_ray(origin, direction, weapon.attack_range, weapon.hit_radius)
		if hit != null and (best == null or hit.distance < best.distance):
			best = hit
			victim = candidate
	var end: Vector3 = origin + direction * (best.distance if best != null else weapon.attack_range)
	var impact: AttackEvent.Impact = AttackEvent.Impact.PLAYER if best != null else AttackEvent.Impact.NONE
	# Один физический луч: стена ближе цели закрывает и её, и всех, кто дальше.
	# Игроки проходят друг сквозь друга: цель вплотную (нулевой отрезок) стеной не закрыта.
	if not origin.is_equal_approx(end):
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end, WORLD_MASK)
		var wall: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(query)
		if not wall.is_empty():
			end = wall["position"]
			impact = AttackEvent.Impact.WORLD
			victim = null
	# Сначала событие, потом урон: клиенты увидят выстрел раньше, чем его последствия.
	_player.send_event(Player.Event.ATTACK, AttackEvent.encode(index, origin, end, impact))
	if victim != null:
		victim.body.server_apply_damage(best.part, weapon.damage, _player.peer_id)


## Сервер: может ли игрок сейчас атаковать и менять оружие.
func _can_act() -> bool:
	return _player.life == Player.Life.ALIVE and Game.is_playing()


## Сервер: отправить хозяину его оружие и патроны.
func _send_loadout() -> void:
	_player.send_private(Player.Private.LOADOUT, _loadout.to_data())


func _on_life_changed(new_life: Player.Life) -> void:
	if new_life == Player.Life.ALIVE:
		return
	_fire_requests.clear()
	_switch_requests = 0
	if _carried != null:
		_drop_carried()


## Сервер: игрок потерял конечность. Без обеих рук груз падает, а в руках остаются только
## «кулаки»; оружие, которое больше не удержать (двуручное без руки), тоже убирается.
func _on_limbs_changed(mask: int) -> void:
	if _carried != null and BodyPart.lost_arms(mask) >= BodyPart.ARM_COUNT:
		_drop_carried()
	if _carried != null:
		if not _loadout.can_hold(_held_before_carry, mask):
			_held_before_carry = EMPTY_HANDS
	elif not _loadout.can_hold(_player.held_item, mask):
		_player.held_item = EMPTY_HANDS
