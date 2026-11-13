class_name PlayerBody
extends Node
## Здоровье и части тела игрока (узел Body внутри Player). Считает сервер.
## Всем видно только то, что и так видно в мире: потерянные конечности (Player.limbs_lost)
## и смерть (Player.life). Точные числа здоровья сервер шлёт одному хозяину аватара.

## Клиент-владелец: изменились health или part_health.
signal vitals_changed
## Сервер: игрок получил урон. attacker_id — кто нанёс (0 — никто).
signal damaged(part: BodyPart.Part, amount: int, attacker_id: int)

const CONFIG: BodyConfig = preload("res://resources/player/body_config.tres")

## Общее здоровье. Знают сервер и хозяин аватара.
var health: int = CONFIG.max_health
## Здоровье частей тела по порядку BodyPart.Part. У головы и торса отдельного запаса нет:
## их значение не меняется.
var part_health: PackedInt32Array = _full_part_health()

@onready var _player: Player = get_parent() as Player


## Сервер: вернуть полное здоровье и все конечности (начало раунда).
func server_reset() -> void:
	if not Net.is_server():
		return
	health = CONFIG.max_health
	part_health = _full_part_health()
	_player.limbs_lost = 0
	_send_vitals()


## Сервер: попадание в часть тела. Голова — больше урона; конечность теряет своё здоровье
## и отлетает, когда оно кончается. Здоровье кончилось — игрок становится телом.
func server_apply_damage(part: BodyPart.Part, amount: int, attacker_id: int = 0) -> void:
	if not Net.is_server() or _player.life != Player.Life.ALIVE or amount <= 0:
		return
	var health_loss: int = amount
	if part == BodyPart.Part.HEAD:
		health_loss = roundi(amount * CONFIG.head_multiplier)
	elif BodyPart.LIMBS.has(part):
		health_loss = roundi(amount * CONFIG.limb_multiplier)
		part_health[part] = maxi(part_health[part] - amount, 0)
		if part_health[part] == 0:
			_player.limbs_lost |= BodyPart.bit(part)
	health = maxi(health - health_loss, 0)
	_send_vitals()
	damaged.emit(part, amount, attacker_id)
	if health == 0:
		_player.server_set_life(Player.Life.CORPSE)


## Клиент-владелец: числа пришли с сервера. Вызывает Player.
func apply_vitals(new_health: int, new_part_health: PackedInt32Array) -> void:
	if new_part_health.size() != BodyPart.Part.size():
		return
	health = new_health
	part_health = new_part_health
	vitals_changed.emit()


## Доля обычной скорости: без одной ноги игрок хромает, без обеих — ползёт.
func get_speed_factor() -> float:
	match BodyPart.lost_legs(_player.limbs_lost):
		0:
			return 1.0
		1:
			return CONFIG.one_leg_speed_factor
	return CONFIG.crawl_speed_factor


## Без обеих ног игрок ползёт: глаза у пола, прыгать нельзя.
func is_crawling() -> bool:
	return BodyPart.lost_legs(_player.limbs_lost) >= BodyPart.LEG_COUNT


func can_jump() -> bool:
	return BodyPart.lost_legs(_player.limbs_lost) == 0


func get_eye_height() -> float:
	return CONFIG.crawl_eye_height if is_crawling() else CONFIG.stand_eye_height


func _send_vitals() -> void:
	_player.send_private(Player.Private.VITALS, [health, part_health])


static func _full_part_health() -> PackedInt32Array:
	var values: PackedInt32Array = []
	values.resize(BodyPart.Part.size())
	values.fill(CONFIG.limb_health)
	return values
