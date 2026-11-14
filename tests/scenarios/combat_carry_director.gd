extends "res://tests/scenarios/combat_director.gd"
## Серверный помощник сценария combat_carry: играет роль модуля заданий — выдаёт игроку
## груз (канистру) и считает, сколько раз игрок его лишился. Шаги идут по тому, что делает
## бот: груз в начале игры; второй груз — после первого выстрела бота (не раньше, чем
## пистолет можно убрать после выстрела); затем игрок теряет обе руки, и груз остаётся
## у него; третий груз — после пинка безрукого. Что-то не так — строка ERROR в логе сервера.

enum Step { GIVE_LOAD, WAIT_FOR_SHOT, GIVE_SECOND, WAIT_BEFORE_ARMS, WAIT_FOR_KICK, GIVE_THIRD, DONE }

const CANISTER: ItemConfig = preload("res://resources/items/canister.tres")
const FISTS: int = 0
const PISTOL: int = 1
## Пауза между вторым грузом и потерей рук: бот должен успеть увидеть груз в руках.
const ARMS_DELAY_SEC: float = 1.0

var _step: Step = Step.GIVE_LOAD
var _lost_count: int = 0
var _has_shot: bool = false
var _has_kicked: bool = false
var _arms_delay_left: float = 0.0
## Сколько раз сервер отказался дать груз, пока оружие нельзя было убрать после атаки.
var _refused_count: int = 0


func _process(delta: float) -> void:
	super(delta)
	var player: Player = _get_player()
	if player == null or not Game.is_playing():
		return
	match _step:
		Step.GIVE_LOAD:
			player.weapons.carried_lost.connect(_on_carried_lost)
			player.event_sent.connect(_on_player_event)
			if not player.weapons.server_carry(CANISTER):
				push_error("[director] сервер не дал игроку груз")
			print("[director] load given")
			_step = Step.WAIT_FOR_SHOT
		Step.WAIT_FOR_SHOT:
			if not _has_shot:
				return
			if _lost_count != 1 or player.held_item != PISTOL:
				push_error("[director] перед выстрелом груз должен был упасть один раз, а в руках быть пистолет")
			_refused_count = 0
			_step = Step.GIVE_SECOND
		Step.GIVE_SECOND:
			# Сразу после выстрела пистолет убрать нельзя: груз в руки не идёт.
			if not _give_when_allowed(player):
				return
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
			# Взаимодействие от рук не зависит: груз остаётся и у безрукого.
			if _lost_count != 1 or not player.weapons.is_carrying(CANISTER):
				push_error("[director] без обеих рук игрок должен нести груз дальше: потерь %d, в руках %d" % [
						_lost_count, player.held_item])
			print("[director] arms lost, load kept")
			_step = Step.WAIT_FOR_KICK
		Step.WAIT_FOR_KICK:
			if not _has_kicked:
				return
			if _lost_count != 2 or player.held_item != FISTS:
				push_error("[director] перед пинком безрукий должен был бросить груз: потерь %d, в руках %d" % [
						_lost_count, player.held_item])
			_refused_count = 0
			_step = Step.GIVE_THIRD
		Step.GIVE_THIRD:
			# Безрукий берёт новый груз так же, как любой другой игрок.
			if _give_when_allowed(player):
				_step = Step.DONE


## Давать груз каждый кадр, пока сервер не согласится. Первый отказ обязателен: игрок
## только что атаковал, и оружие ещё нельзя убрать. true — груз в руках.
func _give_when_allowed(player: Player) -> bool:
	if not player.weapons.server_carry(CANISTER):
		_refused_count += 1
		return false
	if _refused_count == 0:
		push_error("[director] груз попал в руки сразу после атаки: оружие убрано раньше паузы")
	if not player.weapons.is_carrying(CANISTER):
		push_error("[director] сервер сказал, что дал груз, а в руках %d" % player.held_item)
	print("[director] load given after %d refusals" % _refused_count)
	return true


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
	if attack == null:
		return
	if attack.item_index == PISTOL:
		_has_shot = true
	elif attack.item_index == FISTS:
		_has_kicked = true
