extends TestCase
## Правила матча: число предателей, раздача ролей, победа по числу живых, подсчёт голосов.

const PLAYERS_FOR_ONE: int = 3
const PLAYERS_FOR_TWO: int = 7
const SEED: int = 12345


func test_traitor_count_follows_config_thresholds() -> void:
	var config: GameConfig = _make_config()
	assert_eq(MatchRules.traitor_count(1, config), 0, "один игрок")
	assert_eq(MatchRules.traitor_count(2, config), 0, "два игрока")
	assert_eq(MatchRules.traitor_count(3, config), 1, "три игрока")
	assert_eq(MatchRules.traitor_count(6, config), 1, "шесть игроков")
	assert_eq(MatchRules.traitor_count(7, config), 2, "семь игроков")
	assert_eq(MatchRules.traitor_count(8, config), 2, "восемь игроков")


func test_deal_roles_gives_exact_number_of_traitors() -> void:
	var peer_ids: Array[int] = [11, 22, 33, 44, 55, 66, 77]
	for traitors: int in [0, 1, 2]:
		var roles: Dictionary[int, Game.Role] = MatchRules.deal_roles(peer_ids, traitors, [], _make_rng())
		assert_eq(roles.size(), peer_ids.size(), "роль получил каждый игрок")
		assert_eq(_count(roles, Game.Role.TRAITOR), traitors, "предателей при запросе %d" % traitors)
		assert_eq(_count(roles, Game.Role.CREW), peer_ids.size() - traitors, "экипажа при запросе %d" % traitors)


func test_deal_roles_never_gives_more_traitors_than_players() -> void:
	var peer_ids: Array[int] = [11, 22]
	var roles: Dictionary[int, Game.Role] = MatchRules.deal_roles(peer_ids, 5, [], _make_rng())
	assert_eq(_count(roles, Game.Role.TRAITOR), 2, "предателей не больше, чем игроков")
	var none: Dictionary[int, Game.Role] = MatchRules.deal_roles(peer_ids, -3, [], _make_rng())
	assert_eq(_count(none, Game.Role.TRAITOR), 0, "отрицательное число — без предателей")
	var empty: Array[int] = []
	assert_eq(MatchRules.deal_roles(empty, 1, [], _make_rng()).size(), 0, "без игроков ролей нет")


func test_deal_roles_makes_forced_players_traitors_first() -> void:
	var peer_ids: Array[int] = [11, 22, 33, 44]
	var forced: Array[int] = [33]
	for attempt: int in 20:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = attempt
		var roles: Dictionary[int, Game.Role] = MatchRules.deal_roles(peer_ids, 1, forced, rng)
		assert_eq(roles[33], Game.Role.TRAITOR, "назначенный игрок — предатель (попытка %d)" % attempt)
		assert_eq(_count(roles, Game.Role.TRAITOR), 1, "предатель ровно один (попытка %d)" % attempt)


func test_deal_roles_ignores_forced_players_outside_the_match() -> void:
	var peer_ids: Array[int] = [11, 22, 33]
	var forced: Array[int] = [99, 22, 22]
	var roles: Dictionary[int, Game.Role] = MatchRules.deal_roles(peer_ids, 1, forced, _make_rng())
	assert_true(not roles.has(99), "чужой игрок роль не получает")
	assert_eq(roles[22], Game.Role.TRAITOR, "назначенный участник — предатель")
	assert_eq(_count(roles, Game.Role.TRAITOR), 1, "повтор в списке не добавляет предателя")


func test_deal_roles_does_not_force_when_no_traitors_requested() -> void:
	var peer_ids: Array[int] = [11, 22, 33]
	var forced: Array[int] = [22]
	var roles: Dictionary[int, Game.Role] = MatchRules.deal_roles(peer_ids, 0, forced, _make_rng())
	assert_eq(_count(roles, Game.Role.TRAITOR), 0, "при нуле предателей назначенных нет")


func test_deal_roles_is_random_over_many_deals() -> void:
	var peer_ids: Array[int] = [11, 22, 33, 44, 55]
	var chosen: Dictionary[int, bool] = {}
	var rng: RandomNumberGenerator = _make_rng()
	for attempt: int in 200:
		var roles: Dictionary[int, Game.Role] = MatchRules.deal_roles(peer_ids, 1, [], rng)
		for peer_id: int in roles:
			if roles[peer_id] == Game.Role.TRAITOR:
				chosen[peer_id] = true
	assert_eq(chosen.size(), peer_ids.size(), "за 200 раздач предателем побывал каждый")


func test_headcount_winner() -> void:
	assert_eq(MatchRules.winner_by_headcount(1, 4, 1, 4), Game.Winner.NONE, "1 против 4 — игра идёт")
	assert_eq(MatchRules.winner_by_headcount(1, 2, 1, 4), Game.Winner.NONE, "1 против 2 — игра идёт")
	assert_eq(MatchRules.winner_by_headcount(1, 1, 1, 4), Game.Winner.TRAITORS, "1 против 1 — предатели")
	assert_eq(MatchRules.winner_by_headcount(2, 2, 2, 5), Game.Winner.TRAITORS, "2 против 2 — предатели")
	assert_eq(MatchRules.winner_by_headcount(2, 3, 2, 5), Game.Winner.NONE, "2 против 3 — игра идёт")
	assert_eq(MatchRules.winner_by_headcount(0, 3, 1, 4), Game.Winner.CREW, "предателей не осталось — экипаж")
	assert_eq(MatchRules.winner_by_headcount(0, 0, 1, 4), Game.Winner.CREW, "никого не осталось — экипаж")
	assert_eq(MatchRules.winner_by_headcount(1, 0, 1, 4), Game.Winner.TRAITORS, "экипажа не осталось — предатели")


func test_headcount_rule_is_off_without_both_sides_at_start() -> void:
	assert_eq(MatchRules.winner_by_headcount(0, 2, 0, 2), Game.Winner.NONE, "матч без предателей не кончается сам")
	assert_eq(MatchRules.winner_by_headcount(1, 0, 1, 0), Game.Winner.NONE, "матч без экипажа не кончается сам")
	assert_eq(MatchRules.winner_by_headcount(0, 0, 0, 0), Game.Winner.NONE, "пустой матч")


func test_tally_votes_ejects_strict_leader() -> void:
	var votes: Dictionary[int, int] = {1: 5, 2: 5, 3: 7, 4: MatchRules.SKIP_VOTE}
	assert_eq(MatchRules.tally_votes(votes), 5, "лидер по голосам изгнан")


func test_tally_votes_tie_ejects_nobody() -> void:
	var tie: Dictionary[int, int] = {1: 5, 2: 5, 3: 7, 4: 7}
	assert_eq(MatchRules.tally_votes(tie), MatchRules.SKIP_VOTE, "ничья между игроками")
	var tie_with_skip: Dictionary[int, int] = {1: 5, 2: MatchRules.SKIP_VOTE}
	assert_eq(MatchRules.tally_votes(tie_with_skip), MatchRules.SKIP_VOTE, "ничья с пропуском")
	var late_tie: Dictionary[int, int] = {1: 5, 2: 7, 3: 7, 4: 5, 5: 9}
	assert_eq(MatchRules.tally_votes(late_tie), MatchRules.SKIP_VOTE, "ничья лидеров при третьем кандидате")


func test_tally_votes_skip_majority_and_empty() -> void:
	var skipped: Dictionary[int, int] = {1: MatchRules.SKIP_VOTE, 2: MatchRules.SKIP_VOTE, 3: 5}
	assert_eq(MatchRules.tally_votes(skipped), MatchRules.SKIP_VOTE, "большинство за пропуск")
	var empty: Dictionary[int, int] = {}
	assert_eq(MatchRules.tally_votes(empty), MatchRules.SKIP_VOTE, "никто не голосовал")
	var single: Dictionary[int, int] = {1: 5}
	assert_eq(MatchRules.tally_votes(single), 5, "единственный голос решает")


func _make_config() -> GameConfig:
	var config: GameConfig = GameConfig.new()
	config.players_for_one_traitor = PLAYERS_FOR_ONE
	config.players_for_two_traitors = PLAYERS_FOR_TWO
	return config


func _make_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _count(roles: Dictionary[int, Game.Role], role: Game.Role) -> int:
	var count: int = 0
	for peer_id: int in roles:
		if roles[peer_id] == role:
			count += 1
	return count
