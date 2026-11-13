extends TestCase
## Тексты матча (MatchText): время, повод собрания, вердикт, итог, потери. Чистые функции —
## проверяем формулировки, на которые опирается ведущий матча, и поведение на мусоре.


func test_time_rounds_up_and_never_goes_negative() -> void:
	assert_eq(MatchText.time(38.0), "0:38", "целые секунды")
	assert_eq(MatchText.time(37.2), "0:38", "доля секунды округляется вверх")
	assert_eq(MatchText.time(65.0), "1:05", "минуты")
	assert_eq(MatchText.time(600.0), "10:00", "десять минут")
	assert_eq(MatchText.time(0.0), "0:00", "ноль")
	assert_eq(MatchText.time(-4.0), "0:00", "отрицательное время")
	assert_eq(MatchText.time(NAN), "0:00", "не число")
	assert_eq(MatchText.whole_seconds(0.01), 1, "последняя секунда ещё идёт")


func test_task_title_adds_location_only_when_set() -> void:
	assert_eq(MatchText.task_title("Починить проводку", "Реактор"), "Починить проводку — Реактор",
			"название и место")
	assert_eq(MatchText.task_title("Починить проводку", ""), "Починить проводку", "без места")
	assert_eq(MatchText.task_title("", ""), MatchText.TASK_UNKNOWN, "станция неизвестна")
	assert_eq(MatchText.task_done("Починить проводку"), "Готово: Починить проводку", "уведомление о задании")
	assert_eq(MatchText.task_done(""), "Готово: Задание", "уведомление без названия")
	assert_eq(MatchText.cover_task_done("Починить проводку"), "Сделано для вида: Починить проводку",
			"уведомление предателю о фальшивом задании")
	assert_eq(MatchText.cover_task_done(""), "Сделано для вида: Задание", "уведомление предателю без названия")


func test_limb_messages() -> void:
	assert_eq(MatchText.limb_lost(BodyPart.Part.LEFT_LEG), "Потеряна левая нога", "левая нога")
	assert_eq(MatchText.limb_lost(BodyPart.Part.RIGHT_ARM), "Потеряна правая рука", "правая рука")
	assert_eq(MatchText.limb_lost(BodyPart.Part.HEAD), "", "голову потерять нельзя")
	var left_arm: int = BodyPart.bit(BodyPart.Part.LEFT_ARM)
	var both_legs: int = BodyPart.bit(BodyPart.Part.LEFT_LEG) | BodyPart.bit(BodyPart.Part.RIGHT_LEG)
	assert_eq(MatchText.limbs_lost(0, left_arm), PackedStringArray(["Потеряна левая рука"]), "одна новая потеря")
	assert_eq(MatchText.limbs_lost(left_arm, left_arm | both_legs),
			PackedStringArray(["Потеряна левая нога", "Потеряна правая нога"]), "старая потеря не повторяется")
	assert_eq(MatchText.limbs_lost(left_arm, left_arm), PackedStringArray(), "ничего не изменилось")
	assert_eq(MatchText.limbs_lost(left_arm, 0), PackedStringArray(), "новый раунд: конечности на месте")


func test_meeting_reason_is_gender_neutral() -> void:
	assert_eq(MatchText.meeting_title(Meeting.Reason.BUTTON), "Собрание", "заголовок по кнопке")
	assert_eq(MatchText.meeting_title(Meeting.Reason.BODY), "Найдено тело", "заголовок по телу")
	assert_eq(MatchText.meeting_subtitle(Meeting.Reason.BUTTON, "Ваня", ""), "Ваня жмёт тревожную кнопку",
			"кнопка")
	assert_eq(MatchText.meeting_subtitle(Meeting.Reason.BODY, "Джексон", "Мила"), "Тело: Мила. Сообщает Джексон.",
			"тело")
	assert_eq(MatchText.meeting_subtitle(Meeting.Reason.BODY, "Джексон", ""), "Сообщает Джексон.",
			"погибший уже вышел из игры")
	assert_eq(MatchText.meeting_subtitle(Meeting.Reason.BUTTON, "", ""), "Игрок жмёт тревожную кнопку",
			"созвавший уже вышел из игры")


func test_verdict() -> void:
	assert_eq(MatchText.verdict(false, "Ваня", Game.Role.TRAITOR), "Никого не изгнали.", "никого")
	assert_eq(MatchText.verdict(true, "Ваня", Game.Role.TRAITOR), "Ваня за бортом.\nЭто был предатель.",
			"изгнан предатель")
	assert_eq(MatchText.verdict(true, "Оля", Game.Role.CREW), "Оля за бортом.\nЭто был не предатель.",
			"изгнан член экипажа")
	assert_eq(MatchText.verdict(true, "Оля", Game.Role.NONE), "Оля за бортом.", "роль не раскрывается")
	assert_eq(MatchText.verdict(true, "", Game.Role.NONE), "Игрок за бортом.", "изгнанный уже вышел из игры")


func test_result_texts_cover_every_outcome() -> void:
	assert_eq(MatchText.winner_title(Game.Winner.CREW), "Победа экипажа", "победа экипажа")
	assert_eq(MatchText.winner_title(Game.Winner.TRAITORS), "Победа предателей", "победа предателей")
	for winner: Game.Winner in Game.Winner.values():
		assert_true(not MatchText.winner_title(winner).is_empty(), "заголовок для исхода %d" % winner)
	for reason: Game.EndReason in Game.EndReason.values():
		if reason != Game.EndReason.NONE:
			assert_true(not MatchText.end_reason(reason).is_empty(), "текст причины %d" % reason)
	assert_eq(MatchText.end_reason(Game.EndReason.NONE), "", "без причины — пусто")
	assert_eq(MatchText.end_reason(Game.EndReason.SABOTAGE), "Реактор взорвался.", "взрыв реактора")


func test_names() -> void:
	assert_eq(MatchText.player_name("Мила"), "Мила", "обычное имя")
	assert_eq(MatchText.player_name(""), MatchText.NAME_UNKNOWN, "игрок вышел")
	assert_eq(MatchText.join_names(PackedStringArray(["Мила", "", "Ваня"])), "Мила, Ваня", "пустые имена пропущены")
	assert_eq(MatchText.join_names(PackedStringArray()), "", "пустой список")
