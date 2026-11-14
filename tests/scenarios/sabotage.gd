extends TaskScenarioBot
## Сценарий sabotage: Bot1 — предатель, Bot2 чинит реактор, Bot3 смотрит со стороны,
## Bot4 под конец выходит и заходит снова зрителем.
## 1) F у экипажа и F у предателя до конца первой паузы ничего не делают.
## 2) Саботаж: все видят отсчёт, Bot2 чинит реактор на пульте — все видят ended(true).
## 3) Во время паузы предатель включить саботаж не может; после неё включает второй —
##    его сбрасывает «собрание» (sabotage_director.gd): ended(false), матч продолжается.
## 4) Третий саботаж никто не чинит. Bot4 перезаходит и как опоздавший узнаёт об идущем
##    саботаже. Время выходит: победа предателей по причине SABOTAGE.
## Экипаж за весь матч ни разу не узнаёт паузу предателей (cooldown_left).
## Боты договариваются через то, что видно всем, — положение аватаров: предатель отходит
## от точки спавна, когда его пауза кончилась; Bot2 встаёт у пульта, когда готов чинить.
## Игроков четверо, чтобы выход Bot4 не закончил матч по числу живых.

const TRAITOR_NAME: String = "Bot1"
const CREW_NAME: String = "Bot2"
const FIXER: int = 2
const LATE_JOINER: int = 4
## Значения из sabotage.cfg.
const FIRST_DELAY_SEC: float = 4.0
const COUNTDOWN_SEC: float = 10.0
const COOLDOWN_SEC: float = 3.0
## Насколько показания таймеров могут отстать от настроек к моменту проверки.
const TIMER_SLACK_SEC: float = 4.0
const TRIGGER_DEADLINE_SEC: float = 6.0
const COOLDOWN_DEADLINE_SEC: float = 12.0
const OTHER_BOT_DEADLINE_SEC: float = 30.0
## Предатель отошёл от спавна дальше этого — его пауза кончилась.
const SIGNAL_DISTANCE: float = 2.0
const SIGNAL_WALK: float = 3.5
## Экипаж ближе этого к месту перед пультом — готов чинить.
const READY_DISTANCE: float = 1.0

var _panel: ReactorPanel = null
var _started_count: int = 0
var _ended: Array[bool] = []
var _cooldown_signals: int = 0
## Бот вернулся на сервер зрителем посреди третьего саботажа.
var _is_spectator: bool = false


func _run() -> void:
	var panels: Array[Interactable] = find_by_script(ReactorPanel)
	if not check(panels.size() == 1, "на карте пультов реактора: %d" % panels.size()):
		return
	_panel = panels[0] as ReactorPanel
	Game.sabotage.started.connect(func() -> void: _started_count += 1)
	Game.sabotage.ended.connect(func(fixed: bool) -> void: _ended.append(fixed))
	Game.sabotage.cooldown_changed.connect(func() -> void: _cooldown_signals += 1)
	if not await expect(func() -> bool: return Game.local_role != Game.Role.NONE, 4.0, "сервер не прислал роль"):
		return
	var is_traitor: bool = bot_name == TRAITOR_NAME
	if not check((Game.local_role == Game.Role.TRAITOR) == is_traitor, "роль %s" % Game.Role.find_key(Game.local_role)):
		return
	if not check(not Game.sabotage.active and not Game.sabotage.can_trigger(Net.local_id()),
			"до начала игры саботаж идёт или его можно включить"):
		return
	if is_traitor:
		if not await _play_traitor():
			return
	elif bot_number == FIXER:
		if not await _play_crew():
			return
	else:
		if not await _play_observer():
			return
	if not await expect_result(Game.Winner.TRAITORS, Game.EndReason.SABOTAGE, COUNTDOWN_SEC + TIMER_SLACK_SEC + 4.0):
		return
	if _is_spectator:
		# Зритель видел конец третьего саботажа уже после возвращения.
		if not check(not _ended.is_empty() and not _ended.back() and not Game.sabotage.active,
				"зритель не увидел, что саботаж закончился взрывом: %s" % [_ended]):
			return
	else:
		var expected_ended: Array[bool] = [true, false, false]
		if not check(_ended == expected_ended and _started_count == 3 and not Game.sabotage.active,
				"за матч саботаж начинался %d раз и кончался так: %s" % [_started_count, _ended]):
			return
	if not is_traitor and not _check_crew_knows_no_cooldown("в конце матча"):
		return
	if not await expect_lobby(10.0):
		return
	check(not Game.sabotage.active and Game.sabotage.seconds_left == 0.0 and Game.sabotage.cooldown_left == 0.0,
			"после матча саботаж не сброшен")


# --- Предатель ---


func _play_traitor() -> bool:
	var start: Vector3 = me().position
	# Первая пауза приходит только предателю и не идёт, пока показывают роли.
	if not await expect(func() -> bool: return Game.sabotage.cooldown_left > 0.0, 4.0,
			"предатель не получил первую паузу саботажа"):
		return false
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return false
	if not check(Game.sabotage.cooldown_left > FIRST_DELAY_SEC - TIMER_SLACK_SEC
			and Game.sabotage.cooldown_left <= FIRST_DELAY_SEC, "первая пауза %.2f с" % Game.sabotage.cooldown_left):
		return false
	step("F до конца первой паузы")
	if not await _press_during_cooldown("первой паузы"):
		return false
	if not await _wait_cooldown_over():
		return false
	# Знак экипажу: пауза кончилась, предатель уже мог бы включить саботаж.
	if not check(await walk_to(start + Vector3(0.0, 0.0, -SIGNAL_WALK), STOP_DISTANCE, WALK_DEADLINE_SEC),
			"предатель не отошёл от спавна"):
		return false
	step("ждём экипаж у пульта")
	var crew: Player = avatar_named(CREW_NAME)
	var ready_point: Vector3 = _panel.to_global(Vector3(0.0, 0.0, -FRONT_DISTANCE))
	if not await expect(func() -> bool:
			return Vector2(crew.position.x - ready_point.x, crew.position.z - ready_point.z).length() <= READY_DISTANCE,
			OTHER_BOT_DEADLINE_SEC, "экипаж не подошёл к пульту"):
		return false
	if not check(_started_count == 0 and not Game.sabotage.active, "саботаж начался без предателя"):
		return false
	step("первый саботаж")
	if not await _trigger(1):
		return false
	if not await expect(func() -> bool: return _ended.size() == 1, COUNTDOWN_SEC, "экипаж не починил реактор"):
		return false
	if not check(_ended[0] and not Game.sabotage.active and Game.last_result == null, "первый саботаж не починен"):
		return false
	# После саботажа пауза начинается заново.
	if not await expect(func() -> bool: return Game.sabotage.cooldown_left > 0.0, 3.0,
			"после саботажа предатель не получил паузу"):
		return false
	if not check(Game.sabotage.cooldown_left <= COOLDOWN_SEC, "пауза %.2f с" % Game.sabotage.cooldown_left):
		return false
	step("F во время паузы")
	if not await _press_during_cooldown("паузы после саботажа"):
		return false
	if not await _wait_cooldown_over():
		return false
	step("второй саботаж — его сбросит собрание")
	if not await _trigger(2):
		return false
	if not await expect(func() -> bool: return _ended.size() == 2, COUNTDOWN_SEC - 2.0,
			"собрание не сбросило саботаж"):
		return false
	if not check(not _ended[1] and not Game.sabotage.active and Game.last_result == null and Game.is_playing(),
			"после собрания: fixed=%s, матч закончился или игра не идёт" % _ended[1]):
		return false
	if not await expect(func() -> bool: return Game.sabotage.cooldown_left > 0.0, 3.0,
			"после сброса саботажа пауза не началась заново"):
		return false
	if not await _wait_cooldown_over():
		return false
	step("третий саботаж — никто не чинит")
	if not await _trigger(3):
		return false
	# Отсчёт идёт на клиенте сам, без сообщений сервера.
	var seconds_before: float = Game.sabotage.seconds_left
	if not await wait_seconds(1.5):
		return false
	return check(Game.sabotage.seconds_left < seconds_before - 1.0 and Game.sabotage.seconds_left > 0.0,
			"отсчёт не идёт: было %.2f, стало %.2f" % [seconds_before, Game.sabotage.seconds_left])


## Нажать F, пока идёт пауза: саботаж начаться не должен.
func _press_during_cooldown(what: String) -> bool:
	var started_before: int = _started_count
	if not check(not Game.sabotage.can_trigger(Net.local_id()), "во время %s клиент считает, что саботаж доступен" % what):
		return false
	await tap(&"sabotage")
	if not await wait_seconds(NOTHING_SEC):
		return false
	# Если машина так тормозит, что пауза успела кончиться, проверка ничего не доказывает.
	if not check(Game.sabotage.cooldown_left > 0.0, "бот не успел нажать F до конца %s" % what):
		return false
	return check(_started_count == started_before and not Game.sabotage.active, "саботаж включился во время %s" % what)


func _wait_cooldown_over() -> bool:
	var signals_before: int = _cooldown_signals
	if not await expect(func() -> bool: return Game.sabotage.cooldown_left <= 0.0, COOLDOWN_DEADLINE_SEC,
			"пауза саботажа не кончилась"):
		return false
	if not check(_cooldown_signals > signals_before, "о конце паузы не сообщил сигнал cooldown_changed"):
		return false
	return check(Game.sabotage.can_trigger(Net.local_id()), "после паузы клиент считает, что саботаж недоступен")


## Нажать F и убедиться, что саботаж номер number начался с полным отсчётом.
func _trigger(number: int) -> bool:
	await tap(&"sabotage")
	if not await expect(func() -> bool: return _started_count == number and Game.sabotage.active,
			TRIGGER_DEADLINE_SEC, "саботаж %d не начался по F предателя" % number):
		return false
	if not _check_countdown():
		return false
	return check(not Game.sabotage.can_trigger(Net.local_id()), "во время саботажа клиент предлагает включить ещё один")


# --- Экипаж ---


func _play_crew() -> bool:
	var traitor: Player = avatar_named(TRAITOR_NAME)
	var traitor_start: Vector3 = traitor.position
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return false
	if not _check_crew_knows_no_cooldown("в начале игры"):
		return false
	step("ждём, пока у предателя кончится пауза")
	if not await expect(func() -> bool: return traitor.position.distance_to(traitor_start) >= SIGNAL_DISTANCE,
			OTHER_BOT_DEADLINE_SEC, "предатель не подал знак, что пауза кончилась"):
		return false
	# Предатель уже мог бы включить саботаж — экипаж не может.
	step("F у экипажа")
	if not check(not Game.sabotage.can_trigger(Net.local_id()), "клиент экипажа считает, что саботаж доступен"):
		return false
	await tap(&"sabotage")
	Game.sabotage.request()
	if not await wait_seconds(NOTHING_SEC):
		return false
	if not check(_started_count == 0 and not Game.sabotage.active, "саботаж включился по F экипажа"):
		return false
	if not check(not _panel.is_marked(), "над пультом горит метка без саботажа"):
		return false
	# Подходим к пульту: это знак предателю, он включит саботаж, как только увидит нас рядом.
	if not await approach(_panel):
		return false
	if not await expect(func() -> bool: return _started_count == 1 and Game.sabotage.active,
			OTHER_BOT_DEADLINE_SEC, "экипаж не увидел начало саботажа"):
		return false
	if not _check_countdown() or not check(_panel.is_marked(), "над пультом не горит метка во время саботажа"):
		return false
	step("чиним реактор")
	if not await aim(_panel):
		return false
	press(&"interact")
	var is_fixed: bool = await expect(func() -> bool: return _ended.size() == 1,
			_panel.hold_seconds + REPLY_DEADLINE_SEC, "реактор не починен удержанием E")
	release(&"interact")
	if not is_fixed:
		return false
	if not check(_ended[0] and not Game.sabotage.active and Game.sabotage.seconds_left == 0.0
			and Game.last_result == null and not _panel.is_marked(), "после починки саботаж не закончился как починенный"):
		return false
	# Саботажа нет — пульт снова не работает, даже если клиент настаивает.
	if not await expect_no_focus(_panel):
		return false
	if not await force_hold(_panel, _panel.hold_seconds + NOTHING_SEC):
		return false
	if not check(_ended.count(true) == 1, "пульт «починил» реактор без саботажа"):
		return false
	if not _check_crew_knows_no_cooldown("после первого саботажа"):
		return false
	step("ждём второй саботаж и его сброс собранием")
	if not await expect(func() -> bool: return _ended.size() == 2, OTHER_BOT_DEADLINE_SEC,
			"экипаж не увидел конец второго саботажа"):
		return false
	if not check(_started_count == 2 and not _ended[1] and not Game.sabotage.active and Game.last_result == null
			and Game.is_playing(), "после собрания: саботажей %d, fixed=%s" % [_started_count, _ended[1]]):
		return false
	step("ждём третий саботаж и не чиним")
	if not await expect(func() -> bool: return _started_count == 3 and Game.sabotage.active,
			OTHER_BOT_DEADLINE_SEC, "экипаж не увидел третий саботаж"):
		return false
	return _check_countdown() and _check_crew_knows_no_cooldown("во время третьего саботажа")


# --- Наблюдатели ---


## Bot3 и Bot4 ничего не делают: посторонний член экипажа видит все три саботажа и
## ни разу не узнаёт паузу. Bot4 под конец перезаходит зрителем.
func _play_observer() -> bool:
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return false
	if not _check_crew_knows_no_cooldown("в начале игры"):
		return false
	if not await expect(func() -> bool: return _started_count == 1 and Game.sabotage.active,
			OTHER_BOT_DEADLINE_SEC * 2.0, "наблюдатель не увидел первый саботаж"):
		return false
	if not _check_countdown():
		return false
	if not await expect(func() -> bool: return _ended.size() == 1, COUNTDOWN_SEC, "наблюдатель не увидел починку"):
		return false
	if not check(_ended[0] and not Game.sabotage.active and Game.sabotage.seconds_left == 0.0,
			"наблюдатель: первый саботаж не починен"):
		return false
	if not await expect(func() -> bool: return _ended.size() == 2, OTHER_BOT_DEADLINE_SEC,
			"наблюдатель не увидел конец второго саботажа"):
		return false
	if not check(_started_count == 2 and not _ended[1] and Game.is_playing() and Game.last_result == null,
			"наблюдатель: второй саботаж не сброшен собранием"):
		return false
	if not await expect(func() -> bool: return _started_count == 3 and Game.sabotage.active,
			OTHER_BOT_DEADLINE_SEC, "наблюдатель не увидел третий саботаж"):
		return false
	if not _check_countdown() or not _check_crew_knows_no_cooldown("во время третьего саботажа"):
		return false
	if bot_number == LATE_JOINER:
		return await _rejoin_as_spectator()
	return true


## Вошедший посреди матча узнаёт об идущем саботаже и видит тот же отсчёт.
func _rejoin_as_spectator() -> bool:
	step("выходим и заходим снова зрителем")
	var seconds_before: float = Game.sabotage.seconds_left
	if not await rejoin():
		return false
	_is_spectator = true
	if not await expect(func() -> bool: return Game.sabotage.active, REPLY_DEADLINE_SEC,
			"опоздавший не узнал об идущем саботаже"):
		return false
	if not check(Game.sabotage.seconds_left > 0.0 and Game.sabotage.seconds_left < seconds_before,
			"у опоздавшего до взрыва %.2f с, а до выхода было %.2f" % [Game.sabotage.seconds_left, seconds_before]):
		return false
	if not check(Game.local_role == Game.Role.NONE and me() == null and not Game.sabotage.can_trigger(Net.local_id()),
			"у зрителя есть роль, аватар или доступ к саботажу"):
		return false
	var panels: Array[Interactable] = find_by_script(ReactorPanel)
	if not check(panels.size() == 1 and (panels[0] as ReactorPanel).is_marked(),
			"у опоздавшего над пультом не горит метка идущего саботажа"):
		return false
	return _check_crew_knows_no_cooldown("после возвращения зрителем")


## Экипажу пауза предателей не приходит ни числом, ни сигналом.
func _check_crew_knows_no_cooldown(moment: String) -> bool:
	return check(Game.sabotage.cooldown_left == 0.0 and _cooldown_signals == 0,
			"%s экипаж знает паузу саботажа: %.2f с, сигналов %d" % [
			moment, Game.sabotage.cooldown_left, _cooldown_signals])


## Оба: отсчёт только что начался с полного времени.
func _check_countdown() -> bool:
	return check(Game.sabotage.seconds_left <= COUNTDOWN_SEC
			and Game.sabotage.seconds_left > COUNTDOWN_SEC - TIMER_SLACK_SEC,
			"до взрыва %.2f с, а саботаж только начался" % Game.sabotage.seconds_left)
