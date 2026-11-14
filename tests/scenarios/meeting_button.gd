extends MeetingBot
## Сценарий meeting_button: тревожная кнопка и три собрания без предателей.
## Все боты появляются и сидят на собрании в пределах досягаемости кнопки.
## 1. Bot1 жмёт кнопку во время паузы (не работает), во время «саботажа», который держит
##    серверный помощник meeting_button_director.gd (не работает), и после него — собрание.
##    Bot1 и Bot2 пропускают, Bot3 не голосует: голосование идёт до тайм-аута, никого не
##    изгоняют, игра продолжается. Заодно: второй голос Bot2 и голос Bot3 за постороннего.
## 2. У Bot1 нажатий больше нет (ни подсказки, ни результата от запроса в обход неё).
##    Собрание созывает Bot2; Bot1 и Bot2 голосуют друг за друга — ничья, никого не изгоняют.
## 3. Собрание созывает Bot3, а хост посреди голосования завершает матч: собрание молча
##    закрывается у всех.

const FIRST_NAME: String = "Bot1"
const SECOND_NAME: String = "Bot2"
const THIRD_NAME: String = "Bot3"
const BUTTON_PROMPT: String = "Созвать собрание"
const USES_PER_PLAYER: int = 1
const COOLDOWN_SECONDS: float = 4.0
## Меньше этого остатка паузы запрос «во время паузы» слать поздно: под конец паузы
## серверный помощник включает саботаж, и отказ был бы уже не из-за паузы.
const MIN_COOLDOWN_FOR_CHECK: float = 2.0
## peer_id, которого нет ни у одного игрока.
const NOBODY_ID: int = 999999
const WALK_AWAY_SEC: float = 0.6
const MIN_WALK_DISTANCE: float = 1.0
const BUTTON_STOP_DISTANCE: float = 1.7
const SETTLE_SEC: float = 0.3


func _run() -> void:
	remember_ids()
	if not await expect(Game.is_playing, 10.0, "игра не началась после показа ролей"):
		return
	if not await expect(func() -> bool: return Game.meeting.button_uses_left == USES_PER_PLAYER, 3.0,
			"участник не получил свой запас нажатий тревожной кнопки"):
		return
	if not check(Game.meeting.button_cooldown_left > 0.0 and Game.meeting.button_cooldown_left <= COOLDOWN_SECONDS,
			"пауза кнопки в начале игры показывает %.2f с" % Game.meeting.button_cooldown_left):
		return
	if not await _play_first_meeting():
		return
	if not await _play_second_meeting():
		return
	if not await _play_aborted_meeting():
		return
	check_meeting_reset()


# --- Собрание 1: пауза, саботаж, пропуски и тайм-аут ---


func _play_first_meeting() -> bool:
	if bot_name == FIRST_NAME and not await _call_first_meeting():
		return false
	if not await expect(func() -> bool: return started_count == 1, 40.0, "первое собрание не началось"):
		return false
	if not check_meeting_header(Meeting.Reason.BUTTON, FIRST_NAME, "", all_ids()):
		return false
	if not check(stage_at_started == Meeting.Stage.VOTING, "нулевое обсуждение не пропущено: %s" % Meeting.Stage.find_key(stage_at_started)):
		return false
	if not await _check_uses_after_call(FIRST_NAME):
		return false
	if not await expect_seated():
		return false
	var meeting: Meeting = Game.meeting
	match bot_name:
		FIRST_NAME:
			meeting.request_vote(MatchRules.SKIP_VOTE)
		SECOND_NAME:
			meeting.request_vote(MatchRules.SKIP_VOTE)
			if not await expect(func() -> bool: return meeting.voted.has(Net.local_id()), 4.0, "свой пропуск не принят"):
				return false
			# Второй голос того же игрока: не должен ни засчитаться, ни заменить первый.
			meeting.request_vote(id_of(FIRST_NAME))
		THIRD_NAME:
			# Голоса за тех, кого на собрании нет: ни один не должен засчитаться.
			meeting.request_vote(NOBODY_ID)
			if not await check_frozen():
				return false
			meeting.request_vote(-id_of(FIRST_NAME))
	if not await expect(func() -> bool: return verdict_count == 1, 15.0, "вердикт первого собрания не пришёл"):
		return false
	var expected_votes: Dictionary[int, int] = {
		id_of(FIRST_NAME): MatchRules.SKIP_VOTE,
		id_of(SECOND_NAME): MatchRules.SKIP_VOTE,
	}
	if not check_verdict(expected_votes, [id_of(FIRST_NAME), id_of(SECOND_NAME)], "", Game.Role.NONE):
		return false
	if not check(vote_cast_count(FIRST_NAME) == 1 and vote_cast_count(SECOND_NAME) == 1 and vote_cast_count(THIRD_NAME) == 0,
			"vote_cast пришёл не по разу от Bot1 и Bot2"):
		return false
	var expected_local: int = Meeting.NO_VOTE if bot_name == THIRD_NAME else MatchRules.SKIP_VOTE
	if not check(meeting.local_vote == expected_local, "свой голос %d, а ожидался %d" % [meeting.local_vote, expected_local]):
		return false
	if not await _check_game_resumed(1):
		return false
	return await _walk_away_and_back()


## Bot1: кнопка не работает во время паузы и во время саботажа, потом срабатывает.
func _call_first_meeting() -> bool:
	var meeting: Meeting = Game.meeting
	var target: EmergencyButton = button()
	if not check(target != null and target.get_prompt(me()) == BUTTON_PROMPT, "на карте нет тревожной кнопки с подсказкой"):
		return false
	if not check(not meeting.can_press_button(Net.local_id()), "во время паузы кнопка считается доступной"):
		return false
	if not await check_no_prompt(target, "пауза кнопки"):
		return false
	if not check(meeting.button_cooldown_left > MIN_COOLDOWN_FOR_CHECK, "пауза кончается: запрос во время паузы не проверить"):
		return false
	step("запрос во время паузы")
	await force_press(target)
	if not check(started_count == 0, "кнопка сработала во время паузы"):
		return false
	if not await expect(func() -> bool: return meeting.button_cooldown_left <= 0.0, 10.0, "пауза кнопки не кончилась"):
		return false
	# О саботаже, который включил серверный помощник, клиент не знает: подсказка есть,
	# нажатие честное — отказать должен сервер.
	if not check(meeting.can_press_button(Net.local_id()), "после паузы кнопка недоступна"):
		return false
	if not await focus_on(target, "кнопка после паузы"):
		return false
	step("нажатие во время саботажа")
	await hold(&"interact", target.hold_seconds + HOLD_MARGIN_SEC)
	await wait_seconds(REJECT_WAIT_SEC)
	if not check(started_count == 0, "кнопка сработала во время саботажа"):
		return false
	# Знак серверному помощнику: саботаж можно снимать.
	await send_look_signal()
	step("нажатие после саботажа")
	return await press_until(target, func() -> bool: return started_count == 1, "кнопка после саботажа")


# --- Собрание 2: лимит нажатий и ничья ---


func _play_second_meeting() -> bool:
	var meeting: Meeting = Game.meeting
	if not await expect(func() -> bool: return meeting.button_cooldown_left <= 0.0, 12.0, "пауза после собрания не кончилась"):
		return false
	match bot_name:
		FIRST_NAME:
			if not await _check_no_uses_left():
				return false
		SECOND_NAME:
			# Ждём, пока Bot1 закончит свою попытку: иначе не понять, чей запрос сработал.
			if not await expect(func() -> bool: return has_look_signal(FIRST_NAME), 20.0, "Bot1 не подал знак"):
				return false
			step("созываю второе собрание")
			if not await press_until(button(), func() -> bool: return started_count == 2, "кнопка у Bot2"):
				return false
	if not await expect(func() -> bool: return started_count == 2, 40.0, "второе собрание не началось"):
		return false
	if not check_meeting_header(Meeting.Reason.BUTTON, SECOND_NAME, "", all_ids()):
		return false
	if not check(voted_at_voting_start == 0, "в новое собрание перешли голоса прошлого"):
		return false
	if not await _check_uses_after_call(SECOND_NAME):
		return false
	if not await expect_seated():
		return false
	match bot_name:
		FIRST_NAME:
			meeting.request_vote(id_of(SECOND_NAME))
		SECOND_NAME:
			meeting.request_vote(id_of(FIRST_NAME))
	if not await expect(func() -> bool: return verdict_count == 2, 15.0, "вердикт второго собрания не пришёл"):
		return false
	var expected_votes: Dictionary[int, int] = {
		id_of(FIRST_NAME): id_of(SECOND_NAME),
		id_of(SECOND_NAME): id_of(FIRST_NAME),
	}
	# Ничья: по голосу у двоих — никого не изгоняют.
	if not check_verdict(expected_votes, [id_of(FIRST_NAME), id_of(SECOND_NAME)], "", Game.Role.NONE):
		return false
	return await _check_game_resumed(2)


## Bot1: нажатия кончились — подсказки нет, запрос в обход неё ничего не даёт.
func _check_no_uses_left() -> bool:
	var meeting: Meeting = Game.meeting
	var target: EmergencyButton = button()
	if not check(meeting.button_uses_left == 0 and not meeting.can_press_button(Net.local_id()),
			"у Bot1 остались нажатия: %d" % meeting.button_uses_left):
		return false
	if not await check_no_prompt(target, "кнопка без нажатий"):
		return false
	step("запрос без нажатий")
	await force_press(target)
	if not check(started_count == 1 and not meeting.is_active(), "кнопка сработала у игрока без нажатий"):
		return false
	await send_look_signal()
	return true


# --- Собрание 3: матч прерван посреди голосования ---


func _play_aborted_meeting() -> bool:
	var meeting: Meeting = Game.meeting
	if not await expect(func() -> bool: return meeting.button_cooldown_left <= 0.0, 12.0, "пауза после второго собрания не кончилась"):
		return false
	if bot_name == THIRD_NAME:
		step("созываю третье собрание")
		if not await press_until(button(), func() -> bool: return started_count == 3, "кнопка у Bot3"):
			return false
	if not await expect(func() -> bool: return started_count == 3, 40.0, "третье собрание не началось"):
		return false
	if not check_meeting_header(Meeting.Reason.BUTTON, THIRD_NAME, "", all_ids()):
		return false
	if bot_name == FIRST_NAME:
		meeting.request_vote(MatchRules.SKIP_VOTE)
	# Счётчик, а не meeting.voted: конец матча может прийти следом и стереть список.
	if not await expect(func() -> bool: return vote_cast_count(FIRST_NAME) == 3, 4.0, "голос Bot1 в третьем собрании не виден"):
		return false
	if Net.is_local_host():
		step("хост завершает матч посреди голосования")
		Game.request_end_match()
	if not await expect(func() -> bool: return Game.state == Game.State.LOBBY and world.current_map == null,
			10.0, "сервер не вернул игроков в лобби"):
		return false
	return check(closed_count == 3 and verdict_count == 2 and not meeting.is_active(),
			"прерванное собрание не закрылось молча: closed %d, вердиктов %d" % [closed_count, verdict_count])


# --- Общее ---


## Созвавший потратил нажатие, остальные — нет. Это личное: каждый знает только про себя.
func _check_uses_after_call(caller_name: String) -> bool:
	var spent_names: PackedStringArray = [FIRST_NAME]
	if caller_name != FIRST_NAME:
		spent_names.append(SECOND_NAME)
	var expected: int = 0 if spent_names.has(bot_name) else USES_PER_PLAYER
	return await expect(func() -> bool: return Game.meeting.button_uses_left == expected, 3.0,
			"осталось нажатий %d, а ожидалось %d" % [Game.meeting.button_uses_left, expected])


## Собрание закрылось, никого не изгнали, игра идёт, кнопка снова на паузе.
func _check_game_resumed(meeting_number: int) -> bool:
	if not await expect(func() -> bool: return closed_count == meeting_number, 10.0, "собрание %d не закрылось" % meeting_number):
		return false
	if not await expect(Game.is_playing, 5.0, "после собрания игра не продолжилась"):
		return false
	if not check(not Game.meeting.is_active() and Game.meeting.stage_seconds_left <= 0.0, "собрание закрыто не до конца"):
		return false
	for peer_id: int in all_ids():
		if not check(avatar(peer_id) != null and avatar(peer_id).life == Player.Life.ALIVE,
				"после собрания без изгнания игрок %d не жив" % peer_id):
			return false
	return check(Game.meeting.button_cooldown_left > 0.0 and not Game.meeting.can_press_button(Net.local_id()),
			"после собрания кнопка не ушла на паузу")


## После собрания снова можно ходить: бот отходит от кнопки и возвращается к ней.
func _walk_away_and_back() -> bool:
	var target: EmergencyButton = button()
	var start: Vector3 = me().position
	var away: Vector3 = start - target.global_position
	look_at_point(me().get_eye_position() + Vector3(away.x, 0.0, away.z))
	await hold(&"move_forward", WALK_AWAY_SEC)
	await wait_seconds(SETTLE_SEC)
	if not check(me().position.distance_to(start) >= MIN_WALK_DISTANCE,
			"после собрания бот прошёл только %.2f м" % me().position.distance_to(start)):
		return false
	return check(await walk_to(target.global_position, BUTTON_STOP_DISTANCE, 8.0), "бот не вернулся к кнопке")
