class_name MatchRules
extends RefCounted
## Правила матча без состояния: сколько предателей, кому какая роль, кто победил, кого изгнали.
## Чистые функции: их проверяют модульные тесты, а вызывает сервер (Game и его части).

## «Голос» за пропуск в словаре голосов собрания.
const SKIP_VOTE: int = 0


## Сколько предателей в матче на столько игроков.
static func traitor_count(player_count: int, config: GameConfig) -> int:
	if player_count >= config.players_for_two_traitors:
		return 2
	if player_count >= config.players_for_one_traitor:
		return 1
	return 0


## Раздаёт роли: peer_id -> Game.Role. Сначала предателями становятся forced (отладка и
## тесты), остальные места — случайно. Предателей не больше, чем игроков.
static func deal_roles(peer_ids: Array[int], traitors: int, forced: Array[int],
		rng: RandomNumberGenerator) -> Dictionary[int, Game.Role]:
	var roles: Dictionary[int, Game.Role] = {}
	var pool: Array[int] = []
	for peer_id: int in peer_ids:
		roles[peer_id] = Game.Role.CREW
		pool.append(peer_id)
	var left: int = clampi(traitors, 0, pool.size())
	for peer_id: int in forced:
		if left > 0 and pool.has(peer_id):
			roles[peer_id] = Game.Role.TRAITOR
			pool.erase(peer_id)
			left -= 1
	while left > 0:
		var index: int = rng.randi_range(0, pool.size() - 1)
		roles[pool[index]] = Game.Role.TRAITOR
		pool.remove_at(index)
		left -= 1
	return roles


## Победитель по числу живых. Правило действует, только если на старте были и предатели,
## и экипаж: иначе матч для отладки закончился бы, не начавшись.
static func winner_by_headcount(traitors_alive: int, crew_alive: int,
		traitors_at_start: int, crew_at_start: int) -> Game.Winner:
	if traitors_at_start <= 0 or crew_at_start <= 0:
		return Game.Winner.NONE
	if traitors_alive <= 0:
		return Game.Winner.CREW
	if traitors_alive >= crew_alive:
		return Game.Winner.TRAITORS
	return Game.Winner.NONE


## Кого изгнать по итогам голосования. votes: кто -> за кого (SKIP_VOTE — пропуск).
## Нужно строгое большинство среди поданных голосов; ничья или победа пропуска — никого
## (возвращает SKIP_VOTE). Кто не голосовал, тот не считается.
static func tally_votes(votes: Dictionary[int, int]) -> int:
	var counts: Dictionary[int, int] = {}
	for voter: int in votes:
		var target: int = votes[voter]
		counts[target] = (counts[target] if counts.has(target) else 0) + 1
	var best_target: int = SKIP_VOTE
	var best_count: int = 0
	var is_tie: bool = false
	for target: int in counts:
		if counts[target] > best_count:
			best_target = target
			best_count = counts[target]
			is_tie = false
		elif counts[target] == best_count:
			is_tie = true
	return SKIP_VOTE if is_tie else best_target
