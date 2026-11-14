extends Node
## Серверный помощник сценария meeting_leave: проверяет по часам сервера, что голосование
## не ждало вышедших игроков и закончилось досрочно, и что голоса, связанные с вышедшими,
## в вердикт не попали. О нарушении сообщает ошибкой в логе сервера: run_scenario.sh
## считает её провалом.

## Досрочное голосование должно закончиться хотя бы на столько секунд раньше срока.
const EARLY_MARGIN_SEC: float = 2.0
const MSEC_PER_SEC: float = 1000.0

var _voting_started_msec: int = 0


func _ready() -> void:
	Game.meeting.stage_changed.connect(_on_stage_changed)


func _on_stage_changed(new_stage: Meeting.Stage) -> void:
	var meeting: Meeting = Game.meeting
	if new_stage == Meeting.Stage.VOTING:
		_voting_started_msec = Time.get_ticks_msec()
		return
	if new_stage != Meeting.Stage.VERDICT:
		return
	var voting_sec: float = (Time.get_ticks_msec() - _voting_started_msec) / MSEC_PER_SEC
	if voting_sec > Game.config.meeting_voting_seconds - EARLY_MARGIN_SEC:
		push_error("[director] голосование шло %.1f с: сервер ждал вышедших игроков" % voting_sec)
	for voter_id: int in meeting.votes:
		if meeting.dropped.has(voter_id) or meeting.dropped.has(meeting.votes[voter_id]):
			push_error("[director] в вердикт попал голос, связанный с вышедшим игроком %d" % voter_id)
