extends "res://tests/scenarios/combat_base.gd"
## Сценарий combat_knife: нож предателя и смена оружия.
## Bot1 — предатель. Проверяет на себе:
## - Q нож не достаёт; цифра 3 достаёт, цифра 2 без пистолета не делает ничего;
## - «вспышка ножа» не проходит: запросы «достать — ударить — убрать», отправленные разом,
##   сервер разбирает по порядку, и удара не случается — нож ещё не достали;
## - после удара нож не убрать ни цифрой, ни Q, пока не пройдёт его пауза;
## - с пистолетом Q ходит «кулаки — пистолет» и ножа не показывает, цифры берут любое своё
##   оружие напрямую, с ножа Q уводит на кулаки.
## Bot2 — экипаж, свидетель: стоит рядом, сам ножа достать не может и записывает всё, что
## видит в руках предателя; увиденное должно совпасть с тем, что тот делал.
## Точные сроки (время доставания, пауза после удара) сторожит по тикам сервера
## combat_director.gd; матч заканчивает сервер по знаку свидетеля (combat_finish_director.gd).

const TRAITOR_NAME: String = "Bot1"
const WITNESS_NAME: String = "Bot2"
const STAND_AMMO: int = 30
const STAND_STOP_DISTANCE: float = 1.6
## Сколько ждём событие или смену оружия, которых быть не должно.
const SILENCE_SEC: float = 0.8
## Что свидетель должен увидеть в руках предателя после «вспышки», по порядку.
const TRAITOR_HANDS: PackedInt32Array = [
	KNIFE, FISTS, PISTOL, FISTS, PISTOL, FISTS, KNIFE, FISTS, PISTOL, KNIFE, FISTS]

## Что бот видел в руках предателя в тот миг, когда пришло событие его атаки.
var _held_at_attack: int = -1


func _run() -> void:
	track_avatars()
	var traitor: Player = avatar_named(TRAITOR_NAME)
	traitor.event_received.connect(func(_kind: Player.Event, _data: Array) -> void:
		_held_at_attack = traitor.held_item)
	if not await expect(func() -> bool: return Game.local_role != Game.Role.NONE, 3.0, "сервер не прислал роль"):
		return
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	var played: bool = false
	if bot_name == TRAITOR_NAME:
		played = await _play_traitor()
	else:
		played = await _play_witness()
	if not played:
		return
	await expect_lobby(30.0)


# --- Bot1: предатель ---


func _play_traitor() -> bool:
	var my_id: int = Net.local_id()
	var weapons: PlayerWeapons = me().weapons
	var knife: WeaponConfig = ITEMS.get_item(KNIFE) as WeaponConfig
	if not await expect(func() -> bool: return weapons.owns(knife), 3.0, "предатель не получил нож"):
		return false
	# Q нож не достаёт; цифра 2 без пистолета не делает ничего.
	if not check(not weapons.can_switch(), "с кулаками и ножом Q должен быть недоступен"):
		return false
	await tap(&"switch_weapon")
	await tap_slot(SLOT_PISTOL)
	await wait_seconds(SILENCE_SEC)
	if not check(me().held_item == FISTS and held_history(my_id).is_empty(), "Q или цифра 2 сменили оружие предателя"):
		return false
	# «Вспышка ножа»: достать, ударить и убрать одним пакетом. Смотрим в пустоту — мимо всех.
	look_at_point(me().get_eye_position() + Vector3.BACK * 10.0)
	me().input.weapon_slot_pressed.emit(SLOT_KNIFE)
	me().input.fire_pressed.emit()
	me().input.weapon_slot_pressed.emit(SLOT_FISTS)
	await wait_seconds(SILENCE_SEC)
	if not check(count_all_attacks(my_id) == 0, "нож ударил в тот же миг, как его достали"):
		return false
	if not check(me().held_item == FISTS, "после «достать — ударить — убрать» в руках %d" % me().held_item):
		return false
	# Достать и ударить разом: нож остаётся в руке, удара нет.
	me().input.weapon_slot_pressed.emit(SLOT_KNIFE)
	me().input.fire_pressed.emit()
	if not await expect(func() -> bool: return me().held_item == KNIFE, REPLY_SEC, "цифра 3 не дала предателю нож"):
		return false
	if not check(weapons.can_switch(), "с ножом в руке Q должен его убирать"):
		return false
	await wait_drawn()
	if not check(count_all_attacks(my_id) == 0, "нож ударил раньше, чем его достали"):
		return false
	# Нож достали: удар проходит, а убрать нож сразу после него нельзя ни цифрой, ни Q.
	me().input.fire_pressed.emit()
	me().input.weapon_slot_pressed.emit(SLOT_FISTS)
	me().input.switch_weapon_pressed.emit()
	if not await expect(func() -> bool: return count_attacks(my_id, KNIFE, AttackEvent.Impact.NONE) == 1, REPLY_SEC,
			"удар ножом после доставания не состоялся"):
		return false
	await wait_seconds(0.4)
	if not check(me().held_item == KNIFE and held_history(my_id) == PackedInt32Array([KNIFE]),
			"нож убрали сразу после удара: %s" % var_to_str(held_history(my_id))):
		return false
	# Пауза ножа прошла (считаем от мига, когда увидели удар: сервер ударил не позже) — Q убирает.
	await wait_seconds(knife.attack_interval)
	if not await _switch_to(&"switch_weapon", FISTS, "Q не убрал нож после паузы"):
		return false
	if not await _take_pistol():
		return false
	# С пистолетом Q ходит «кулаки — пистолет»: убрать пистолет можно, не показав нож.
	if not check(weapons.can_switch(), "с пистолетом Q должен быть доступен"):
		return false
	if not await _switch_to(&"switch_weapon", FISTS, "Q не убрал пистолет"):
		return false
	if not await _switch_to(&"switch_weapon", PISTOL, "Q не вернул пистолет"):
		return false
	if not await _switch_to(&"switch_weapon", FISTS, "Q не убрал пистолет во второй раз"):
		return false
	# Цифры берут оружие напрямую; с ножа Q уводит на кулаки.
	if not await _switch_to(PlayerInput.WEAPON_SLOT_ACTIONS[SLOT_KNIFE - 1], KNIFE, "цифра 3 не достала нож"):
		return false
	if not await _switch_to(&"switch_weapon", FISTS, "Q с ножа не увёл на кулаки"):
		return false
	if not await _switch_to(PlayerInput.WEAPON_SLOT_ACTIONS[SLOT_PISTOL - 1], PISTOL, "цифра 2 не достала пистолет"):
		return false
	if not await _switch_to(PlayerInput.WEAPON_SLOT_ACTIONS[SLOT_KNIFE - 1], KNIFE, "цифра 3 не сменила пистолет на нож"):
		return false
	if not await _switch_to(PlayerInput.WEAPON_SLOT_ACTIONS[SLOT_FISTS - 1], FISTS, "цифра 1 не убрала нож"):
		return false
	# Та же клавиша второй раз ничего не меняет.
	await tap_slot(SLOT_FISTS)
	await wait_seconds(SILENCE_SEC)
	if not check(_after_flash(held_history(my_id)) == TRAITOR_HANDS, "руки предателя: %s" % var_to_str(held_history(my_id))):
		return false
	return check(count_all_attacks(my_id) == 1 and bad_event_count() == 0, "лишние атаки предателя: %d" % count_all_attacks(my_id))


## Нажать клавишу и дождаться предмета в руках.
func _switch_to(action: StringName, item_index: int, what: String) -> bool:
	await tap(action)
	if not await expect(func() -> bool: return me().held_item == item_index, REPLY_SEC,
			"%s: в руках %d" % [what, me().held_item]):
		return false
	# Свидетель должен успеть увидеть каждую смену отдельно.
	await wait_seconds(0.3)
	return true


func _take_pistol() -> bool:
	var stand: WeaponPickup = map().get_interactables()[0] as WeaponPickup
	if not check(await walk_to(stand.global_position, STAND_STOP_DISTANCE, 10.0), "предатель не дошёл до стойки"):
		return false
	look_at_point(stand.get_focus_position())
	if not await expect(func() -> bool: return me().interactor.focus == stand, 2.0, "стойка не попала под прицел"):
		return false
	await tap(&"interact")
	if not await expect(func() -> bool: return me().held_item == PISTOL and me().weapons.get_ammo() == STAND_AMMO, REPLY_SEC,
			"предатель не получил пистолет"):
		return false
	await wait_seconds(0.3)
	return true


# --- Bot2: свидетель ---


func _play_witness() -> bool:
	var traitor: Player = avatar_named(TRAITOR_NAME)
	var traitor_id: int = traitor.peer_id
	# Экипажу нож не достаётся ни цифрой, ни Q.
	await tap_slot(SLOT_KNIFE)
	await tap_slot(SLOT_PISTOL)
	await tap(&"switch_weapon")
	await wait_seconds(SILENCE_SEC)
	if not check(me().held_item == FISTS and held_history(Net.local_id()).is_empty(), "экипаж сменил оружие цифрой или Q"):
		return false
	if not check(not me().weapons.owns(ITEMS.get_item(KNIFE) as WeaponConfig), "у экипажа появился нож"):
		return false
	# Удар ножом: в этот миг нож уже виден в руке предателя.
	if not await expect(func() -> bool: return count_attacks(traitor_id, KNIFE) == 1, 40.0, "свидетель не увидел удар ножом"):
		return false
	if not check(_held_at_attack == KNIFE, "удар ножом пришёл, когда в руках предателя было %d" % _held_at_attack):
		return false
	# Всё, что предатель делал с оружием дальше, видно по порядку.
	if not await expect(func() -> bool: return _after_flash(held_history(traitor_id)) == TRAITOR_HANDS, 60.0,
			"руки предателя глазами свидетеля: %s" % var_to_str(held_history(traitor_id))):
		return false
	await wait_seconds(SILENCE_SEC)
	if not check(_after_flash(held_history(traitor_id)) == TRAITOR_HANDS and traitor.held_item == FISTS,
			"после конца сценария руки предателя изменились: %s" % var_to_str(held_history(traitor_id))):
		return false
	if not check(count_all_attacks(traitor_id) == 1 and bad_event_count() == 0, "свидетель видел лишние атаки: %d" % count_all_attacks(traitor_id)):
		return false
	if not check_no_private_leaks():
		return false
	signal_finish()
	return true


## История рук без «вспышки» в начале: «достать — убрать» в одном пакете сервер может
## разобрать в одном тике (тогда этого никто не видит) или в двух соседних.
func _after_flash(history: PackedInt32Array) -> PackedInt32Array:
	if history.size() >= 2 and history[0] == KNIFE and history[1] == FISTS and history.size() > TRAITOR_HANDS.size():
		return history.slice(2)
	return history
