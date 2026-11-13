class_name PlayerWeapons
extends Node
## Оружие и предметы в руках игрока (узел Weapons внутри Player). Решает сервер.
## Что игрок держит (Player.held_item — номер в наборе ITEMS), узнают только те, кто его
## замечает: сам хозяин, игроки рядом или на прямой видимости, призраки и зрители. Сервер
## рассказывает им об этом через World (правило — в Perception); остальные помнят то, что
## видели в последний раз. Что ещё у игрока есть и сколько патронов, знают сервер и хозяин
## аватара: личное сообщение Player.Private.LOADOUT (раскладка массива — в WeaponLoadout).
##
## Запросы клиента — атака, клавиша Q, цифровые клавиши (World -> server_fire / server_switch /
## server_select) — встают в ОДНУ очередь и разбираются в физическом тике в том порядке,
## в каком пришли. Запрос, который сейчас выполнить нельзя, пропадает.
##
## Смена оружия. Цифра достаёт оружие напрямую (1 — кулаки, 2 — пистолет, 3 — нож), Q идёт
## по кругу своего оружия без оружия предателя (с ножа — на кулаки). Оружие достают:
## WeaponConfig.draw_seconds после того, как оно оказалось в руках, им нельзя атаковать.
## После атаки оружие нельзя убрать, пока не пройдёт его пауза attack_interval. Поэтому нож
## виден в руке до удара и после него. Принудительно руки пустеют сразу: при смерти, на
## собрании, когда оружие больше нечем держать.
##
## Атака. Клиент присылает нажатие и углы взгляда, сервер проверяет: игрок жив, идёт игра,
## в руках оружие, а не груз, оружие достали, прошла его пауза, нет общего запрета атак
## (GameConfig.attack_lock_seconds после начала игры и после каждого собрания) и есть
## патроны. Луч идёт из глаз атакующего со случайным разбросом и пересекается с хитбоксами
## живых игроков (PlayerBody.HITBOXES, формулой, без физики): сначала точный луч по всем,
## и только если он ни в кого не попал — по коробкам, раздутым на толщину удара. Ближайшее
## попадание получает урон, если по пути нет стены (один физический луч по слою world).
## Компенсации задержки нет: сервер считает по положению игроков на своём текущем тике —
## мы играем своей компанией на сервере с низким пингом. О каждой состоявшейся атаке (попал
## или нет) узнают те, кто замечает атакующего или место, где она закончилась: событие
## Player.Event.ATTACK, раскладка массива — в AttackEvent.

## Клиент-владелец: изменились набор оружия, патроны, оружие в руках или возможность
## его сменить — HUD перечитывает всё разом.
signal loadout_changed
## Клиент-владелец: общий запрет атак начался или кончился (см. get_attack_lock_left()).
signal attack_lock_changed
## Сервер: игрок лишился груза, который нёс (бросил, сменил оружие, умер, началось собрание).
signal carried_lost(item: ItemConfig)

## Виды запросов клиента в очереди.
enum Request { FIRE, SWITCH, SELECT }

const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
## Номер пустых рук (кулаков) в наборе: они есть у каждого.
const EMPTY_HANDS: int = 0
## Сервер: больше запросов (всех видов вместе) за тик от клиента не принимаем.
const MAX_QUEUED_REQUESTS: int = 8
## Слой world: стены и предметы карты останавливают пули и удары, игроки — нет.
const WORLD_MASK: int = 1
## Клиент-владелец: дольше этого общий запрет атак не бывает (проверка личного сообщения), с.
const MAX_ATTACK_LOCK_SEC: float = 600.0

## Сервер: груз в руках (канистра); null — груза нет.
var _carried: ItemConfig = null
## Сервер: что игрок держал до того, как взял груз.
var _held_before_carry: int = EMPTY_HANDS
## Сервер и клиент-владелец: какое оружие есть и сколько патронов.
var _loadout: WeaponLoadout = WeaponLoadout.new(ITEMS)
## Сервер: запросы клиента по порядку прихода, ждут ближайшего физического тика.
## Запись — [Request.FIRE, yaw, pitch], [Request.SWITCH] или [Request.SELECT, slot].
var _requests: Array[Array] = []
## Сервер: когда оружием можно атаковать и когда его можно убрать (в физических тиках).
var _timing: WeaponTiming = WeaponTiming.new()
## Клиент-владелец: сколько секунд ещё действует общий запрет атак.
var _attack_lock_left: float = 0.0
## Сервер: случайные числа для разброса.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	set_physics_process(Net.is_server())
	set_process(false)
	if Net.is_server():
		_rng.randomize()
		_player.life_changed.connect(_on_life_changed)
		_player.limbs_changed.connect(_on_limbs_changed)
		Game.phase_changed.connect(_on_phase_changed)
	elif _player.is_local():
		# HUD хозяина слушает один сигнал: то, что видно всем, тоже меняет его картину.
		_player.held_item_changed.connect(loadout_changed.emit.unbind(1))
		_player.limbs_changed.connect(loadout_changed.emit.unbind(1))


## Клиент-владелец: общий запрет атак дотикивает у себя, без сообщений сервера.
func _process(delta: float) -> void:
	_attack_lock_left = maxf(_attack_lock_left - delta, 0.0)
	if _attack_lock_left <= 0.0:
		set_process(false)
		attack_lock_changed.emit()


## Сервер: разобрать запросы клиента, пришедшие с прошлого тика, в порядке прихода.
func _physics_process(_delta: float) -> void:
	if _requests.is_empty():
		return
	var requests: Array[Array] = _requests
	_requests = []
	for request: Array in requests:
		match request[0] as Request:
			Request.FIRE:
				_server_attack(request[1] as float, request[2] as float)
			Request.SWITCH:
				_server_switch_once()
			Request.SELECT:
				_server_select_once(request[1] as int)


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


## Сервер и клиент-владелец: сделает ли что-нибудь клавиша Q — в её круге есть другое
## оружие, которое игрок сейчас может держать, в руках оружие предателя (Q его уберёт)
## или груз (его можно бросить). Нож в круг Q не входит: его достают цифрой.
func can_switch() -> bool:
	if get_held_weapon() == null:
		return true
	return _loadout.next_index(_player.held_item, _player.limbs_lost) != _player.held_item


## Сервер и клиент-владелец: сколько секунд ещё действует общий запрет атак (начало игры,
## конец собрания); 0 — атаковать можно. Клиенту-владельцу длину запрета присылает сервер
## (Player.Private.ATTACK_LOCK), дальше он считает сам. У чужих игроков всегда 0.
func get_attack_lock_left() -> float:
	if Net.is_server():
		return float(_timing.get_lock_ticks_left(Engine.get_physics_frames())) / Engine.physics_ticks_per_second
	return _attack_lock_left


## Сервер: начало раунда — кулаки всем, нож предателю.
func server_reset(role: Game.Role) -> void:
	if not Net.is_server():
		return
	_carried = null
	_held_before_carry = EMPTY_HANDS
	_requests.clear()
	_timing.reset()
	_loadout.reset(role)
	_player.held_item = EMPTY_HANDS
	_send_loadout()


## Сервер: клиент нажал атаку; углы взгляда уже очищены. Сама атака — в физическом тике.
## Пока игрок несёт груз, не достал оружие или действует запрет атак, запрос пропадает.
func server_fire(yaw: float, pitch: float) -> void:
	_queue_request([Request.FIRE, yaw, pitch])


## Сервер: клиент нажал Q. Если игрок нёс груз — он его бросает, иначе берёт следующее
## своё оружие по кругу Q (без оружия предателя). Сама смена — в физическом тике.
func server_switch() -> void:
	_queue_request([Request.SWITCH])


## Сервер: клиент нажал цифровую клавишу slot (с единицы): взять в руки оружие номер
## slot - 1 из набора ITEMS, если оно у игрока есть и он может его держать. Груз при этом
## падает. Сама смена — в физическом тике.
func server_select(slot: int) -> void:
	if slot >= 1 and slot <= ITEMS.items.size():
		_queue_request([Request.SELECT, slot])


## Сервер: выдать оружие с патронами (подобрал со стойки). Нового оружия ещё не было —
## игрок берёт его в руки (если руки заняты грузом или прежнее оружие ещё нельзя убрать
## после атаки, новое просто появляется у игрока), уже было — получает патроны.
## false — не взял: мёртв, нет обеих рук (двуручному нужны обе), оружие предателя —
## не предателю, предмет не оружие или брать незачем (такое оружие без патронов уже есть).
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
	elif is_new and _timing.can_put_away(Engine.get_physics_frames()):
		_set_held(index)
	_send_loadout()
	return true


## Сервер: взять груз в руки. Пока игрок его несёт, атаковать нельзя. Руки для этого
## не нужны: безрукий несёт груз так же (взаимодействие от рук не зависит). false — не взял:
## мёртв, уже что-то несёт, предмета нет в наборе ITEMS или оружие в руках ещё нельзя
## убрать после атаки.
func server_carry(item: ItemConfig) -> bool:
	if not Net.is_server() or _player.life != Player.Life.ALIVE or _carried != null:
		return false
	var index: int = ITEMS.index_of(item)
	if index <= EMPTY_HANDS or not _timing.can_put_away(Engine.get_physics_frames()):
		return false
	_carried = item
	_held_before_carry = _player.held_item
	_player.held_item = index
	return true


## Сервер: забрать груз из рук (игрок его доставил) — без сигнала carried_lost.
## В руки возвращается прежнее оружие; его нужно достать заново.
func server_take_carried() -> void:
	if not Net.is_server() or _carried == null:
		return
	_carried = null
	_set_held(_held_before_carry)


## Клиент-владелец: личные данные об оружии пришли с сервера. Вызывает Player.
## Негодные данные (не тот размер, типы, чужие номера) отбрасываются целиком.
func apply_loadout(data: Array) -> void:
	if _loadout.apply_data(data):
		loadout_changed.emit()


## Клиент-владелец: сервер сообщил, что атаковать нельзя ещё seconds секунд. Вызывает Player.
## Негодное число отбрасывается.
func apply_attack_lock(seconds: float) -> void:
	if not is_finite(seconds) or seconds < 0.0 or seconds > MAX_ATTACK_LOCK_SEC:
		return
	_attack_lock_left = seconds
	set_process(seconds > 0.0)
	attack_lock_changed.emit()


## Сервер: поставить запрос клиента в общую очередь.
func _queue_request(request: Array) -> void:
	if Net.is_server() and _requests.size() < MAX_QUEUED_REQUESTS:
		_requests.append(request)


## Сервер: в руках теперь оружие index. Новое оружие ещё нужно достать.
func _set_held(index: int) -> void:
	if index == _player.held_item:
		return
	_player.held_item = index
	var weapon: WeaponConfig = get_held_weapon()
	if weapon != null:
		_timing.draw(Engine.get_physics_frames(),
				WeaponTiming.to_ticks(weapon.draw_seconds, Engine.physics_ticks_per_second))


## Сервер: игрок бросил груз или потерял его.
func _drop_carried() -> void:
	var item: ItemConfig = _carried
	server_take_carried()
	carried_lost.emit(item)


## Сервер: руки пустеют сразу, что бы игрок ни держал (смерть, собрание). Груз падает.
func _empty_hands() -> void:
	_requests.clear()
	_held_before_carry = EMPTY_HANDS
	if _carried != null:
		_drop_carried()
	else:
		_set_held(EMPTY_HANDS)


## Сервер: одно нажатие Q.
func _server_switch_once() -> void:
	if _carried != null:
		_drop_carried()
		return
	if _can_act() and _timing.can_put_away(Engine.get_physics_frames()):
		_set_held(_loadout.next_index(_player.held_item, _player.limbs_lost))


## Сервер: одно нажатие цифровой клавиши.
func _server_select_once(slot: int) -> void:
	if not _can_act():
		return
	var index: int = _loadout.slot_index(slot, _player.limbs_lost)
	if index == WeaponLoadout.NO_SLOT:
		return
	if _carried != null:
		# Груз падает, в руках оказывается выбранное оружие.
		_held_before_carry = index
		_drop_carried()
	elif _timing.can_put_away(Engine.get_physics_frames()):
		_set_held(index)


## Сервер: одно нажатие атаки. Запрос, который сейчас выполнить нельзя, пропадает.
func _server_attack(yaw: float, pitch: float) -> void:
	var weapon: WeaponConfig = get_held_weapon()
	if weapon == null or _carried != null or _player.map == null or not _can_act():
		return
	var tick: int = Engine.get_physics_frames()
	var index: int = _player.held_item
	if not _timing.can_attack(tick) or not _loadout.spend_ammo(index):
		return
	_timing.attack(tick, WeaponTiming.to_ticks(weapon.attack_interval, Engine.physics_ticks_per_second))
	if weapon.uses_ammo:
		_send_loadout()
	var origin: Vector3 = _player.get_eye_position()
	var spread: float = Aim.spread_radians(weapon.spread_degrees, _player.limbs_lost,
			PlayerBody.CONFIG.one_arm_spread_factor)
	var direction: Vector3 = Aim.spread_direction(yaw, pitch, spread, _rng)
	var candidates: Array[Player] = []
	var positions: PackedVector3Array = []
	var yaws: PackedFloat32Array = []
	var limbs: PackedInt32Array = []
	for candidate: Player in _player.map.get_players():
		if candidate == _player or candidate.life != Player.Life.ALIVE:
			continue
		candidates.append(candidate)
		positions.append(candidate.global_position)
		yaws.append(candidate.rotation.y)
		limbs.append(candidate.limbs_lost)
	# Точный луч — по всем целям, и только при общем промахе — толщина удара.
	var best: BodyHit = PlayerBody.HITBOXES.intersect_ray_many(origin, direction, weapon.attack_range,
			positions, yaws, limbs, weapon.hit_radius)
	var victim: Player = candidates[best.body_index] if best != null else null
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


## Сервер: игрок умер или его убрали — руки пустеют: тело не должно показывать нож.
func _on_life_changed(new_life: Player.Life) -> void:
	if new_life != Player.Life.ALIVE:
		_empty_hands()


## Сервер: игрок потерял конечность. Оружие, которое больше не удержать (без обеих рук —
## любое, кроме «кулаков»; двуручное — без одной), убирается из рук. Груз остаётся: его
## несут и без рук, как и любое взаимодействие с предметами.
func _on_limbs_changed(mask: int) -> void:
	if _carried != null:
		if not _loadout.can_hold(_held_before_carry, mask):
			_held_before_carry = EMPTY_HANDS
	elif not _loadout.can_hold(_player.held_item, mask):
		_set_held(EMPTY_HANDS)


## Сервер: сменилась фаза матча.
## Собрание: у всех живых руки пустеют (оружие убрано, груз брошен) — игроков сажают
## в двух шагах друг от друга, и нож в руке был бы приговором соседу.
## Игра началась или продолжилась: общий запрет атак на GameConfig.attack_lock_seconds;
## хозяину аватара уходит его длина.
func _on_phase_changed(new_phase: Game.Phase) -> void:
	if _player.life != Player.Life.ALIVE:
		return
	match new_phase:
		Game.Phase.MEETING:
			_empty_hands()
		Game.Phase.PLAYING:
			var seconds: float = maxf(Game.config.attack_lock_seconds, 0.0)
			_timing.lock_attacks(Engine.get_physics_frames(),
					WeaponTiming.to_ticks(seconds, Engine.physics_ticks_per_second))
			_player.send_private(Player.Private.ATTACK_LOCK, [seconds])
