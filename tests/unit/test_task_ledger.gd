extends TestCase
## Учёт заданий (TaskLedger): раздача, выполнение, общий счёт и «работа коллеги».

const SEED: int = 20240
const PER_PLAYER: int = 4
const STATIONS: PackedInt32Array = [1, 2, 3, 4, 5, 6, 7, 8]
const PLAYERS: Array[int] = [11, 22, 33, 44, 55]
## 22 — предатель.
const CREW: Array[int] = [11, 33, 44, 55]
const TRAITOR: int = 22
const OUTSIDER: int = 99


func test_assign_gives_every_player_the_requested_number_of_distinct_stations() -> void:
	var ledger: TaskLedger = _make_ledger()
	for peer_id: int in PLAYERS:
		var tasks: PackedInt32Array = ledger.get_tasks(peer_id)
		assert_eq(tasks.size(), PER_PLAYER, "заданий у игрока %d" % peer_id)
		assert_eq(_unique_count(tasks), PER_PLAYER, "задания игрока %d не повторяются" % peer_id)
		for station_id: int in tasks:
			assert_true(STATIONS.has(station_id), "станция %d есть на карте" % station_id)
			assert_true(ledger.is_pending(peer_id, station_id), "выданное задание ждёт игрока")
			assert_true(not ledger.is_done(peer_id, station_id), "выданное задание не сделано")
		assert_eq(ledger.get_pending_count(peer_id), PER_PLAYER, "осталось заданий у игрока %d" % peer_id)


func test_assign_with_few_stations_gives_everyone_all_of_them() -> void:
	var ledger: TaskLedger = TaskLedger.new()
	var stations: PackedInt32Array = [5, 9]
	ledger.assign(PLAYERS, CREW, stations, PER_PLAYER, _make_rng())
	for peer_id: int in PLAYERS:
		var tasks: PackedInt32Array = ledger.get_tasks(peer_id)
		tasks.sort()
		assert_eq(tasks, stations, "игрок %d получил все станции" % peer_id)
	assert_eq(ledger.get_total_count(), CREW.size() * stations.size(), "всего заданий экипажа")


func test_assign_without_stations_or_tasks_gives_nothing() -> void:
	var ledger: TaskLedger = TaskLedger.new()
	ledger.assign(PLAYERS, CREW, PackedInt32Array(), PER_PLAYER, _make_rng())
	assert_eq(ledger.get_tasks(11).size(), 0, "без станций заданий нет")
	assert_eq(ledger.get_total_count(), 0, "без станций общий счёт пуст")
	ledger.assign(PLAYERS, CREW, STATIONS, 0, _make_rng())
	assert_eq(ledger.get_tasks(11).size(), 0, "ноль заданий на игрока")
	ledger.assign(PLAYERS, CREW, STATIONS, -3, _make_rng())
	assert_eq(ledger.get_tasks(11).size(), 0, "отрицательное число заданий — ноль")
	assert_true(ledger.has_peer(11), "игрок без заданий всё равно участник")


func test_assign_ignores_duplicate_players_and_stations() -> void:
	var ledger: TaskLedger = TaskLedger.new()
	var players: Array[int] = [11, 22, 11]
	var crew: Array[int] = [11, 22]
	var stations: PackedInt32Array = [3, 3, 7, 3]
	ledger.assign(players, crew, stations, PER_PLAYER, _make_rng())
	assert_eq(ledger.get_tasks(11).size(), 2, "повтор станции не даёт второго задания")
	assert_eq(_unique_count(ledger.get_tasks(11)), 2, "станции в списке разные")
	assert_eq(ledger.get_total_count(), 4, "повтор игрока не добавляет заданий")


func test_assign_is_deterministic_for_the_same_seed() -> void:
	var first: TaskLedger = _make_ledger()
	var second: TaskLedger = _make_ledger()
	var is_same_as_other_seed: bool = true
	var other: TaskLedger = TaskLedger.new()
	var other_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	other_rng.seed = SEED + 1
	other.assign(PLAYERS, CREW, STATIONS, PER_PLAYER, other_rng)
	for peer_id: int in PLAYERS:
		assert_eq(first.get_tasks(peer_id), second.get_tasks(peer_id), "тот же seed — тот же список у %d" % peer_id)
		if first.get_tasks(peer_id) != other.get_tasks(peer_id):
			is_same_as_other_seed = false
	assert_true(not is_same_as_other_seed, "другой seed даёт другую раздачу")


func test_assign_uses_all_stations_over_many_deals() -> void:
	var seen: Dictionary[int, bool] = {}
	var first_stations: Dictionary[int, bool] = {}
	for attempt: int in 50:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = attempt
		var ledger: TaskLedger = TaskLedger.new()
		ledger.assign(PLAYERS, CREW, STATIONS, PER_PLAYER, rng)
		first_stations[ledger.get_tasks(11)[0]] = true
		for station_id: int in ledger.get_tasks(11):
			seen[station_id] = true
	assert_eq(seen.size(), STATIONS.size(), "за много раздач игроку попадается каждая станция")
	assert_eq(first_stations.size(), STATIONS.size(), "первой в списке бывает любая станция")


func test_assign_replaces_the_previous_match() -> void:
	var ledger: TaskLedger = _make_ledger()
	ledger.complete(11, ledger.get_tasks(11)[0])
	ledger.remove(33)
	var players: Array[int] = [77, 88]
	var crew: Array[int] = [77]
	ledger.assign(players, crew, STATIONS, 2, _make_rng())
	assert_true(not ledger.has_peer(11), "участников прошлого матча больше нет")
	assert_eq(ledger.get_total_count(), 2, "счёт начат заново")
	assert_eq(ledger.get_done_count(), 0, "сделанное прошлого матча забыто")


func test_totals_count_only_crew_tasks() -> void:
	var ledger: TaskLedger = _make_ledger()
	assert_eq(ledger.get_total_count(), CREW.size() * PER_PLAYER, "в общий счёт идут задания экипажа")
	assert_eq(ledger.get_done_count(), 0, "в начале ничего не сделано")
	assert_true(ledger.is_counted(11), "экипаж считается")
	assert_true(not ledger.is_counted(TRAITOR), "предатель не считается")
	assert_true(not ledger.is_counted(OUTSIDER), "чужой игрок не считается")


func test_traitor_list_looks_real_but_never_moves_progress() -> void:
	var ledger: TaskLedger = _make_ledger()
	var fake: PackedInt32Array = ledger.get_tasks(TRAITOR)
	assert_eq(fake.size(), PER_PLAYER, "у предателя такой же по размеру список")
	for station_id: int in fake:
		assert_true(ledger.is_pending(TRAITOR, station_id), "фальшивое задание ждёт предателя")
		assert_true(ledger.complete(TRAITOR, station_id), "предатель «выполняет» своё задание")
		assert_true(ledger.is_done(TRAITOR, station_id), "у предателя оно отмечено сделанным")
	assert_eq(ledger.get_pending_count(TRAITOR), 0, "фальшивый список закончился")
	assert_eq(ledger.get_done_count(), 0, "общий прогресс не сдвинулся")
	assert_eq(ledger.get_total_count(), CREW.size() * PER_PLAYER, "общее число заданий не изменилось")


func test_complete_counts_once() -> void:
	var ledger: TaskLedger = _make_ledger()
	var station_id: int = ledger.get_tasks(11)[1]
	assert_true(ledger.complete(11, station_id), "первое выполнение засчитано")
	assert_true(not ledger.complete(11, station_id), "повторное выполнение не засчитано")
	assert_eq(ledger.get_done_count(), 1, "сделано одно задание")
	assert_true(ledger.is_done(11, station_id), "задание отмечено сделанным")
	assert_true(not ledger.is_pending(11, station_id), "сделанное задание больше не ждёт")
	assert_eq(ledger.get_pending_count(11), PER_PLAYER - 1, "осталось на одно меньше")
	assert_eq(ledger.get_tasks(11).size(), PER_PLAYER, "сделанное остаётся в списке")


func test_complete_rejects_foreign_stations_and_unknown_players() -> void:
	var ledger: TaskLedger = _make_ledger()
	var foreign: int = _station_outside(ledger.get_tasks(11))
	assert_true(not ledger.complete(11, foreign), "станция не из списка игрока")
	assert_true(not ledger.complete(11, 12345), "станции нет на карте")
	assert_true(not ledger.complete(OUTSIDER, STATIONS[0]), "игрок не участвует в матче")
	assert_true(not ledger.is_pending(OUTSIDER, STATIONS[0]), "у чужого игрока заданий нет")
	assert_true(not ledger.is_done(OUTSIDER, STATIONS[0]), "чужой игрок ничего не сделал")
	assert_eq(ledger.get_tasks(OUTSIDER).size(), 0, "список чужого игрока пуст")
	assert_eq(ledger.get_pending_count(OUTSIDER), 0, "чужому игроку нечего делать")
	assert_eq(ledger.get_done_count(), 0, "отклонённые попытки прогресс не меняют")


func test_all_crew_tasks_done_reaches_the_total() -> void:
	var ledger: TaskLedger = _make_ledger()
	for peer_id: int in CREW:
		for station_id: int in ledger.get_tasks(peer_id):
			ledger.complete(peer_id, station_id)
	assert_eq(ledger.get_done_count(), ledger.get_total_count(), "экипаж сделал всё")
	assert_eq(ledger.get_done_count(), CREW.size() * PER_PLAYER, "сделано заданий")


func test_remove_hands_unfinished_tasks_to_living_crew_and_keeps_the_total() -> void:
	# Три станции на двоих по одной: у второго точно нет станции первого или наоборот.
	var ledger: TaskLedger = TaskLedger.new()
	var players: Array[int] = [11, 22, 33]
	var stations: PackedInt32Array = [1, 2, 3, 4, 5, 6, 7, 8, 9]
	ledger.assign(players, players, stations, 3, _make_rng())
	var dead_tasks: PackedInt32Array = ledger.get_tasks(11)
	var done_station: int = dead_tasks[0]
	ledger.complete(11, done_station)
	var total_before: int = ledger.get_total_count()
	var handed: Dictionary[int, int] = {}
	var expected_handed: int = 0
	for station_id: int in dead_tasks:
		if station_id == done_station:
			continue
		if not ledger.get_tasks(22).has(station_id) or not ledger.get_tasks(33).has(station_id):
			expected_handed += 1
	var sizes_before: Dictionary[int, int] = {22: ledger.get_tasks(22).size(), 33: ledger.get_tasks(33).size()}
	var receivers: Array[int] = ledger.remove(11)
	for peer_id: int in [22, 33]:
		handed[peer_id] = ledger.get_tasks(peer_id).size() - sizes_before[peer_id]
		assert_eq(receivers.has(peer_id), handed[peer_id] > 0, "в ответе те, чей список вырос (%d)" % peer_id)
		assert_eq(_unique_count(ledger.get_tasks(peer_id)), ledger.get_tasks(peer_id).size(),
				"в списке %d нет повторов" % peer_id)
	assert_eq(handed[22] + handed[33], expected_handed, "передано столько заданий, сколько можно было взять")
	assert_eq(ledger.get_total_count(), total_before - (2 - expected_handed), "пропали только те, что некому взять")
	assert_eq(ledger.get_done_count(), 1, "сделанное погибшим остаётся засчитанным")
	assert_eq(ledger.get_tasks(11), dead_tasks, "погибший видит свой список прежним")
	assert_true(ledger.is_done(11, done_station), "сделанное погибшим отмечено")


func test_remove_keeps_the_total_when_someone_can_take_every_task() -> void:
	var ledger: TaskLedger = TaskLedger.new()
	var players: Array[int] = [11, 22, 33]
	# У каждого по одной станции из трёх: игрок 11 получит x, и передача зависит от раздачи,
	# поэтому перебираем раздачи, пока у всех троих станции разные.
	var rng: RandomNumberGenerator = _make_rng()
	var stations: PackedInt32Array = [1, 2, 3]
	var is_found: bool = false
	for attempt: int in 200:
		ledger.assign(players, players, stations, 1, rng)
		var used: PackedInt32Array = [ledger.get_tasks(11)[0], ledger.get_tasks(22)[0], ledger.get_tasks(33)[0]]
		if _unique_count(used) == 3:
			is_found = true
			break
	assert_true(is_found, "нашлась раздача, где у всех разные станции")
	var station_id: int = ledger.get_tasks(11)[0]
	var receivers: Array[int] = ledger.remove(11)
	var expected: Array[int] = [22]
	assert_eq(receivers, expected, "при равенстве задание берёт первый по порядку лобби")
	assert_eq(ledger.get_total_count(), 3, "общее число заданий не изменилось")
	assert_true(ledger.is_pending(22, station_id), "задание погибшего ждёт нового хозяина")
	assert_eq(ledger.get_tasks(22).size(), 2, "оно добавлено в конец списка")
	assert_eq(ledger.get_tasks(22)[1], station_id, "новое задание — последнее в списке")
	assert_true(not ledger.is_pending(33, station_id), "второй живой его не получил")
	assert_true(ledger.complete(22, station_id), "новый хозяин может его выполнить")
	assert_eq(ledger.get_done_count(), 1, "работа коллеги идёт в общий прогресс")


func test_remove_prefers_the_player_with_fewest_pending_tasks() -> void:
	var ledger: TaskLedger = TaskLedger.new()
	var players: Array[int] = [11, 22, 33]
	var rng: RandomNumberGenerator = _make_rng()
	var stations: PackedInt32Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
	var station_id: int = 0
	# Нужна раздача, где первую станцию игрока 11 не имеют ни 22, ни 33.
	for attempt: int in 200:
		ledger.assign(players, players, stations, 2, rng)
		station_id = ledger.get_tasks(11)[0]
		if not ledger.get_tasks(22).has(station_id) and not ledger.get_tasks(33).has(station_id):
			break
		station_id = 0
	assert_true(station_id != 0, "нашлась подходящая раздача")
	# Второе задание погибшего уже сделано, а у 33 осталось меньше, чем у 22.
	ledger.complete(11, ledger.get_tasks(11)[1])
	ledger.complete(33, ledger.get_tasks(33)[0])
	var receivers: Array[int] = ledger.remove(11)
	var expected: Array[int] = [33]
	assert_eq(receivers, expected, "задание берёт тот, у кого меньше осталось")
	assert_true(ledger.is_pending(33, station_id), "задание у игрока 33")
	assert_true(not ledger.is_pending(22, station_id), "игрок 22 его не получил")


func test_remove_drops_tasks_nobody_can_take() -> void:
	var ledger: TaskLedger = TaskLedger.new()
	var players: Array[int] = [11, 22, 33]
	var stations: PackedInt32Array = [1, 2]
	# Станций меньше, чем заданий: у всех одинаковые списки, брать чужое некому.
	ledger.assign(players, players, stations, PER_PLAYER, _make_rng())
	ledger.complete(11, 1)
	ledger.complete(22, 2)
	assert_eq(ledger.get_total_count(), 6, "всего до гибели")
	var receivers: Array[int] = ledger.remove(11)
	assert_eq(receivers.size(), 0, "никто ничего не получил")
	assert_eq(ledger.get_total_count(), 5, "несделанное задание погибшего пропало из счёта")
	assert_eq(ledger.get_done_count(), 2, "сделанное остаётся засчитанным")
	assert_eq(ledger.get_tasks(22).size(), 2, "списки живых не изменились")
	# Уже сделанную станцию живому тоже не дают повторно.
	ledger.remove(22)
	assert_eq(ledger.get_total_count(), 4, "после второй гибели: 2 задания живого и 2 сделанных")
	ledger.complete(33, 1)
	ledger.complete(33, 2)
	assert_eq(ledger.get_done_count(), ledger.get_total_count(), "последний живой закрывает счёт")


func test_remove_of_the_last_crew_member_leaves_only_done_tasks() -> void:
	var ledger: TaskLedger = TaskLedger.new()
	var players: Array[int] = [11, TRAITOR]
	var crew: Array[int] = [11]
	ledger.assign(players, crew, STATIONS, PER_PLAYER, _make_rng())
	ledger.complete(11, ledger.get_tasks(11)[0])
	var receivers: Array[int] = ledger.remove(11)
	assert_eq(receivers.size(), 0, "предателю работа экипажа не достаётся")
	assert_eq(ledger.get_tasks(TRAITOR).size(), PER_PLAYER, "список предателя не вырос")
	assert_eq(ledger.get_total_count(), 1, "в счёте осталось только сделанное")
	assert_eq(ledger.get_done_count(), 1, "сделанное засчитано")


func test_remove_of_a_traitor_changes_nothing() -> void:
	var ledger: TaskLedger = _make_ledger()
	var lists_before: Dictionary[int, PackedInt32Array] = {}
	for peer_id: int in CREW:
		lists_before[peer_id] = ledger.get_tasks(peer_id)
	var total_before: int = ledger.get_total_count()
	var receivers: Array[int] = ledger.remove(TRAITOR)
	assert_eq(receivers.size(), 0, "задания предателя никому не достаются")
	assert_eq(ledger.get_total_count(), total_before, "общее число заданий прежнее")
	for peer_id: int in CREW:
		assert_eq(ledger.get_tasks(peer_id), lists_before[peer_id], "список игрока %d прежний" % peer_id)
	assert_true(not ledger.is_active(TRAITOR), "предатель выбыл")
	assert_true(not ledger.complete(TRAITOR, ledger.get_tasks(TRAITOR)[0]), "выбывший предатель заданий не делает")


func test_removed_player_keeps_the_list_but_cannot_complete_it() -> void:
	var ledger: TaskLedger = _make_ledger()
	var tasks: PackedInt32Array = ledger.get_tasks(33)
	ledger.complete(33, tasks[0])
	ledger.remove(33)
	assert_true(ledger.has_peer(33), "выбывший остаётся в учёте")
	assert_true(not ledger.is_active(33), "выбывший не в игре")
	assert_eq(ledger.get_tasks(33), tasks, "список выбывшего виден прежним")
	assert_true(ledger.is_done(33, tasks[0]), "его сделанное задание отмечено")
	assert_true(not ledger.is_pending(33, tasks[1]), "несделанное больше его не ждёт")
	assert_eq(ledger.get_pending_count(33), 0, "выбывшему нечего делать")
	var done_before: int = ledger.get_done_count()
	assert_true(not ledger.complete(33, tasks[1]), "выбывший задание не выполняет")
	assert_eq(ledger.get_done_count(), done_before, "прогресс не изменился")


func test_remove_twice_or_of_an_unknown_player_is_ignored() -> void:
	var ledger: TaskLedger = _make_ledger()
	ledger.remove(11)
	var total_after_first: int = ledger.get_total_count()
	var sizes: Dictionary[int, int] = {}
	for peer_id: int in PLAYERS:
		sizes[peer_id] = ledger.get_tasks(peer_id).size()
	assert_eq(ledger.remove(11).size(), 0, "повторное выбывание никому ничего не даёт")
	assert_eq(ledger.remove(OUTSIDER).size(), 0, "чужой игрок никому ничего не даёт")
	assert_eq(ledger.get_total_count(), total_after_first, "общее число заданий прежнее")
	for peer_id: int in PLAYERS:
		assert_eq(ledger.get_tasks(peer_id).size(), sizes[peer_id], "список игрока %d прежний" % peer_id)


func test_handed_tasks_move_again_when_the_receiver_goes_out() -> void:
	var ledger: TaskLedger = TaskLedger.new()
	var players: Array[int] = [11, 22, 33]
	var rng: RandomNumberGenerator = _make_rng()
	var stations: PackedInt32Array = [1, 2, 3]
	for attempt: int in 200:
		ledger.assign(players, players, stations, 1, rng)
		var used: PackedInt32Array = [ledger.get_tasks(11)[0], ledger.get_tasks(22)[0], ledger.get_tasks(33)[0]]
		if _unique_count(used) == 3:
			break
	ledger.remove(11)
	ledger.remove(22)
	assert_eq(ledger.get_tasks(33).size(), 3, "последний живой получил работу обоих")
	assert_eq(ledger.get_total_count(), 3, "общее число заданий не изменилось")
	assert_eq(ledger.get_pending_count(33), 3, "все три ждут последнего живого")


func test_clear_forgets_everything() -> void:
	var ledger: TaskLedger = _make_ledger()
	ledger.complete(11, ledger.get_tasks(11)[0])
	ledger.clear()
	assert_true(not ledger.has_peer(11), "участников нет")
	assert_eq(ledger.get_total_count(), 0, "общий счёт пуст")
	assert_eq(ledger.get_done_count(), 0, "сделанного нет")
	assert_true(not ledger.is_pending(11, STATIONS[0]), "заданий нет")


func _make_ledger() -> TaskLedger:
	var ledger: TaskLedger = TaskLedger.new()
	ledger.assign(PLAYERS, CREW, STATIONS, PER_PLAYER, _make_rng())
	return ledger


func _make_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _unique_count(values: PackedInt32Array) -> int:
	var unique: Dictionary[int, bool] = {}
	for value: int in values:
		unique[value] = true
	return unique.size()


## Станция карты, которой нет в этом списке.
func _station_outside(tasks: PackedInt32Array) -> int:
	for station_id: int in STATIONS:
		if not tasks.has(station_id):
			return station_id
	return 0
