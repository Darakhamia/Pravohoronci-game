extends Node
## Серверный помощник сценария sabotage: второй по счёту саботаж сбрасывает «собранием».
## Модуль собраний в этой сборке может быть заглушкой, поэтому помощник сам подаёт его
## сигнал started — ровно то, что слушают саботаж и карта.

## Какой по счёту саботаж сбросить.
const CANCELLED_SABOTAGE: int = 2
## Через сколько секунд после его начала «созвать собрание».
const MEETING_DELAY_SEC: float = 1.5

var _started_count: int = 0
var _meeting_in_sec: float = 0.0


func _ready() -> void:
	Game.round_started.connect(_on_round_started)
	Game.sabotage.started.connect(_on_sabotage_started)


func _process(delta: float) -> void:
	if _meeting_in_sec <= 0.0:
		return
	_meeting_in_sec -= delta
	if _meeting_in_sec > 0.0:
		return
	if not Game.sabotage.active:
		push_error("[director] саботаж закончился раньше, чем его сбросило собрание")
		return
	Game.meeting.started.emit()
	if Game.sabotage.active or Game.sabotage.cooldown_left <= 0.0:
		push_error("[director] собрание не сбросило саботаж или пауза не началась заново")


func _on_round_started() -> void:
	_started_count = 0
	_meeting_in_sec = 0.0


func _on_sabotage_started() -> void:
	_started_count += 1
	if _started_count == CANCELLED_SABOTAGE:
		_meeting_in_sec = MEETING_DELAY_SEC
