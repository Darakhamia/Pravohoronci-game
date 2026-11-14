extends MeetingBot
## Сценарий meeting: собрание по найденному телу от начала до конца.
## Bot1 — предатель (флаг сервера). Bot2 убивает серверный помощник (meeting_director.gd).
## Bot3 подходит к телу и сообщает о нём. На собрании Bot3 и Bot4 голосуют за Bot1,
## Bot1 — за Bot3: предателя изгоняют, экипаж побеждает. Каждый бот проверяет, что видит он.
## Заодно — чего сервер делать не должен: принять голос во время обсуждения (Bot3),
## голос мёртвого (Bot2) и «сообщение о теле» живого игрока (Bot4).

const TRAITOR_NAME: String = "Bot1"
const VICTIM_NAME: String = "Bot2"
const REPORTER_NAME: String = "Bot3"
const LAST_VOTER_NAME: String = "Bot4"
const CORPSE_STOP_DISTANCE: float = 1.2
const CORPSE_PROMPT: String = "Сообщить о теле"
const DISCUSSION_SECONDS: float = 2.0
const VOTING_SECONDS: float = 8.0

## Что этот бот видел в момент вердикта.
var _traitor_life_at_verdict: Player.Life = Player.Life.GONE
var _phase_at_verdict: Game.Phase = Game.Phase.NONE
## Что этот бот видел в момент начала собрания.
var _seconds_at_started: float = -1.0
var _could_vote_at_started: bool = true


func _run() -> void:
	remember_ids()
	if not await expect(Game.is_playing, 10.0, "игра не началась после показа ролей"):
		return
	if not await expect(func() -> bool: return Game.meeting.button_uses_left == 1, 3.0,
			"участник не получил свой запас нажатий тревожной кнопки"):
		return
	if bot_name == LAST_VOTER_NAME:
		# Тело живого игрока — не тело: сервер не должен начать собрание.
		me().interactor.press_requested.emit(-id_of(TRAITOR_NAME), true)
	var victim: Player = avatar(id_of(VICTIM_NAME))
	if not await expect(func() -> bool: return victim.life == Player.Life.CORPSE, 10.0, "жертва не стала телом"):
		return
	if not check(started_count == 0, "собрание началось раньше, чем о теле сообщили"):
		return
	if bot_name == REPORTER_NAME and not await _report_body(victim):
		return
	if not await expect(func() -> bool: return started_count == 1, 20.0, "собрание не началось"):
		return
	if not await _check_meeting_start(victim):
		return
	if not await _vote():
		return
	if not await _check_verdict_and_ejection():
		return
	if not await expect(func() -> bool: return Game.state == Game.State.LOBBY and world.current_map == null,
			10.0, "после итогов сервер не вернул игроков в лобби"):
		return
	check_meeting_reset()


## Сразу по сигналу: Bot3 голосует ещё во время обсуждения. Если бы сервер принял этот
## голос, настоящий голос Bot3 уже не прошёл бы, и вердикт вышел бы другим.
func _meeting_started() -> void:
	_seconds_at_started = Game.meeting.stage_seconds_left
	_could_vote_at_started = Game.meeting.can_local_vote()
	if bot_name == REPORTER_NAME and Game.meeting.stage == Meeting.Stage.DISCUSSION:
		Game.meeting.request_vote(MatchRules.SKIP_VOTE)


func _meeting_verdict_ready() -> void:
	var traitor: Player = avatar(id_of(TRAITOR_NAME))
	_traitor_life_at_verdict = traitor.life if traitor != null else Player.Life.GONE
	_phase_at_verdict = Game.phase


## Bot3: дойти до тела, навести прицел и нажать E.
func _report_body(victim: Player) -> bool:
	if not check(await walk_to(victim.position, CORPSE_STOP_DISTANCE, 8.0), "бот не дошёл до тела"):
		return false
	if not await focus_on(victim.corpse, "тело"):
		return false
	if not check(victim.corpse.get_prompt(me()) == CORPSE_PROMPT, "подсказка у тела: %s" % victim.corpse.get_prompt(me())):
		return false
	step("сообщаю о теле")
	await tap(&"interact")
	return true


## Все: собрание по телу видно каждому, тело убрано, живые сидят.
func _check_meeting_start(victim: Player) -> bool:
	var meeting: Meeting = Game.meeting
	var attendee_ids: PackedInt32Array = all_ids()
	attendee_ids.remove_at(attendee_ids.find(id_of(VICTIM_NAME)))
	if not check_meeting_header(Meeting.Reason.BODY, REPORTER_NAME, VICTIM_NAME, attendee_ids):
		return false
	if not check(stage_at_started == Meeting.Stage.DISCUSSION, "собрание началось не с обсуждения: %s" % Meeting.Stage.find_key(stage_at_started)):
		return false
	if not check(_seconds_at_started > 0.0 and _seconds_at_started <= DISCUSSION_SECONDS,
			"таймер обсуждения в начале собрания показывал %.2f с" % _seconds_at_started):
		return false
	if not check(not _could_vote_at_started and voted_at_voting_start <= 0,
			"во время обсуждения бот уже мог голосовать или чей-то голос был принят"):
		return false
	if not await expect(func() -> bool: return victim.life == Player.Life.GONE, 5.0, "тело не убрали"):
		return false
	var is_victim: bool = bot_name == VICTIM_NAME
	if not check(meeting.is_candidate(id_of(TRAITOR_NAME)) and not meeting.is_candidate(id_of(VICTIM_NAME)),
			"кандидаты собрания определены неверно"):
		return false
	if is_victim:
		return check(find_own_seat() == null, "мёртвого посадили за стол")
	return await expect_seated()


## Все: голосуют по очереди Bot3 -> Bot4 -> Bot1, остальные видят, кто проголосовал.
func _vote() -> bool:
	var meeting: Meeting = Game.meeting
	if not await expect(func() -> bool: return meeting.stage == Meeting.Stage.VOTING, 10.0, "голосование не началось"):
		return false
	if not check(voted_at_voting_start == 0, "к началу голосования уже есть голоса: принят голос из обсуждения"):
		return false
	if not check(meeting.stage_seconds_left > 0.0 and meeting.stage_seconds_left <= VOTING_SECONDS,
			"таймер голосования показывает %.2f с" % meeting.stage_seconds_left):
		return false
	var is_victim: bool = bot_name == VICTIM_NAME
	if not check(meeting.can_local_vote() != is_victim, "право голоса определено неверно"):
		return false
	if is_victim:
		# Голос мёртвого: если бы его приняли, вышла бы ничья и никого бы не изгнали.
		meeting.request_vote(id_of(REPORTER_NAME))
	if not await _vote_in_turn(REPORTER_NAME, "", TRAITOR_NAME):
		return false
	if not await _vote_in_turn(LAST_VOTER_NAME, REPORTER_NAME, TRAITOR_NAME):
		return false
	return await _vote_in_turn(TRAITOR_NAME, LAST_VOTER_NAME, REPORTER_NAME)


## Игрок voter_name голосует за target_name после того, как проголосовал after_name.
## Все дожидаются его голоса и убеждаются, что видят только сам факт.
func _vote_in_turn(voter_name: String, after_name: String, target_name: String) -> bool:
	var meeting: Meeting = Game.meeting
	var voter_id: int = id_of(voter_name)
	if bot_name == voter_name:
		if not after_name.is_empty() and not await expect(
				func() -> bool: return meeting.voted.has(id_of(after_name)), 8.0,
				"не дождались голоса игрока %s" % after_name):
			return false
		if not check(meeting.can_local_vote(), "бот не может голосовать в свою очередь"):
			return false
		meeting.request_vote(id_of(target_name))
	if not await expect(func() -> bool: return meeting.voted.has(voter_id), 8.0,
			"не видно, что %s проголосовал" % voter_name):
		return false
	# Последний голос и вердикт приходят вместе: тогда тайну проверяет is_vote_leak_seen.
	if meeting.stage == Meeting.Stage.VOTING and not check(meeting.votes.is_empty(), "голоса раскрыты до вердикта"):
		return false
	if bot_name == voter_name:
		return check(meeting.local_vote == id_of(target_name) and not meeting.can_local_vote(),
				"свой голос не подтверждён: local_vote %d" % meeting.local_vote)
	return true


## Все: вердикт раскрывает голоса и роль предателя, после него предателя убирают,
## экипаж побеждает.
func _check_verdict_and_ejection() -> bool:
	var meeting: Meeting = Game.meeting
	if not await expect(func() -> bool: return verdict_count == 1, 10.0, "вердикт не пришёл"):
		return false
	var expected_votes: Dictionary[int, int] = {
		id_of(REPORTER_NAME): id_of(TRAITOR_NAME),
		id_of(LAST_VOTER_NAME): id_of(TRAITOR_NAME),
		id_of(TRAITOR_NAME): id_of(REPORTER_NAME),
	}
	var expected_voted: PackedInt32Array = [id_of(TRAITOR_NAME), id_of(REPORTER_NAME), id_of(LAST_VOTER_NAME)]
	if not check_verdict(expected_votes, expected_voted, TRAITOR_NAME, Game.Role.TRAITOR):
		return false
	if not check(_traitor_life_at_verdict == Player.Life.ALIVE and _phase_at_verdict == Game.Phase.MEETING,
			"в момент вердикта предатель уже убран или фаза не MEETING"):
		return false
	for voter_name: String in [TRAITOR_NAME, REPORTER_NAME, LAST_VOTER_NAME]:
		if not check(vote_cast_count(voter_name) == 1, "vote_cast про %s пришёл %d раз" % [voter_name, vote_cast_count(voter_name)]):
			return false
	if not check(vote_cast_count(VICTIM_NAME) == 0 and not is_vote_leak_seen, "принят голос мёртвого или голос вне голосования"):
		return false
	if not check(stages_seen == [Meeting.Stage.DISCUSSION, Meeting.Stage.VOTING, Meeting.Stage.VERDICT],
			"стадии собрания шли не по порядку: %s" % [stages_seen]):
		return false
	var traitor: Player = avatar(id_of(TRAITOR_NAME))
	if not await expect(func() -> bool: return traitor.life == Player.Life.GONE, 8.0, "изгнанного не убрали с карты"):
		return false
	if not await expect(func() -> bool: return Game.last_result != null, 5.0, "итоги матча не пришли"):
		return false
	var result: MatchResult = Game.last_result
	if not check(result.winner == Game.Winner.CREW and result.reason == Game.EndReason.TRAITORS_ELIMINATED,
			"итог %s / %s" % [Game.Winner.find_key(result.winner), Game.EndReason.find_key(result.reason)]):
		return false
	if not check(result.did_win(Net.local_id()) == (bot_name != TRAITOR_NAME), "победа посчитана не тому"):
		return false
	return check(not meeting.is_active() and closed_count == 1 and started_count == 1,
			"после изгнания собрание не закрыто ровно один раз: started %d, closed %d" % [started_count, closed_count])
