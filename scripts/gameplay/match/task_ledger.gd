class_name TaskLedger
extends RefCounted
## Учёт заданий одного матча без сети и сцен: кому какая станция выдана, что сделано,
## кому достаётся работа выбывшего и чему равен общий прогресс экипажа.
## Чистая логика: её проверяют модульные тесты, а ведёт сервер (TaskBoard).
##
## У каждого участника свой список станций в порядке выдачи. В общий счёт идут только
## задания «считаемых» участников (экипажа): список предателя выглядит так же, но на
## прогресс не влияет. Выбывший участник сохраняет список, но выполнять его уже не может.

## Участники в порядке лобби: по нему решается, кому достанется работа при равенстве.
var _order: Array[int] = []
## peer_id -> станции участника в порядке выдачи.
var _tasks: Dictionary[int, PackedInt32Array] = {}
## peer_id -> станции, которые участник уже сделал.
var _done: Dictionary[int, PackedInt32Array] = {}
## Чьи задания идут в общий прогресс (экипаж).
var _counted: Dictionary[int, bool] = {}
## Кто ещё в игре: только они выполняют задания и получают чужую работу.
var _active: Dictionary[int, bool] = {}


## Забыть всё: матч закончился.
func clear() -> void:
	_order.clear()
	_tasks.clear()
	_done.clear()
	_counted.clear()
	_active.clear()


## Раздать задания на новый матч. Каждый из peer_ids (порядок лобби) получает per_player
## разных случайных станций из station_ids; если станций меньше — все станции.
## counted_ids — те, чьи задания идут в общий прогресс (экипаж); остальные получают
## фальшивый список. Повторы в списках игроков и станций не считаются.
func assign(peer_ids: Array[int], counted_ids: Array[int], station_ids: PackedInt32Array,
		per_player: int, rng: RandomNumberGenerator) -> void:
	clear()
	var stations: PackedInt32Array = []
	for station_id: int in station_ids:
		if not stations.has(station_id):
			stations.append(station_id)
	var count: int = clampi(per_player, 0, stations.size())
	for peer_id: int in peer_ids:
		if _tasks.has(peer_id):
			continue
		_order.append(peer_id)
		_tasks[peer_id] = _pick_random(stations, count, rng)
		_done[peer_id] = PackedInt32Array()
		_counted[peer_id] = counted_ids.has(peer_id)
		_active[peer_id] = true


## Есть ли у игрока список (участвует ли он в матче).
func has_peer(peer_id: int) -> bool:
	return _tasks.has(peer_id)


## Идут ли задания игрока в общий прогресс.
func is_counted(peer_id: int) -> bool:
	return _counted.has(peer_id) and _counted[peer_id]


## Ещё ли игрок в игре (не выбыл через remove()).
func is_active(peer_id: int) -> bool:
	return _active.has(peer_id) and _active[peer_id]


## Список станций игрока в порядке выдачи (копия). У чужого игрока — пустой.
func get_tasks(peer_id: int) -> PackedInt32Array:
	return _tasks[peer_id].duplicate() if _tasks.has(peer_id) else PackedInt32Array()


## Сделал ли игрок задание на этой станции.
func is_done(peer_id: int, station_id: int) -> bool:
	return _done.has(peer_id) and _done[peer_id].has(station_id)


## Ждёт ли это задание этого игрока: оно в его списке, не сделано, а сам он в игре.
func is_pending(peer_id: int, station_id: int) -> bool:
	return (is_active(peer_id) and _tasks[peer_id].has(station_id)
			and not _done[peer_id].has(station_id))


## Сколько заданий игроку осталось. У выбывшего и чужого — ноль.
func get_pending_count(peer_id: int) -> int:
	if not is_active(peer_id):
		return 0
	return _tasks[peer_id].size() - _done[peer_id].size()


## Игрок выполнил задание. true — оно засчитано; false — задание чужое, уже сделано
## или игрок выбыл (тогда ничего не меняется).
func complete(peer_id: int, station_id: int) -> bool:
	if not is_pending(peer_id, station_id):
		return false
	var done: PackedInt32Array = _done[peer_id]
	done.append(station_id)
	_done[peer_id] = done
	return true


## Игрок выбыл (убит, изгнан, вышел). Каждое несделанное задание члена экипажа достаётся
## живому члену экипажа, у которого этой станции нет ни в работе, ни среди сделанных:
## тому, у кого меньше всего осталось, при равенстве — первому по порядку лобби.
## Задание, которое взять некому, пропадает из общего счёта. Сделанное остаётся засчитанным.
## Возвращает тех, чей список вырос (по порядку лобби). Предатель и чужой игрок — пусто.
func remove(peer_id: int) -> Array[int]:
	var receivers: Array[int] = []
	if not is_active(peer_id):
		return receivers
	_active[peer_id] = false
	if not is_counted(peer_id):
		return receivers
	for station_id: int in _tasks[peer_id]:
		if _done[peer_id].has(station_id):
			continue
		var receiver: int = _find_receiver(station_id)
		if receiver == 0:
			continue
		var tasks: PackedInt32Array = _tasks[receiver]
		tasks.append(station_id)
		_tasks[receiver] = tasks
		if not receivers.has(receiver):
			receivers.append(receiver)
	receivers.sort_custom(func(a: int, b: int) -> bool: return _order.find(a) < _order.find(b))
	return receivers


## Сколько заданий нужно экипажу всего: списки живых плюс сделанное выбывшими.
func get_total_count() -> int:
	var total: int = 0
	for peer_id: int in _order:
		if not _counted[peer_id]:
			continue
		total += _tasks[peer_id].size() if _active[peer_id] else _done[peer_id].size()
	return total


## Сколько заданий экипаж уже сделал.
func get_done_count() -> int:
	var done: int = 0
	for peer_id: int in _order:
		if _counted[peer_id]:
			done += _done[peer_id].size()
	return done


## Кому отдать станцию выбывшего; 0 — некому.
func _find_receiver(station_id: int) -> int:
	var best: int = 0
	var best_pending: int = 0
	for peer_id: int in _order:
		if not _active[peer_id] or not _counted[peer_id] or _tasks[peer_id].has(station_id):
			continue
		var pending: int = get_pending_count(peer_id)
		# Строго меньше: при равенстве остаётся первый по порядку лобби.
		if best == 0 or pending < best_pending:
			best = peer_id
			best_pending = pending
	return best


## count случайных станций без повторов (частичная перетасовка Фишера — Йетса).
static func _pick_random(stations: PackedInt32Array, count: int,
		rng: RandomNumberGenerator) -> PackedInt32Array:
	var pool: PackedInt32Array = stations.duplicate()
	var picked: PackedInt32Array = []
	for index: int in count:
		var other: int = rng.randi_range(index, pool.size() - 1)
		var value: int = pool[other]
		pool[other] = pool[index]
		pool[index] = value
		picked.append(value)
	return picked
