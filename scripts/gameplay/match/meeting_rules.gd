class_name MeetingRules
extends RefCounted
## Правила собрания без состояния: кто может голосовать и за кого, когда голосование можно
## закончить досрочно, что делать с голосами выбывшего, когда работает тревожная кнопка.
## Чистые функции: их проверяют модульные тесты, а вызывает Meeting (сервер решает,
## клиент теми же функциями узнаёт, что ему показать). Подсчёт голосов — MatchRules.tally_votes.
##
## Во всех функциях attendees — кто был жив в начале собрания, dropped — кто из них выбыл
## уже во время собрания (вышел из игры), voted — кто уже проголосовал.


## Может ли участник ещё отдать голос: он был на собрании, не выбыл и не голосовал.
static func can_vote(voter_id: int, attendees: PackedInt32Array, dropped: Dictionary[int, bool],
		voted: Dictionary[int, bool]) -> bool:
	return attendees.has(voter_id) and not dropped.has(voter_id) and not voted.has(voter_id)


## Можно ли голосовать за target_id: это пропуск или участник собрания, который не выбыл.
static func is_candidate(target_id: int, attendees: PackedInt32Array,
		dropped: Dictionary[int, bool]) -> bool:
	if target_id == MatchRules.SKIP_VOTE:
		return true
	return attendees.has(target_id) and not dropped.has(target_id)


## Принимается ли голос voter_id за target_id. Голосовать за себя можно.
static func is_vote_valid(voter_id: int, target_id: int, attendees: PackedInt32Array,
		dropped: Dictionary[int, bool], voted: Dictionary[int, bool]) -> bool:
	return (can_vote(voter_id, attendees, dropped, voted)
			and is_candidate(target_id, attendees, dropped))


## Проголосовали ли все, кого ещё стоит ждать. Если ждать некого — тоже true.
static func has_everyone_voted(attendees: PackedInt32Array, dropped: Dictionary[int, bool],
		voted: Dictionary[int, bool]) -> bool:
	for peer_id: int in attendees:
		if not dropped.has(peer_id) and not voted.has(peer_id):
			return false
	return true


## Голоса без выбывшего: пропадает и его голос, и голоса, отданные за него.
## Исходный словарь не меняется.
static func discard_votes_of(ballots: Dictionary[int, int], leaver_id: int) -> Dictionary[int, int]:
	var kept: Dictionary[int, int] = {}
	for voter_id: int in ballots:
		if voter_id != leaver_id and ballots[voter_id] != leaver_id:
			kept[voter_id] = ballots[voter_id]
	return kept


## Сработает ли тревожная кнопка: идёт игра, игрок жив, у него остались нажатия,
## общая пауза прошла и нет саботажа.
static func can_press_button(is_playing: bool, is_alive: bool, uses_left: int,
		cooldown_left: float, is_sabotage_active: bool) -> bool:
	return (is_playing and is_alive and uses_left > 0 and cooldown_left <= 0.0
			and not is_sabotage_active)
