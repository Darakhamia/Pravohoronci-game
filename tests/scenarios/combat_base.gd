extends ScenarioBot
## Общая часть сценариев боя (combat*.gd): бот запоминает всё, что видит о каждом аватаре
## (атаки, предметы в руках), и умеет целиться в часть тела, быстро щёлкать атакой,
## выбирать оружие цифрой и перезаходить на сервер зрителем.
## Сам сценарием не является: у него нет файла .cfg.

const ITEMS: ItemSet = preload("res://resources/items/item_set.tres")
const FISTS: int = 0
const PISTOL: int = 1
const KNIFE: int = 2
const CANISTER: int = 3
## Цифровые клавиши оружия.
const SLOT_FISTS: int = 1
const SLOT_PISTOL: int = 2
const SLOT_KNIFE: int = 3
## Любой исход атаки (для count_attacks).
const ANY_IMPACT: int = -1
## Половина быстрого щелчка: клавиша нажата столько же, сколько отпущена. Игра опрашивает
## ввод раз в физический тик, поэтому короче трёх-четырёх тиков нажимать нельзя.
const CLICK_HALF_SEC: float = 0.06
## Насколько взгляд цели может отличаться от направления на стрелка.
const FACING_TOLERANCE: float = 0.08
## После остановки аватар ещё доезжает и поворачивается: ждём, прежде чем целиться.
const SETTLE_SEC: float = 0.5
## Запас к времени доставания оружия: округление до тика и кадр самого бота.
const DRAW_MARGIN_SEC: float = 0.15
## Сколько ждать подтверждения сервера на одно действие.
const REPLY_SEC: float = 4.0
## Сколько раз жать атаку, пока сервер её не подтвердит.
const ATTACK_TRIES: int = 4
## Взгляд почти вертикально вверх: знак конца сценария (см. signal_finish()), рад.
const FINISH_SIGNAL_PITCH: float = 1.4

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


## Нажать цифровую клавишу оружия (1 — кулаки, 2 — пистолет, 3 — нож).
func tap_slot(slot: int) -> void:
	await tap(PlayerInput.WEAPON_SLOT_ACTIONS[slot - 1])


## Выбрать оружие цифрой и дождаться, пока сервер покажет его в руках и его можно будет
## пустить в ход. Сервер достал оружие не позже, чем бот это увидел, поэтому ждать время
## доставания от этого момента — с запасом при любой задержке сети.
func draw_weapon(slot: int, item_index: int) -> bool:
	await tap_slot(slot)
	if not await expect(func() -> bool: return me().held_item == item_index, REPLY_SEC,
			"клавиша %d не дала в руки предмет %d: в руках %d" % [slot, item_index, me().held_item]):
		return false
	await wait_drawn()
	return true


## Подождать, пока оружие в руках достанут до конца (см. draw_weapon()).
func wait_drawn() -> void:
	var weapon: WeaponConfig = me().weapons.get_held_weapon()
	await wait_seconds((weapon.draw_seconds if weapon != null else 0.0) + DRAW_MARGIN_SEC)


## Жать атаку, пока сервер не подтвердит новую атаку своего игрока (запрос, пришедший
## раньше срока, сервер молча отбрасывает). false — атаки так и не случилось.
func attack_until_seen() -> bool:
	var before: int = count_all_attacks(Net.local_id())
	for attempt: int in ATTACK_TRIES:
		await click(&"fire")
		if await wait_until(func() -> bool: return count_all_attacks(Net.local_id()) > before, REPLY_SEC):
			return true
	return false


## Выйти с сервера и зайти снова под тем же именем — уже зрителем идущего матча, с новым
## peer_id и без аватара. База считает обрыв сессии провалом, поэтому на время выхода
## говорим ей, что уходим сами. Записи о чужих аватарах после этого начинаются заново.
func leave_and_rejoin() -> bool:
	_release_all()
	_is_leaving = true
	Net.leave()
	_attacks.clear()
	_held_history.clear()
	# Сервер должен успеть заметить выход, иначе имя ещё занято.
	await wait_seconds(0.5)
	var port: int = CmdArgs.get_int("--port", Net.DEFAULT_PORT, CmdArgs.MIN_PORT, CmdArgs.MAX_PORT)
	var error: Error = Net.join_server(SERVER_ADDRESS, port, bot_name)
	if not check(error == OK, "повторный вход: Net.join_server вернул %s" % error_string(error)):
		return false
	if not await expect(Net.is_joined, CONNECT_DEADLINE_SEC, "сервер не пустил обратно"):
		return false
	_is_leaving = false
	if not await expect(func() -> bool: return world.current_map != null and Game.state == Game.State.MATCH,
			AVATARS_DEADLINE_SEC, "вернувшийся не получил карту идущего матча"):
		return false
	step("вернулся зрителем")
	return true


## Знак серверному помощнику combat_finish_director.gd: сценарий закончен, пора в лобби.
## Бот смотрит почти вертикально вверх (взгляд живого игрока сервер знает всегда).
func signal_finish() -> void:
	step("сценарий пройден, подаю знак серверу")
	me().input.pitch = FINISH_SIGNAL_PITCH


## Сервер вернул всех в лобби и убрал карту.
func expect_lobby(timeout_sec: float) -> bool:
	return await expect(func() -> bool: return Game.state == Game.State.LOBBY and world.current_map == null,
			timeout_sec, "сервер не вернул игроков в лобби")


## Расстояние между двумя аватарами по горизонтали.
func flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


## Чужие личные данные до бота не дошли: про других он знает только кулаки и полное здоровье.
func check_no_private_leaks() -> bool:
	for peer_id: int in Net.players:
		if peer_id == Net.local_id():
			continue
		var other: Player = avatar(peer_id)
		# Зритель, вошедший посреди матча, — без аватара.
		if other == null:
			continue
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
