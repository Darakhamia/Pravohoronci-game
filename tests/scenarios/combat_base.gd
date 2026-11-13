extends ScenarioBot
## Общая часть сценариев боя (combat*.gd): бот запоминает всё, что видит о каждом аватаре
## (атаки, предметы в руках), и умеет целиться в часть тела и быстро щёлкать атакой.
## Сам сценарием не является: у него нет файла .cfg.

const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
const FISTS: int = 0
const PISTOL: int = 1
const KNIFE: int = 2
## Любой исход атаки (для count_attacks).
const ANY_IMPACT: int = -1
## Половина быстрого щелчка: клавиша нажата столько же, сколько отпущена. Игра опрашивает
## ввод раз в физический тик, поэтому короче трёх-четырёх тиков нажимать нельзя.
const CLICK_HALF_SEC: float = 0.06
## Насколько взгляд цели может отличаться от направления на стрелка.
const FACING_TOLERANCE: float = 0.08
## После остановки аватар ещё доезжает и поворачивается: ждём, прежде чем целиться.
const SETTLE_SEC: float = 0.5

## Атаки каждого аватара, как их увидел этот бот: peer_id -> список AttackEvent.
var _attacks: Dictionary[int, Array] = {}
## Что каждый аватар брал в руки, по порядку: peer_id -> номера предметов.
var _held_history: Dictionary[int, PackedInt32Array] = {}
## События атаки, которые не прошли проверку AttackEvent.decode().
var _bad_events: int = 0


## Начать записывать события всех аватаров. Вызывается в начале сценария.
func track_avatars() -> void:
	for peer_id: int in Net.players:
		var player: Player = avatar(peer_id)
		_attacks[peer_id] = []
		_held_history[peer_id] = PackedInt32Array()
		player.event_received.connect(_on_avatar_event.bind(peer_id))
		player.held_item_changed.connect(_on_avatar_held_item_changed.bind(peer_id))


## Сколько атак аватара увидел бот: этим оружием и с этим исходом (ANY_IMPACT — с любым).
func count_attacks(peer_id: int, item_index: int, impact: int = ANY_IMPACT) -> int:
	var count: int = 0
	for attack: AttackEvent in _attacks.get(peer_id, []):
		if attack.item_index == item_index and (impact == ANY_IMPACT or attack.impact == impact):
			count += 1
	return count


## Все атаки аватара, которые увидел бот.
func count_all_attacks(peer_id: int) -> int:
	var attacks: Array = _attacks.get(peer_id, [])
	return attacks.size()


func held_history(peer_id: int) -> PackedInt32Array:
	return _held_history.get(peer_id, PackedInt32Array())


func bad_event_count() -> int:
	return _bad_events


## Центр части тела стоящего игрока в мире (по хитбоксам из ресурса).
func part_position(player: Player, part: BodyPart.Part) -> Vector3:
	for box: Hitbox in PlayerBody.HITBOXES.standing:
		if box.part == part:
			return player.global_transform * box.center
	return player.global_position


func aim_at_part(player: Player, part: BodyPart.Part) -> void:
	look_at_point(part_position(player, part))


## Смотрит ли аватар target прямо на точку (по тому, что видит этот бот).
func is_facing(target: Player, point: Vector3) -> bool:
	var offset: Vector3 = point - target.global_position
	var wanted_yaw: float = atan2(-offset.x, -offset.z)
	return absf(angle_difference(target.rotation.y, wanted_yaw)) <= FACING_TOLERANCE


## Быстрый щелчок: нажать и отпустить.
func click(action: StringName) -> void:
	press(action)
	await wait_seconds(CLICK_HALF_SEC)
	release(action)
	await wait_seconds(CLICK_HALF_SEC)


## Расстояние между двумя аватарами по горизонтали.
func flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


## Чужие личные данные до бота не дошли: про других он знает только кулаки и полное здоровье.
func check_no_private_leaks() -> bool:
	for peer_id: int in Net.players:
		if peer_id == Net.local_id():
			continue
		var other: Player = avatar(peer_id)
		var other_name: String = Net.get_player_name(peer_id)
		if not check(other.weapons.get_owned_weapons().size() == 1, "боту известно оружие игрока %s" % other_name):
			return false
		if not check(other.weapons.get_ammo() == WeaponLoadout.NO_AMMO_COUNTER, "боту известны патроны игрока %s" % other_name):
			return false
		if not check(other.body.health == PlayerBody.CONFIG.max_health, "боту известно здоровье игрока %s" % other_name):
			return false
	return true


func _on_avatar_event(kind: Player.Event, data: Array, peer_id: int) -> void:
	if kind != Player.Event.ATTACK:
		return
	var attack: AttackEvent = AttackEvent.decode(data, ITEMS)
	if attack == null:
		_bad_events += 1
		return
	_attacks[peer_id].append(attack)


func _on_avatar_held_item_changed(item_id: int, peer_id: int) -> void:
	_held_history[peer_id].append(item_id)
