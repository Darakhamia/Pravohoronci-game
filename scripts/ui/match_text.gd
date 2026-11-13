class_name MatchText
extends RefCounted
## Тексты матча: как показать время, повод собрания, вердикт, итог и потери игрока.
## Чистые функции без состояния: их вызывает MatchPresenter и проверяют модульные тесты.
## Формулировки не зависят от пола игрока: «за бортом», «сообщает», «победа», а не
## «изгнан», «нашёл», «победил».

const SECONDS_PER_MINUTE: int = 60
const TIME_FORMAT: String = "%d:%02d"
## Имя для игрока, которого уже нет в списке (вышел посреди матча).
const NAME_UNKNOWN: String = "Игрок"
const NAME_SEPARATOR: String = ", "

const KEY_INTERACT: String = "E"
const KEY_SABOTAGE: String = "F"
const ABILITY_SABOTAGE: String = "Саботаж"
const ALERT_REACTOR: String = "Реактор перегревается"

const BANNER_SPECTATOR: String = "Матч уже идёт. Ты войдёшь в следующем раунде."
const BANNER_GHOST: String = "Ты призрак. WASD — лететь, пробел — вверх."

const TASK_WITH_LOCATION: String = "%s — %s"
const TASK_UNKNOWN: String = "Задание"
const KEYPAD_TITLE: String = "Ввести код"

const TOAST_TASK_DONE: String = "Готово: %s"
const TOAST_WRONG_CODE: String = "Неверный код"
const TOAST_MISSED_ZONE: String = "Мимо зелёной зоны. Попробуй ещё раз."
const TOAST_TASK_FAILED: String = "Не получилось. Попробуй ещё раз."
const TOAST_NO_AMMO: String = "Нет патронов"
const LIMB_LOST: Dictionary[BodyPart.Part, String] = {
	BodyPart.Part.LEFT_ARM: "Потеряна левая рука",
	BodyPart.Part.RIGHT_ARM: "Потеряна правая рука",
	BodyPart.Part.LEFT_LEG: "Потеряна левая нога",
	BodyPart.Part.RIGHT_LEG: "Потеряна правая нога",
}

const MEETING_TITLE_BUTTON: String = "Собрание"
const MEETING_TITLE_BODY: String = "Найдено тело"
const MEETING_BUTTON: String = "%s жмёт тревожную кнопку"
const MEETING_BODY: String = "Тело: %s. Сообщает %s."
const MEETING_BODY_UNKNOWN: String = "Сообщает %s."

const VERDICT_NOBODY: String = "Никого не изгнали."
const VERDICT_EJECTED: String = "%s за бортом."
## Роль изгнанного — второй строкой: вердикт на экране собрания занимает до двух строк.
const VERDICT_WAS_TRAITOR: String = "\nЭто был предатель."
const VERDICT_WAS_CREW: String = "\nЭто был не предатель."

const WINNER_TITLE: Dictionary[Game.Winner, String] = {
	Game.Winner.NONE: "Матч окончен",
	Game.Winner.CREW: "Победа экипажа",
	Game.Winner.TRAITORS: "Победа предателей",
}
const END_REASON: Dictionary[Game.EndReason, String] = {
	Game.EndReason.NONE: "",
	Game.EndReason.TASKS_DONE: "Экипаж выполнил все задания.",
	Game.EndReason.TRAITORS_ELIMINATED: "Предателей не осталось.",
	Game.EndReason.CREW_OUTNUMBERED: "Экипажа осталось не больше, чем предателей.",
	Game.EndReason.SABOTAGE: "Реактор взорвался.",
}


## Время таймера: «0:38», «1:05». Доли секунды округляются вверх, отрицательное время — «0:00».
static func time(seconds_left: float) -> String:
	var seconds: int = whole_seconds(seconds_left)
	@warning_ignore("integer_division")
	return TIME_FORMAT % [seconds / SECONDS_PER_MINUTE, seconds % SECONDS_PER_MINUTE]


## Сколько целых секунд показывает таймер: по этому числу видно, пора ли обновлять надпись.
static func whole_seconds(seconds_left: float) -> int:
	if not is_finite(seconds_left):
		return 0
	return maxi(ceili(seconds_left), 0)


## Имя игрока для надписей; пустое (игрок вышел) заменяется на «Игрок».
static func player_name(raw_name: String) -> String:
	return NAME_UNKNOWN if raw_name.is_empty() else raw_name


## Строка задания в списке: «Починить проводку — Реактор»; без места — только название.
static func task_title(title: String, location: String) -> String:
	var shown_title: String = TASK_UNKNOWN if title.is_empty() else title
	return shown_title if location.is_empty() else TASK_WITH_LOCATION % [shown_title, location]


static func task_done(title: String) -> String:
	return TOAST_TASK_DONE % (TASK_UNKNOWN if title.is_empty() else title)


## Сообщение о потерянной конечности; для головы и торса — пустая строка.
static func limb_lost(part: BodyPart.Part) -> String:
	return LIMB_LOST[part] if LIMB_LOST.has(part) else ""


## Сообщения обо всех конечностях, которые есть в new_mask, но не было в old_mask.
static func limbs_lost(old_mask: int, new_mask: int) -> PackedStringArray:
	var messages: PackedStringArray = []
	for part: BodyPart.Part in BodyPart.LIMBS:
		if BodyPart.is_lost(new_mask, part) and not BodyPart.is_lost(old_mask, part):
			messages.append(limb_lost(part))
	return messages


static func meeting_title(reason: Meeting.Reason) -> String:
	return MEETING_TITLE_BODY if reason == Meeting.Reason.BODY else MEETING_TITLE_BUTTON


## Повод собрания одной строкой: кто нажал кнопку или чьё тело найдено и кто сообщает.
static func meeting_subtitle(reason: Meeting.Reason, caller_name: String, victim_name: String) -> String:
	var caller: String = player_name(caller_name)
	if reason != Meeting.Reason.BODY:
		return MEETING_BUTTON % caller
	if victim_name.is_empty():
		return MEETING_BODY_UNKNOWN % caller
	return MEETING_BODY % [victim_name, caller]


## Вердикт собрания. is_ejected == false — никого не изгнали; роль NONE — роль не раскрываем.
static func verdict(is_ejected: bool, ejected_name: String, ejected_role: Game.Role) -> String:
	if not is_ejected:
		return VERDICT_NOBODY
	var text: String = VERDICT_EJECTED % player_name(ejected_name)
	match ejected_role:
		Game.Role.TRAITOR:
			text += VERDICT_WAS_TRAITOR
		Game.Role.CREW:
			text += VERDICT_WAS_CREW
	return text


static func winner_title(winner: Game.Winner) -> String:
	return WINNER_TITLE[winner] if WINNER_TITLE.has(winner) else WINNER_TITLE[Game.Winner.NONE]


## Причина конца матча одной строкой; пустая, если причины нет.
static func end_reason(reason: Game.EndReason) -> String:
	return END_REASON[reason] if END_REASON.has(reason) else ""


## Имена через запятую; пустые (игрок вышел) пропускаются.
static func join_names(names: PackedStringArray) -> String:
	var known: PackedStringArray = []
	for item: String in names:
		if not item.is_empty():
			known.append(item)
	return NAME_SEPARATOR.join(known)
