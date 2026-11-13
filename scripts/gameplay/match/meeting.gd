class_name Meeting
extends Node
## Собрание и голосование (узел Game.meeting, есть на каждом пире).
## Сервер ведёт стадии и считает голоса; клиенты получают копию и показывают экран.
## О сценах Meeting не знает: карта слушает started/ejected/closed и сама рассаживает
## игроков, убирает тела и выбрасывает изгнанного.

## Стадии собрания. NONE — собрания нет.
enum Stage { NONE, DISCUSSION, VOTING, VERDICT }
## Почему созвали собрание.
enum Reason { BUTTON, BODY }

## Все пиры: собрание началось (поля caller_id, reason, victim_id, attendees уже заполнены).
signal started
## Все пиры: сменилась стадия; сколько она продлится — в stage_seconds_left.
signal stage_changed(new_stage: Stage)
## Все пиры: участник проголосовал (за кого — до вердикта тайна).
signal vote_cast(voter_id: int)
## Все пиры: вердикт (поля votes, ejected_id, ejected_role заполнены).
signal verdict_ready
## Все пиры: собрание закончилось.
signal closed
## Сервер: этого участника изгнали — карта убирает его аватар.
signal ejected(peer_id: int)

var stage: Stage = Stage.NONE
## Сколько секунд осталось до конца стадии. Идёт на всех пирах.
var stage_seconds_left: float = 0.0
## Кто созвал собрание.
var caller_id: int = 0
var reason: Reason = Reason.BUTTON
## Чьё тело нашли (для Reason.BODY), иначе 0.
var victim_id: int = 0
## Кто был жив в начале собрания: только они голосуют и только за них можно голосовать.
var attendees: PackedInt32Array = []
## Кто уже проголосовал.
var voted: Dictionary[int, bool] = {}
## После вердикта: кто за кого голосовал (MatchRules.SKIP_VOTE — пропуск).
var votes: Dictionary[int, int] = {}
## После вердикта: кого изгнали (MatchRules.SKIP_VOTE — никого) и кем он был
## (Game.Role.NONE, если роль изгнанного не показываем).
var ejected_id: int = MatchRules.SKIP_VOTE
var ejected_role: Game.Role = Game.Role.NONE


func is_active() -> bool:
	return stage != Stage.NONE


## Сервер: созвать собрание. false, если сейчас нельзя (не идёт игра, созывающий мёртв).
## Лимит и пауза тревожной кнопки проверяются в can_press_button().
func server_call(_caller_id: int, _reason: Reason, _victim_id: int = 0) -> bool:
	return false


## Может ли игрок сейчас нажать тревожную кнопку. Сервер: про любого. Клиент: про себя.
func can_press_button(_peer_id: int) -> bool:
	return false


## Клиент: проголосовать за участника (MatchRules.SKIP_VOTE — пропустить).
func request_vote(_target_id: int) -> void:
	pass
