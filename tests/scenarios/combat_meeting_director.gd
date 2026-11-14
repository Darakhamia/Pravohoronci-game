extends "res://tests/scenarios/combat_finish_director.gd"
## Серверный помощник сценария combat_meeting. Когда Bot2 первый раз бьёт кулаком (запрет
## атак в начале игры кончился), отнимает у Bot3 обе ноги и даёт Bot2 груз, как это делает
## в игре стеллаж с канистрами. В начале собрания проверяет по состоянию сервера: груз упал
## через carried_lost, у всех живых пустые руки. Запрет атак после начала игры и после
## собрания сторожит по тикам combat_director.gd. Что-то не так — строка ERROR в логе.

const CARRIER_NAME: String = "Bot2"
const CRAWLER_NAME: String = "Bot3"
const CANISTER: ItemConfig = preload("res://resources/items/canister.tres")
const FISTS: int = 0

var _is_punch_seen: bool = false
var _is_load_given: bool = false
var _lost_count: int = 0
var _meeting_count: int = 0


func _ready() -> void:
	super()
	Game.meeting.started.connect(_on_meeting_started)


func _process(delta: float) -> void:
	super(delta)
	if not _is_punch_seen or _is_load_given or not Game.is_playing():
		return
	var carrier: Player = _find(CARRIER_NAME)
	# Сразу после удара кулаки «убрать» нельзя: груз в руки пойдёт, когда пройдёт их пауза.
	if carrier != null and carrier.weapons.server_carry(CANISTER):
		_is_load_given = true
		print("[director] load given to %s" % CARRIER_NAME)


func _on_player_added(player: Player) -> void:
	super(player)
	player.weapons.carried_lost.connect(_on_carried_lost.bind(player))
	player.event_sent.connect(_on_player_event.bind(player))


func _on_player_event(kind: Player.Event, _data: Array, player: Player) -> void:
	if kind != Player.Event.ATTACK or _is_punch_seen or player.display_name != CARRIER_NAME:
		return
	_is_punch_seen = true
	var crawler: Player = _find(CRAWLER_NAME)
	var limb_health: int = PlayerBody.CONFIG.limb_health
	crawler.body.server_apply_damage(BodyPart.Part.LEFT_LEG, limb_health)
	crawler.body.server_apply_damage(BodyPart.Part.RIGHT_LEG, limb_health)
	print("[director] legs taken from %s" % CRAWLER_NAME)


func _on_carried_lost(item: ItemConfig, player: Player) -> void:
	_lost_count += 1
	print("[director] load lost by=%s item=%s count=%d" % [player.display_name, item.title, _lost_count])


## Собрание началось: руки должны быть пусты уже сейчас, до первого слова.
func _on_meeting_started() -> void:
	_meeting_count += 1
	print("[director] meeting started")
	if _lost_count != 1:
		push_error("[director] к началу собрания груз должен был упасть один раз, а упал %d" % _lost_count)
	for player: Player in _world.current_map.get_players():
		if player.life != Player.Life.ALIVE:
			continue
		if player.held_item != FISTS or player.weapons.is_carrying(CANISTER):
			push_error("[director] на собрании у игрока %s в руках предмет %d" % [player.display_name, player.held_item])


func _find(player_name: String) -> Player:
	if _world == null or _world.current_map == null:
		return null
	for player: Player in _world.current_map.get_players():
		if player.display_name == player_name:
			return player
	return null
