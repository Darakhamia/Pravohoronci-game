extends TestCase
## Правила собрания: кто и за кого может голосовать, досрочный конец голосования,
## голоса выбывшего, тревожная кнопка. Плюс то, что Meeting обещает HUD без сети.

const ANN: int = 11
const BOB: int = 22
const CAT: int = 33
const DAN: int = 44
## Не участник собрания: умер до него или зашёл зрителем.
const OUTSIDER: int = 99
const SKIP: int = MatchRules.SKIP_VOTE


func test_attendee_votes_once() -> void:
	var attendees: PackedInt32Array = _attendees()
	assert_true(MeetingRules.can_vote(ANN, attendees, _ids([]), _ids([])), "участник может голосовать")
	assert_true(not MeetingRules.can_vote(ANN, attendees, _ids([]), _ids([ANN])), "второй голос не принимается")
	assert_true(MeetingRules.can_vote(BOB, attendees, _ids([]), _ids([ANN])), "чужой голос не мешает")


func test_outsider_and_dropped_cannot_vote() -> void:
	var attendees: PackedInt32Array = _attendees()
	assert_true(not MeetingRules.can_vote(OUTSIDER, attendees, _ids([]), _ids([])), "не участник собрания не голосует")
	assert_true(not MeetingRules.can_vote(BOB, attendees, _ids([BOB]), _ids([])), "выбывший не голосует")
	assert_true(not MeetingRules.can_vote(ANN, PackedInt32Array(), _ids([]), _ids([])), "без участников голосовать некому")


func test_candidates_are_skip_and_present_attendees() -> void:
	var attendees: PackedInt32Array = _attendees()
	assert_true(MeetingRules.is_candidate(SKIP, attendees, _ids([])), "пропуск — всегда вариант")
	assert_true(MeetingRules.is_candidate(SKIP, PackedInt32Array(), _ids([])), "пропуск — вариант и без участников")
	assert_true(MeetingRules.is_candidate(CAT, attendees, _ids([])), "за участника можно")
	assert_true(not MeetingRules.is_candidate(OUTSIDER, attendees, _ids([])), "за не участника нельзя")
	assert_true(not MeetingRules.is_candidate(CAT, attendees, _ids([CAT])), "за выбывшего нельзя")
	assert_true(not MeetingRules.is_candidate(-ANN, attendees, _ids([])), "отрицательный id — не участник")


func test_vote_needs_valid_voter_and_valid_target() -> void:
	var attendees: PackedInt32Array = _attendees()
	assert_true(MeetingRules.is_vote_valid(ANN, BOB, attendees, _ids([]), _ids([])), "обычный голос")
	assert_true(MeetingRules.is_vote_valid(ANN, ANN, attendees, _ids([]), _ids([])), "за себя можно")
	assert_true(MeetingRules.is_vote_valid(ANN, SKIP, attendees, _ids([]), _ids([])), "пропуск")
	assert_true(not MeetingRules.is_vote_valid(ANN, OUTSIDER, attendees, _ids([]), _ids([])), "цель не на собрании")
	assert_true(not MeetingRules.is_vote_valid(OUTSIDER, ANN, attendees, _ids([]), _ids([])), "голосующий не на собрании")
	assert_true(not MeetingRules.is_vote_valid(ANN, BOB, attendees, _ids([]), _ids([ANN])), "уже голосовал")
	assert_true(not MeetingRules.is_vote_valid(ANN, BOB, attendees, _ids([BOB]), _ids([])), "цель выбыла")
	assert_true(not MeetingRules.is_vote_valid(ANN, SKIP, attendees, _ids([ANN]), _ids([])), "выбывший не может даже пропустить")


func test_everyone_voted_only_when_no_one_is_awaited() -> void:
	var attendees: PackedInt32Array = _attendees()
	assert_true(not MeetingRules.has_everyone_voted(attendees, _ids([]), _ids([])), "никто не голосовал")
	assert_true(not MeetingRules.has_everyone_voted(attendees, _ids([]), _ids([ANN, BOB, CAT])), "одного ещё ждём")
	assert_true(MeetingRules.has_everyone_voted(attendees, _ids([]), _ids([ANN, BOB, CAT, DAN])), "проголосовали все")


func test_everyone_voted_does_not_wait_for_dropped() -> void:
	var attendees: PackedInt32Array = _attendees()
	assert_true(MeetingRules.has_everyone_voted(attendees, _ids([DAN]), _ids([ANN, BOB, CAT])), "выбывшего не ждём")
	assert_true(not MeetingRules.has_everyone_voted(attendees, _ids([DAN]), _ids([ANN, BOB])), "оставшегося ждём")
	assert_true(MeetingRules.has_everyone_voted(attendees, _ids([ANN, BOB, CAT, DAN]), _ids([])), "выбыли все — ждать некого")
	assert_true(MeetingRules.has_everyone_voted(PackedInt32Array(), _ids([]), _ids([])), "пустое собрание — ждать некого")


func test_discard_removes_vote_of_leaver_and_votes_for_him() -> void:
	var ballots: Dictionary[int, int] = {ANN: BOB, BOB: CAT, CAT: BOB, DAN: SKIP}
	var kept: Dictionary[int, int] = MeetingRules.discard_votes_of(ballots, BOB)
	var expected: Dictionary[int, int] = {DAN: SKIP}
	assert_eq(kept, expected, "остался только голос, не связанный с выбывшим")
	assert_eq(ballots.size(), 4, "исходные голоса не тронуты")


func test_discard_keeps_everything_when_leaver_is_not_involved() -> void:
	var ballots: Dictionary[int, int] = {ANN: BOB, BOB: ANN, CAT: SKIP}
	assert_eq(MeetingRules.discard_votes_of(ballots, DAN), ballots, "голоса остальных на месте")
	var empty: Dictionary[int, int] = {}
	assert_eq(MeetingRules.discard_votes_of(empty, ANN), empty, "без голосов и убирать нечего")


func test_discard_keeps_skip_votes_and_self_vote_of_others() -> void:
	var ballots: Dictionary[int, int] = {ANN: SKIP, BOB: BOB, CAT: CAT}
	var kept: Dictionary[int, int] = MeetingRules.discard_votes_of(ballots, CAT)
	var expected: Dictionary[int, int] = {ANN: SKIP, BOB: BOB}
	assert_eq(kept, expected, "пропуск и чужой голос за себя остались")


func test_discarded_votes_change_the_verdict() -> void:
	# Двое за Боба, один за Энн. Боб вышел: остаётся один голос — за Энн, она и изгнана.
	var ballots: Dictionary[int, int] = {ANN: BOB, CAT: BOB, DAN: ANN}
	assert_eq(MatchRules.tally_votes(ballots), BOB, "до выхода лидирует Боб")
	assert_eq(MatchRules.tally_votes(MeetingRules.discard_votes_of(ballots, BOB)), ANN, "после выхода — Энн")
	# Вышел голосовавший за Энн: голоса за Боба остаются.
	assert_eq(MatchRules.tally_votes(MeetingRules.discard_votes_of(ballots, DAN)), BOB, "выход чужого избирателя лидера не меняет")
	# Вышла Кэт, её голос был решающим: теперь ничья.
	assert_eq(MatchRules.tally_votes(MeetingRules.discard_votes_of(ballots, CAT)), SKIP, "без решающего голоса — ничья")


func test_button_works_only_when_every_condition_holds() -> void:
	assert_true(MeetingRules.can_press_button(true, true, 1, 0.0, false), "всё в порядке — кнопка работает")
	assert_true(not MeetingRules.can_press_button(false, true, 1, 0.0, false), "не идёт игра")
	assert_true(not MeetingRules.can_press_button(true, false, 1, 0.0, false), "игрок мёртв")
	assert_true(not MeetingRules.can_press_button(true, true, 0, 0.0, false), "нажатия кончились")
	assert_true(not MeetingRules.can_press_button(true, true, -1, 0.0, false), "отрицательный остаток")
	assert_true(not MeetingRules.can_press_button(true, true, 1, 0.01, false), "пауза ещё идёт")
	assert_true(not MeetingRules.can_press_button(true, true, 1, 0.0, true), "идёт саботаж")
	assert_true(MeetingRules.can_press_button(true, true, 3, -0.5, false), "пауза давно прошла")


func test_meeting_is_idle_and_harmless_without_a_session() -> void:
	var meeting: Meeting = Meeting.new()
	assert_true(not meeting.is_active(), "нового собрания нет")
	assert_eq(meeting.stage, Meeting.Stage.NONE, "стадия NONE")
	assert_eq(meeting.local_vote, Meeting.NO_VOTE, "своего голоса нет")
	assert_eq(meeting.ejected_id, SKIP, "никто не изгнан")
	assert_true(not meeting.can_local_vote(), "без сессии голосовать нельзя")
	assert_true(not meeting.is_candidate(SKIP), "без собрания кандидатов нет")
	assert_true(not meeting.can_press_button(ANN), "без сессии кнопка не работает")
	assert_true(not meeting.server_call(ANN, Meeting.Reason.BUTTON), "не сервер собрание не созывает")
	# Без сессии запрос никуда не уходит и ничего не меняет.
	meeting.request_vote(ANN)
	assert_true(meeting.voted.is_empty(), "голосов нет")
	meeting.free()


func test_no_vote_marker_differs_from_any_real_vote() -> void:
	assert_true(Meeting.NO_VOTE != SKIP, "«не голосовал» — не то же, что пропуск")
	assert_true(Meeting.NO_VOTE < 0, "и не чей-то peer_id")


func _attendees() -> PackedInt32Array:
	return PackedInt32Array([ANN, BOB, CAT, DAN])


func _ids(ids: Array[int]) -> Dictionary[int, bool]:
	var result: Dictionary[int, bool] = {}
	for peer_id: int in ids:
		result[peer_id] = true
	return result
