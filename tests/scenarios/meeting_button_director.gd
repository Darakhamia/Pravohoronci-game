extends Node
## Серверный помощник сценария meeting_button.
## 1. Под конец первой паузы тревожной кнопки включает «саботаж» (поля Game.sabotage) и
##    держит его, пока Bot1 не подаст знак взглядом вверх: всё это время кнопка работать
##    не должна. Раньше включать нельзя: тогда запрос Bot1 во время паузы отклонялся бы
##    из-за саботажа, и проверка самой паузы ничего бы не стоила.
## 2. Проверяет по часам сервера, что голосование, где проголосовали не все, шло до
##    тайм-аута, а не закончилось досрочно.
## О нарушении сообщает ошибкой в логе сервера: run_scenario.sh считает её провалом.

const SIGNAL_NAME: String = "Bot1"
## Саботаж включается, когда серверной паузе кнопки остаётся меньше этого. Bot1 шлёт
## свой запрос «во время паузы», только пока ей остаётся заметно больше
## (meeting_button.gd, MIN_COOLDOWN_FOR_CHECK).
const SABOTAGE_BEFORE_COOLDOWN_END_SEC: float = 1.0
## Тот же порог, что у ботов (MeetingBot.SIGNAL_PITCH_THRESHOLD).
const SIGNAL_PITCH_THRESHOLD: float = 1.0
## Чтобы настоящий модуль саботажа не «взорвал» реактор посреди теста.
const SABOTAGE_SECONDS: float = 9999.0
## Часы сервера и таймер стадии могут разойтись на кадр-другой.
const TIMEOUT_TOLERANCE_SEC: float = 0.25
const MSEC_PER_SEC: float = 1000.0

var _is_sabotage_held: bool = false
var _is_sabotage_done: bool = false
var _voting_started_msec: int = 0


func _ready() -> void:
	Game.meeting.started.connect(_on_meeting_started)
	Game.meeting.stage_changed.connect(_on_stage_changed)


func _process(_delta: float) -> void:
	if _is_sabotage_done or not Game.is_playing():
		return
	if not _is_sabotage_held:
		var cooldown_left: float = Game.meeting.button_cooldown_left
		if cooldown_left > 0.0 and cooldown_left < SABOTAGE_BEFORE_COOLDOWN_END_SEC:
			_is_sabotage_held = true
			Game.sabotage.active = true
			Game.sabotage.seconds_left = SABOTAGE_SECONDS
			print("[director] саботаж включён")
		return
	var player: Player = _get_player(SIGNAL_NAME)
	if player != null and player.input.get_pitch() > SIGNAL_PITCH_THRESHOLD:
		_is_sabotage_held = false
		_is_sabotage_done = true
		Game.sabotage.active = false
		Game.sabotage.seconds_left = 0.0
		print("[director] саботаж снят")


func _on_meeting_started() -> void:
	if not _is_sabotage_done:
		push_error("[director] тревожная кнопка сработала во время паузы или саботажа")


func _on_stage_changed(new_stage: Meeting.Stage) -> void:
	if new_stage == Meeting.Stage.VOTING:
		_voting_started_msec = Time.get_ticks_msec()
	elif new_stage == Meeting.Stage.VERDICT:
		var voting_sec: float = (Time.get_ticks_msec() - _voting_started_msec) / MSEC_PER_SEC
		var is_everyone_in: bool = Game.meeting.voted.size() >= Game.meeting.attendees.size()
		if not is_everyone_in and voting_sec < Game.config.meeting_voting_seconds - TIMEOUT_TOLERANCE_SEC:
			push_error("[director] голосование закончилось через %.2f с, хотя проголосовали не все" % voting_sec)


func _get_player(player_name: String) -> Player:
	var world: World = get_tree().root.get_node(^"Main/World") as World
	if world.current_map == null:
		return null
	for peer_id: int in Net.players:
		if Net.players[peer_id] == player_name:
			return world.current_map.get_player(peer_id)
	return null
