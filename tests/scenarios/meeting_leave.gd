extends MeetingBot
## Сценарий meeting_leave: игроки выходят из игры посреди собрания и возвращаются зрителями.
## Bot1 созывает собрание кнопкой. Bot4 голосует за Bot1, Bot2 — за Bot4. Bot4 выходит:
## пропадает и его голос, и голос Bot2 за него (второго голоса Bot2 не получает).
## Bot4 возвращается зрителем и получает собрание как есть — в стадии голосования.
## Bot1 пропускает; Bot3, так и не проголосовав, выходит — ждать больше некого, и сервер
## сразу выносит вердикт. Bot3 возвращается уже во время вердикта и получает его целиком.
## В вердикте один голос (пропуск Bot1): никого не изгоняют, игра продолжается.

const CALLER_NAME: String = "Bot1"
const SECOND_NAME: String = "Bot2"
## Выходит, не проголосовав: его выход заканчивает голосование.
const QUIET_LEAVER_NAME: String = "Bot3"
## Голосует и выходит: его голос и голос за него пропадают.
const VOTED_LEAVER_NAME: String = "Bot4"

## Что вернувшийся бот увидел в момент, когда получил собрание.
var _snapshot_stage: Meeting.Stage = Meeting.Stage.NONE
var _snapshot_voted: PackedInt32Array = []
var _snapshot_dropped: PackedInt32Array = []
var _snapshot_votes_size: int = -1
var _snapshot_phase: Game.Phase = Game.Phase.NONE


func _run() -> void:
	remember_ids()
	var meeting: Meeting = Game.meeting
	if not await expect(Game.is_playing, 10.0, "игра не началась после показа ролей"):
		return
	if bot_name == CALLER_NAME:
		if not await expect(func() -> bool: return meeting.can_press_button(Net.local_id()), 10.0, "кнопка не стала доступной"):
			return
		if not await press_until(button(), func() -> bool: return started_count == 1, "кнопка у Bot1"):
			return
	if not await expect(func() -> bool: return started_count == 1, 30.0, "собрание не началось"):
		return
	if not check_meeting_header(Meeting.Reason.BUTTON, CALLER_NAME, "", all_ids()):
		return
	if not await expect(func() -> bool: return meeting.stage == Meeting.Stage.VOTING, 10.0, "голосование не началось"):
		return
	if not await _first_votes():
		return
	if not await _voted_leaver_leaves():
		return
	if not await _quiet_leaver_leaves():
		return
	if not await _check_verdict_and_resume():
		return
	if Net.is_local_host():
		await wait_seconds(1.0)
		step("хост завершает матч")
		Game.request_end_match()
	if not await expect(func() -> bool: return Game.state == Game.State.LOBBY and world.current_map == null,
			15.0, "сервер не вернул игроков в лобби"):
		return
	check_meeting_reset()


## Вернувшийся бот запоминает собрание таким, каким получил его от сервера.
func _meeting_started() -> void:
	_snapshot_stage = Game.meeting.stage
	_snapshot_voted = PackedInt32Array(Game.meeting.voted.keys())
	_snapshot_dropped = PackedInt32Array(Game.meeting.dropped.keys())
	_snapshot_votes_size = Game.meeting.votes.size()
	_snapshot_phase = Game.phase


## Bot4 голосует за Bot1, следом Bot2 — за Bot4. Все видят обоих проголосовавших.
func _first_votes() -> bool:
	var meeting: Meeting = Game.meeting
	if bot_name == VOTED_LEAVER_NAME:
		meeting.request_vote(id_of(CALLER_NAME))
	if not await expect(func() -> bool: return meeting.voted.has(id_of(VOTED_LEAVER_NAME)), 8.0, "голос Bot4 не виден"):
		return false
	if bot_name == SECOND_NAME:
		meeting.request_vote(id_of(VOTED_LEAVER_NAME))
	return await expect(func() -> bool: return vote_cast_count(SECOND_NAME) == 1, 8.0, "голос Bot2 не виден")


## Bot4 выходит и возвращается зрителем; остальные видят, что он выбыл из собрания.
func _voted_leaver_leaves() -> bool:
	var meeting: Meeting = Game.meeting
	var leaver_id: int = id_of(VOTED_LEAVER_NAME)
	if bot_name == VOTED_LEAVER_NAME:
		return await _leave_and_return(Meeting.Stage.VOTING, [id_of(SECOND_NAME)], [leaver_id])
	if not await expect(func() -> bool: return meeting.dropped.has(leaver_id), 15.0, "выход Bot4 из собрания не виден"):
		return false
	if not check(dropped_seen == [leaver_id], "сигналы attendee_dropped: %s" % [dropped_seen]):
		return false
	if not check(not meeting.voted.has(leaver_id) and meeting.voted.has(id_of(SECOND_NAME)) and meeting.voted.size() == 1,
			"после выхода Bot4 проголосовавшими числятся %s" % [meeting.voted.keys()]):
		return false
	if not check(not meeting.is_candidate(leaver_id) and meeting.is_candidate(id_of(CALLER_NAME))
			and meeting.is_candidate(MatchRules.SKIP_VOTE), "кандидаты после выхода Bot4 определены неверно"):
		return false
	if not check(meeting.stage == Meeting.Stage.VOTING and meeting.votes.is_empty(), "голосование не продолжается"):
		return false
	match bot_name:
		SECOND_NAME:
			# Голос за вышедшего пропал, но второго голоса за это не дают.
			if not check(not meeting.can_local_vote(), "Bot2 снова может голосовать"):
				return false
			meeting.request_vote(MatchRules.SKIP_VOTE)
		CALLER_NAME:
			# За вышедшего голосовать нельзя: голос не засчитывается и не тратится.
			meeting.request_vote(leaver_id)
			await wait_seconds(REJECT_WAIT_SEC)
			if not check(not meeting.voted.has(Net.local_id()) and meeting.can_local_vote(), "голос за вышедшего засчитан"):
				return false
	# Ждём, пока Bot4 вернётся: он должен получить собрание ещё в голосовании.
	return await expect(func() -> bool: return Net.players.size() == expected_players and not Net.players.has(leaver_id),
			20.0, "Bot4 не вернулся на сервер")


## Bot1 пропускает; Bot3 выходит, не проголосовав, — и голосование сразу заканчивается.
func _quiet_leaver_leaves() -> bool:
	var meeting: Meeting = Game.meeting
	if bot_name == CALLER_NAME:
		meeting.request_vote(MatchRules.SKIP_VOTE)
	if not await expect(func() -> bool: return vote_cast_count(CALLER_NAME) == 1, 10.0, "голос Bot1 не виден"):
		return false
	if bot_name == QUIET_LEAVER_NAME:
		if not check(meeting.stage == Meeting.Stage.VOTING and meeting.can_local_vote(), "Bot3 уже не может голосовать"):
			return false
		var dropped_ids: PackedInt32Array = [id_of(VOTED_LEAVER_NAME), id_of(QUIET_LEAVER_NAME)]
		return await _leave_and_return(Meeting.Stage.VERDICT, [id_of(SECOND_NAME), id_of(CALLER_NAME)], dropped_ids)
	return true


## Выйти, убедиться, что у вышедшего от собрания ничего не осталось, вернуться зрителем
## и сверить собрание, которое прислал сервер.
func _leave_and_return(expected_stage: Meeting.Stage, expected_voted: PackedInt32Array,
		expected_dropped: PackedInt32Array) -> bool:
	var meeting: Meeting = Game.meeting
	var closed_before: int = closed_count
	var started_before: int = started_count
	step("выхожу посреди собрания")
	if not await rejoin():
		return false
	if not check(closed_count == closed_before + 1, "у вышедшего игрока собрание не закрылось"):
		return false
	if not await expect(func() -> bool: return started_count == started_before + 1, 10.0, "вернувшийся не получил идущее собрание"):
		return false
	if not check(_snapshot_stage == expected_stage, "вернувшийся получил стадию %s" % Meeting.Stage.find_key(_snapshot_stage)):
		return false
	if not check(_sorted(_snapshot_voted) == _sorted(expected_voted), "вернувшийся получил проголосовавших %s" % _snapshot_voted):
		return false
	if not check(_sorted(_snapshot_dropped) == _sorted(expected_dropped), "вернувшийся получил выбывших %s" % _snapshot_dropped):
		return false
	var is_verdict: bool = expected_stage == Meeting.Stage.VERDICT
	if not check((_snapshot_votes_size > 0) == is_verdict, "вернувшийся получил %d раскрытых голосов" % _snapshot_votes_size):
		return false
	if not check(meeting.caller_id == id_of(CALLER_NAME) and meeting.reason == Meeting.Reason.BUTTON
			and meeting.attendees == all_ids(), "вернувшийся получил не тот заголовок собрания"):
		return false
	if not await expect(func() -> bool: return Game.phase == Game.Phase.MEETING and world.current_map != null, 5.0,
			"вернувшийся не получил фазу собрания и карту"):
		return false
	# Зритель: не участник, без аватара, не голосует и кнопку не жмёт.
	if not check(not Game.is_participant(Net.local_id()) and me() == null, "вернувшийся стал участником матча"):
		return false
	if not check(not meeting.can_local_vote() and not meeting.can_press_button(Net.local_id())
			and meeting.local_vote == Meeting.NO_VOTE, "зритель может голосовать или жать кнопку"):
		return false
	meeting.request_vote(id_of(CALLER_NAME))
	return true


## Все: в вердикте один голос, вышедших и связанных с ними голосов нет; игра продолжается.
func _check_verdict_and_resume() -> bool:
	var meeting: Meeting = Game.meeting
	if not await expect(func() -> bool: return verdict_count == 1, 20.0, "вердикт не пришёл"):
		return false
	var expected_votes: Dictionary[int, int] = {id_of(CALLER_NAME): MatchRules.SKIP_VOTE}
	if not check_verdict(expected_votes, [id_of(CALLER_NAME), id_of(SECOND_NAME)], "", Game.Role.NONE):
		return false
	var dropped_ids: PackedInt32Array = [id_of(VOTED_LEAVER_NAME), id_of(QUIET_LEAVER_NAME)]
	if not check(_sorted(PackedInt32Array(meeting.dropped.keys())) == _sorted(dropped_ids), "выбывшие: %s" % [meeting.dropped.keys()]):
		return false
	if not check(vote_cast_count(QUIET_LEAVER_NAME) == 0 and vote_cast_count(SECOND_NAME) <= 1 and vote_cast_count(CALLER_NAME) <= 1,
			"засчитан лишний голос"):
		return false
	if not await expect(func() -> bool: return not meeting.is_active() and Game.is_playing(), 15.0,
			"после вердикта игра не продолжилась"):
		return false
	for player_name: String in [CALLER_NAME, SECOND_NAME]:
		var player: Player = avatar(id_of(player_name))
		if not check(player != null and player.life == Player.Life.ALIVE, "%s после собрания не жив" % player_name):
			return false
	for player_name: String in [QUIET_LEAVER_NAME, VOTED_LEAVER_NAME]:
		if not check(avatar(id_of(player_name)) == null, "аватар вышедшего %s остался на карте" % player_name):
			return false
	return true


func _sorted(values: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = values.duplicate()
	result.sort()
	return result
