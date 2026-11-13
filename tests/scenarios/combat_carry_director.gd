extends "res://tests/scenarios/combat_director.gd"
## Серверный помощник сценария combat_carry: играет роль модуля заданий — выдаёт игроку
## груз (канистру) и считает, сколько раз игрок его лишился. Шаги идут по тому, что делает
## бот: груз в начале игры; второй груз — после первого выстрела бота; затем игрок теряет
## обе руки. Если груз не упал, когда должен, — строка ERROR в логе сервера.

enum Step { GIVE_LOAD, WAIT_FOR_SHOT, WAIT_BEFORE_ARMS, DONE }

const CANISTER: ItemConfig = preload("res://resources/items/canister.tres")
const PISTOL: int = 1
## Пауза между вторым грузом и потерей рук: бот должен успеть увидеть груз в руках.
const ARMS_DELAY_SEC: float = 1.0

var _step: Step = Step.GIVE_LOAD
var _lost_count: int = 0
var _has_shot: bool = false
var _arms_delay_left: float = 0.0


func _process(delta: float) -> void:
	super(delta)
	var player: Player = _get_player()
	if player == null or not Game.is_playing():
		return
	match _step:
		Step.GIVE_LOAD:
			player.weapons.carried_lost.connect(_on_carried_lost)
			player.event_sent.connect(_on_player_event)
			_give_load(player)
			_step = Step.WAIT_FOR_SHOT
		Step.WAIT_FOR_SHOT:
			if not _has_shot:
				return
			if _lost_count != 1 or player.held_item != PISTOL:
				push_error("[director] перед выстрелом груз должен был упасть один раз, а в руках быть пистолет")
			_give_load(player)
			_arms_delay_left = ARMS_DELAY_SEC
			_step = Step.WAIT_BEFORE_ARMS
		Step.WAIT_BEFORE_ARMS:
			_arms_delay_left -= delta
			if _arms_delay_left > 0.0:
				return
			var limb_health: int = PlayerBody.CONFIG.limb_health
			player.body.server_apply_damage(BodyPart.Part.LEFT_ARM, limb_health)
			if _lost_count != 1 or not player.weapons.is_carrying(CANISTER):
				push_error("[director] с одной рукой игрок должен нести груз дальше")
			player.body.server_apply_damage(BodyPart.Part.RIGHT_ARM, limb_health)
			if _lost_count != 2 or player.held_item != PlayerWeapons.EMPTY_HANDS:
				push_error("[director] без обеих рук груз должен упасть, а руки — опустеть")
			_step = Step.DONE


func _give_load(player: Player) -> void:
	if not player.weapons.server_carry(CANISTER):
		push_error("[director] сервер не дал игроку груз")
	print("[director] load given")


func _get_player() -> Player:
	if _world == null or _world.current_map == null:
		return null
	var players: Array[Player] = _world.current_map.get_players()
	return players[0] if not players.is_empty() else null


func _on_carried_lost(item: ItemConfig) -> void:
	_lost_count += 1
	print("[director] load lost item=%s count=%d" % [item.title, _lost_count])


func _on_player_event(kind: Player.Event, data: Array) -> void:
	var attack: AttackEvent = AttackEvent.decode(data, ITEMS) if kind == Player.Event.ATTACK else null
	if attack != null and attack.item_index == PISTOL:
		_has_shot = true
