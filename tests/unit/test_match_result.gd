extends TestCase
## Итог матча: передача по сети и подсчёт победителей.


func test_rows_round_trip() -> void:
	var result: MatchResult = _make_result(Game.Winner.CREW, Game.EndReason.TASKS_DONE)
	var copy: MatchResult = MatchResult.from_rows(result.winner, result.reason, result.to_rows())
	assert_true(copy != null, "итог собрался из строк")
	if copy == null:
		return
	assert_eq(copy.winner, Game.Winner.CREW, "победитель")
	assert_eq(copy.reason, Game.EndReason.TASKS_DONE, "причина")
	assert_eq(copy.entries.size(), 3, "число строк")
	var traitor: MatchResult.Entry = copy.get_entry(22)
	assert_eq(traitor.name, "Боря", "имя")
	assert_eq(traitor.color_slot, 1, "цвет")
	assert_eq(traitor.role, Game.Role.TRAITOR, "роль")
	assert_eq(traitor.alive, false, "жив ли")
	assert_true(copy.get_entry(99) == null, "неизвестного игрока в итогах нет")


func test_did_win_depends_on_role() -> void:
	var crew_win: MatchResult = _make_result(Game.Winner.CREW, Game.EndReason.TRAITORS_ELIMINATED)
	assert_true(crew_win.did_win(11), "экипаж победил")
	assert_true(not crew_win.did_win(22), "предатель проиграл")
	assert_true(not crew_win.did_win(99), "зритель не побеждает")
	var traitor_win: MatchResult = _make_result(Game.Winner.TRAITORS, Game.EndReason.SABOTAGE)
	assert_true(traitor_win.did_win(22), "предатель победил")
	assert_true(not traitor_win.did_win(33), "экипаж проиграл, даже мёртвый")
	var nobody: MatchResult = _make_result(Game.Winner.NONE, Game.EndReason.NONE)
	assert_true(not nobody.did_win(11) and not nobody.did_win(22), "без победителя не побеждает никто")


func test_from_rows_rejects_broken_data() -> void:
	var good: Array = [[11, "Аня", 0, Game.Role.CREW, true]]
	assert_true(MatchResult.from_rows(Game.Winner.CREW, Game.EndReason.TASKS_DONE, good) != null, "верные данные")
	assert_true(MatchResult.from_rows(99, Game.EndReason.TASKS_DONE, good) == null, "неизвестный победитель")
	assert_true(MatchResult.from_rows(Game.Winner.CREW, -1, good) == null, "неизвестная причина")
	assert_true(MatchResult.from_rows(Game.Winner.CREW, Game.EndReason.TASKS_DONE, ["строка"]) == null, "строка не массив")
	assert_true(MatchResult.from_rows(Game.Winner.CREW, Game.EndReason.TASKS_DONE, [[11, "Аня", 0, Game.Role.CREW]]) == null,
			"короткая строка")
	assert_true(MatchResult.from_rows(Game.Winner.CREW, Game.EndReason.TASKS_DONE, [["11", "Аня", 0, Game.Role.CREW, true]]) == null,
			"id не число")
	assert_true(MatchResult.from_rows(Game.Winner.CREW, Game.EndReason.TASKS_DONE, [[11, "Аня", 0, 42, true]]) == null,
			"неизвестная роль")
	assert_true(MatchResult.from_rows(Game.Winner.CREW, Game.EndReason.TASKS_DONE, [[11, "Аня", 0, Game.Role.CREW, 1]]) == null,
			"флаг не bool")
	var too_many: Array = []
	for index: int in Net.MAX_PLAYERS + 1:
		too_many.append([index + 2, "Игрок", 0, Game.Role.CREW, true])
	assert_true(MatchResult.from_rows(Game.Winner.CREW, Game.EndReason.TASKS_DONE, too_many) == null, "слишком много строк")


func _make_result(winner: Game.Winner, reason: Game.EndReason) -> MatchResult:
	var result: MatchResult = MatchResult.new()
	result.winner = winner
	result.reason = reason
	result.add_entry(11, "Аня", 0, Game.Role.CREW, true)
	result.add_entry(22, "Боря", 1, Game.Role.TRAITOR, false)
	result.add_entry(33, "Вера", 2, Game.Role.CREW, false)
	return result
