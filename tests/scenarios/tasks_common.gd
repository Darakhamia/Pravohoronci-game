class_name TaskScenarioBot
extends ScenarioBot
## Общее для сценариев заданий и саботажа: подойти к предмету карты, навести на него
## прицел, удержать E — и то же самое «в обход клиента», как сделал бы изменённый клиент.

## На каком расстоянии перед предметом бот останавливается.
const FRONT_DISTANCE: float = 1.3
const STOP_DISTANCE: float = 0.3
const WALK_DEADLINE_SEC: float = 15.0
const FOCUS_DEADLINE_SEC: float = 4.0
## Сколько ждать, чтобы убедиться, что чего-то НЕ произошло.
const NOTHING_SEC: float = 0.7
## Аватар останавливается не сразу после отпускания клавиши.
const SETTLE_SEC: float = 0.3
const REPLY_DEADLINE_SEC: float = 5.0
## Пауза между выходом и повторным входом: сервер должен успеть заметить выход.
const REJOIN_PAUSE_SEC: float = 0.5

## Экран матча своего клиента: бот без окна, но HUD у него тот же, что у игрока.
const HUD_PATH: NodePath = ^"Main/UI/Hud"

## Бот сам вышел с сервера, чтобы зайти снова: обрыв сессии сейчас не провал.
var _is_rejoining: bool = false


## Подойти к предмету спереди (у моделей перёд — это -Z) и повернуться к нему.
func approach(target: Interactable) -> bool:
	var front: Vector3 = target.to_global(Vector3(0.0, 0.0, -FRONT_DISTANCE))
	if not check(await walk_to(front, STOP_DISTANCE, WALK_DEADLINE_SEC), "бот не дошёл до %s" % target.name):
		return false
	if not await wait_seconds(SETTLE_SEC):
		return false
	look_at_point(target.get_focus_position())
	return true


## Довести прицел до предмета: клиент должен предложить им воспользоваться.
func aim(target: Interactable) -> bool:
	return await expect(func() -> bool:
		look_at_point(target.get_focus_position())
		return me().interactor.focus == target,
		FOCUS_DEADLINE_SEC, "%s не попадает под прицел" % target.name)


## Смотрим на предмет NOTHING_SEC: клиент не должен предлагать им пользоваться.
## Прицел пересчитывается раз в физический тик, поэтому судим по концу ожидания.
func expect_no_focus(target: Interactable) -> bool:
	await wait_until(func() -> bool:
		look_at_point(target.get_focus_position())
		return false, NOTHING_SEC)
	return check(me().interactor.focus != target, "%s под прицелом, хотя пользоваться им нельзя" % target.name)


## Элемент HUD своего клиента по уникальному имени (^"%Prompt"): что видит игрок.
func hud_view(path: NodePath) -> Node:
	return get_tree().root.get_node(HUD_PATH).get_node(path)


## Подойти, навестись и зажать E. Клавишу отпускает вызывающий (release(&"interact")).
func approach_and_press(target: Interactable) -> bool:
	if not await approach(target) or not await aim(target):
		return false
	press(&"interact")
	return true


## «Изменённый клиент»: отправить серверу удержание E на предмете, который свой клиент
## не предлагает. Ждёт seconds и отпускает.
func force_hold(target: Interactable, seconds: float) -> bool:
	me().interactor.press_requested.emit(target.interact_id, true)
	var is_alive: bool = await wait_seconds(seconds)
	if me() != null:
		me().interactor.press_requested.emit(target.interact_id, false)
	return is_alive


## Выйти с сервера и зайти снова под тем же именем. Посреди матча бот возвращается
## зрителем: аватара и роли у него нет, а общее состояние матча сервер досылает.
func rejoin() -> bool:
	_release_all()
	_is_rejoining = true
	Net.leave()
	_is_rejoining = false
	if not await wait_seconds(REJOIN_PAUSE_SEC):
		return false
	var port: int = CmdArgs.get_int("--port", Net.DEFAULT_PORT, CmdArgs.MIN_PORT, CmdArgs.MAX_PORT)
	var error: Error = Net.join_server(SERVER_ADDRESS, port, bot_name)
	if not check(error == OK, "повторный Net.join_server вернул %s" % error_string(error)):
		return false
	if not await expect(Net.is_joined, CONNECT_DEADLINE_SEC, "сервер не пустил бота обратно"):
		return false
	return await expect(func() -> bool: return Game.state == Game.State.MATCH and world.current_map != null,
			AVATARS_DEADLINE_SEC, "вернувшийся бот не увидел идущий матч")


## Все предметы карты этого класса (по скрипту), в порядке номеров.
func find_by_script(script: Script) -> Array[Interactable]:
	var result: Array[Interactable] = []
	for candidate: Interactable in map().get_interactables():
		if is_instance_of(candidate, script):
			result.append(candidate)
	return result


## Дождаться итогов матча и сверить победителя и причину.
func expect_result(winner: Game.Winner, reason: Game.EndReason, timeout_sec: float) -> bool:
	if not await expect(func() -> bool: return Game.last_result != null, timeout_sec, "итоги матча не пришли"):
		return false
	var result: MatchResult = Game.last_result
	return check(result.winner == winner and result.reason == reason, "итог %s / %s, а ждали %s / %s" % [
			Game.Winner.find_key(result.winner), Game.EndReason.find_key(result.reason),
			Game.Winner.find_key(winner), Game.EndReason.find_key(reason)])


## Дождаться возврата в лобби после итогов.
func expect_lobby(timeout_sec: float) -> bool:
	return await expect(func() -> bool: return Game.state == Game.State.LOBBY and world.current_map == null,
			timeout_sec, "после итогов сервер не вернул игроков в лобби")


## ScenarioBot считает любой обрыв сессии провалом — кроме выхода ради повторного входа.
func _on_session_lost(reason: String) -> void:
	if not _is_rejoining:
		super._on_session_lost(reason)
