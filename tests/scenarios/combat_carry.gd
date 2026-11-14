extends "res://tests/scenarios/combat_base.gd"
## Сценарий combat_carry: оружие и груз в руках (канистру выдаёт combat_carry_director.gd,
## как это делает в игре модуль заданий). Один бот проверяет:
## - с грузом атаковать нельзя, а Q его бросает;
## - оружие, взятое со стойки с грузом в руках, оказывается в руках, когда груз брошен,
##   и его ещё нужно достать;
## - сразу после выстрела груз в руки не идёт: оружие нельзя убрать раньше его паузы;
## - без обеих рук груз остаётся в руках (взаимодействие от рук не зависит), безрукий
##   может его бросить, пнуть и взять новый.

const STAND_AMMO: int = 30
const STAND_STOP_DISTANCE: float = 1.6
const BOTH_ARMS: int = (1 << BodyPart.Part.LEFT_ARM) | (1 << BodyPart.Part.RIGHT_ARM)
## Две руки по 40 здоровья: 2 * 40 * 0.6 из общего.
const HEALTH_AFTER_ARMS: int = 52


func _run() -> void:
	track_avatars()
	var my_id: int = Net.local_id()
	var pistol: WeaponConfig = ITEMS.get_item(PISTOL) as WeaponConfig
	var stand: WeaponPickup = map().get_interactables()[0] as WeaponPickup
	if not await expect(Game.is_playing, 6.0, "игра не началась после показа ролей"):
		return
	# Сервер дал груз: в руках канистра, это не оружие.
	if not await expect(func() -> bool: return me().held_item == CANISTER, 5.0, "бот не получил груз"):
		return
	if not check(me().weapons.get_held_weapon() == null and me().weapons.get_held_item().title == "Канистра",
			"в руках должна быть канистра"):
		return
	if not check(me().weapons.can_switch() and me().weapons.get_ammo() == WeaponLoadout.NO_AMMO_COUNTER,
			"с грузом Q должен работать (бросить), а счётчика патронов быть не должно"):
		return
	# С грузом атаковать нельзя.
	look_at_point(me().get_eye_position() + Vector3.BACK * 10.0)
	for attempt: int in 3:
		await click(&"fire")
	await wait_seconds(0.8)
	if not check(count_all_attacks(my_id) == 0, "бот атаковал с грузом в руках"):
		return
	# Пистолет со стойки с грузом в руках: оружие есть, но руки заняты.
	if not check(await walk_to(stand.global_position, STAND_STOP_DISTANCE, 8.0), "бот не дошёл до стойки"):
		return
	look_at_point(stand.get_focus_position())
	if not await expect(func() -> bool: return me().interactor.focus == stand, 2.0, "стойка не попала под прицел"):
		return
	await tap(&"interact")
	if not await expect(func() -> bool: return me().weapons.get_weapon_ammo(pistol) == STAND_AMMO, 3.0,
			"бот не получил пистолет со стойки"):
		return
	await wait_seconds(0.5)
	if not check(me().held_item == CANISTER and not stand.is_available(), "с грузом в руках пистолет не должен попасть в руки"):
		return
	# Q бросает груз — в руках оказывается подобранный пистолет. Его достают: выстрел в тот же
	# миг пропадает, а после времени доставания проходит.
	look_at_point(me().get_eye_position() + Vector3.BACK * 10.0)
	me().input.switch_weapon_pressed.emit()
	me().input.fire_pressed.emit()
	if not await expect(func() -> bool: return me().held_item == PISTOL, 3.0, "после броска груза в руках не пистолет"):
		return
	await wait_drawn()
	if not check(count_all_attacks(my_id) == 0 and me().weapons.get_weapon_ammo(pistol) == STAND_AMMO,
			"пистолет выстрелил в тот же миг, как оказался в руках"):
		return
	await click(&"fire")
	if not await expect(func() -> bool:
		# Патроны спрашиваем по оружию, а не по рукам: сервер вскоре снова даёт груз.
		return count_attacks(my_id, PISTOL, AttackEvent.Impact.NONE) == 1 and me().weapons.get_weapon_ammo(pistol) == STAND_AMMO - 1,
		3.0, "после броска груза пистолет не выстрелил"):
		return
	# Сервер снова даёт груз и отнимает обе руки: груз остаётся в руках.
	if not await expect(func() -> bool: return me().limbs_lost == BOTH_ARMS and me().body.health == HEALTH_AFTER_ARMS,
			15.0, "после потери рук: маска %d, здоровье %d" % [me().limbs_lost, me().body.health]):
		return
	await wait_seconds(0.6)
	if not check(held_history(my_id) == PackedInt32Array([CANISTER, PISTOL, CANISTER]) and me().held_item == CANISTER,
			"без рук груз должен остаться в руках: %s" % var_to_str(held_history(my_id))):
		return
	if not check(me().weapons.can_switch() and me().weapons.owns(pistol), "безрукий с грузом должен мочь его бросить, пистолет остаётся его"):
		return
	# С грузом по-прежнему не атакуют.
	await click(&"fire")
	await wait_seconds(0.6)
	if not check(count_all_attacks(my_id) == 1, "безрукий атаковал с грузом в руках"):
		return
	# Q бросает груз. Пистолет держать нечем: в руках «кулаки», Q и цифра 2 больше ничего не дают.
	await tap(&"switch_weapon")
	if not await expect(func() -> bool: return me().held_item == FISTS, 3.0, "безрукий не бросил груз клавишей Q"):
		return
	if not check(not me().weapons.can_switch(), "без рук и без груза Q делать нечего"):
		return
	await tap_slot(SLOT_PISTOL)
	await tap(&"switch_weapon")
	await wait_seconds(0.6)
	if not check(me().held_item == FISTS, "безрукий взял оружие в руки: %d" % me().held_item):
		return
	# Пинок без рук работает.
	await click(&"fire")
	if not await expect(func() -> bool: return count_attacks(my_id, FISTS) == 1, 3.0, "пинок без рук не состоялся"):
		return
	# Сервер даёт груз ещё раз: безрукий берёт его, как любой другой.
	if not await expect(func() -> bool:
		return held_history(my_id) == PackedInt32Array([CANISTER, PISTOL, CANISTER, FISTS, CANISTER]),
		10.0, "безрукий не получил новый груз: %s" % var_to_str(held_history(my_id))):
		return
	check(count_all_attacks(my_id) == 2 and bad_event_count() == 0, "лишние атаки: %d" % count_all_attacks(my_id))
