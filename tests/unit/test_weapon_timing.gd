extends TestCase
## WeaponTiming: оружие достают, после атаки его нельзя убрать, общий запрет атак.
## Вместе это не даёт предателю достать нож, ударить и спрятать его за два тика сервера.

const TICKS_PER_SECOND: int = 60
const KNIFE: WeaponConfig = preload("res://resources/items/knife.tres")
const PISTOL: WeaponConfig = preload("res://resources/items/pistol.tres")
const FISTS: WeaponConfig = preload("res://resources/items/fists.tres")


func test_seconds_to_ticks_rounds_up() -> void:
	assert_eq(WeaponTiming.to_ticks(0.35, TICKS_PER_SECOND), 21, "0.35 с — ровно 21 тик, без лишнего из-за погрешности")
	assert_eq(WeaponTiming.to_ticks(0.5, TICKS_PER_SECOND), 30, "0.5 с")
	assert_eq(WeaponTiming.to_ticks(1.0, TICKS_PER_SECOND), 60, "1 с")
	assert_eq(WeaponTiming.to_ticks(0.01, TICKS_PER_SECOND), 1, "меньше тика — один тик")
	assert_eq(WeaponTiming.to_ticks(0.0, TICKS_PER_SECOND), 0, "ноль")
	assert_eq(WeaponTiming.to_ticks(-3.0, TICKS_PER_SECOND), 0, "отрицательное время — ноль")


func test_fresh_timing_allows_everything() -> void:
	var timing: WeaponTiming = WeaponTiming.new()
	assert_true(timing.can_attack(0) and timing.can_put_away(0), "в начале раунда можно всё")
	assert_eq(timing.get_lock_ticks_left(0), 0, "запрета нет")


func test_weapon_cannot_attack_until_drawn() -> void:
	var timing: WeaponTiming = WeaponTiming.new()
	var draw_ticks: int = WeaponTiming.to_ticks(KNIFE.draw_seconds, TICKS_PER_SECOND)
	assert_true(draw_ticks > 1, "нож достают дольше одного тика")
	timing.draw(100, draw_ticks)
	assert_true(not timing.can_attack(100), "в тот же тик, что достал, ударить нельзя")
	assert_true(not timing.can_attack(101), "и на следующий тик")
	assert_true(not timing.can_attack(100 + draw_ticks - 1), "за тик до конца — ещё нельзя")
	assert_true(timing.can_attack(100 + draw_ticks), "достал — можно бить")
	assert_true(timing.can_put_away(100), "оружие, которым не били, убирается сразу")


func test_weapon_cannot_be_put_away_right_after_an_attack() -> void:
	var timing: WeaponTiming = WeaponTiming.new()
	var interval_ticks: int = WeaponTiming.to_ticks(KNIFE.attack_interval, TICKS_PER_SECOND)
	timing.draw(0, WeaponTiming.to_ticks(KNIFE.draw_seconds, TICKS_PER_SECOND))
	var attack_tick: int = 200
	assert_true(timing.can_attack(attack_tick), "нож достали давно")
	timing.attack(attack_tick, interval_ticks)
	assert_true(not timing.can_put_away(attack_tick), "в тик удара нож не убрать")
	assert_true(not timing.can_put_away(attack_tick + 1), "и на следующий тик")
	assert_true(not timing.can_attack(attack_tick + 1), "вторая атака ждёт паузу оружия")
	assert_true(not timing.can_put_away(attack_tick + interval_ticks - 1), "за тик до конца паузы — ещё нельзя")
	assert_true(timing.can_put_away(attack_tick + interval_ticks), "пауза прошла — нож можно убрать")
	assert_true(timing.can_attack(attack_tick + interval_ticks), "и ударить снова")


## Сценарий из ревью: достать нож, ударить и убрать за два тика.
func test_knife_stays_visible_around_a_stab() -> void:
	var timing: WeaponTiming = WeaponTiming.new()
	var draw_ticks: int = WeaponTiming.to_ticks(KNIFE.draw_seconds, TICKS_PER_SECOND)
	var interval_ticks: int = WeaponTiming.to_ticks(KNIFE.attack_interval, TICKS_PER_SECOND)
	var drawn_tick: int = 1000
	timing.draw(drawn_tick, draw_ticks)
	var first_attack_tick: int = -1
	var put_away_tick: int = -1
	# Клиент каждый тик шлёт и атаку, и смену оружия: сервер выполняет, что уже можно.
	for tick: int in range(drawn_tick, drawn_tick + 1000):
		if first_attack_tick < 0:
			if timing.can_attack(tick):
				timing.attack(tick, interval_ticks)
				first_attack_tick = tick
		elif timing.can_put_away(tick):
			put_away_tick = tick
			break
	assert_eq(first_attack_tick - drawn_tick, draw_ticks, "удар — не раньше, чем нож достали")
	assert_eq(put_away_tick - first_attack_tick, interval_ticks, "спрятать — не раньше паузы после удара")
	assert_true(put_away_tick - drawn_tick >= TICKS_PER_SECOND, "нож был виден в руке не меньше секунды")


func test_new_weapon_starts_its_own_draw() -> void:
	var timing: WeaponTiming = WeaponTiming.new()
	timing.attack(10, WeaponTiming.to_ticks(KNIFE.attack_interval, TICKS_PER_SECOND))
	# Нож отняли силой (смерть рук, собрание): в руках кулаки, у них своё время.
	var fists_ticks: int = WeaponTiming.to_ticks(FISTS.draw_seconds, TICKS_PER_SECOND)
	timing.draw(12, fists_ticks)
	assert_true(not timing.can_attack(12 + fists_ticks - 1), "кулаки ещё заносят")
	assert_true(timing.can_attack(12 + fists_ticks), "пауза ножа кулакам не мешает")
	assert_true(timing.can_put_away(12), "новое оружие, которым не били, можно убрать")
	assert_true(WeaponTiming.to_ticks(PISTOL.draw_seconds, TICKS_PER_SECOND) > fists_ticks, "пистолет достают дольше кулаков")


func test_attack_lock_blocks_attacks_but_not_switching() -> void:
	var timing: WeaponTiming = WeaponTiming.new()
	var lock_ticks: int = WeaponTiming.to_ticks(5.0, TICKS_PER_SECOND)
	timing.lock_attacks(500, lock_ticks)
	assert_eq(timing.get_lock_ticks_left(500), lock_ticks, "запрет начался")
	assert_true(not timing.can_attack(500) and not timing.can_attack(500 + lock_ticks - 1), "пока идёт запрет, атаковать нельзя")
	assert_true(timing.can_put_away(500), "менять оружие запрет не мешает")
	# Нож достали во время запрета: готов он раньше, но бить всё равно нельзя.
	timing.draw(510, WeaponTiming.to_ticks(KNIFE.draw_seconds, TICKS_PER_SECOND))
	assert_true(not timing.can_attack(560), "нож достали, но запрет ещё идёт")
	assert_eq(timing.get_lock_ticks_left(560), lock_ticks - 60, "запрет убывает")
	assert_true(timing.can_attack(500 + lock_ticks), "запрет кончился — можно атаковать")
	assert_eq(timing.get_lock_ticks_left(500 + lock_ticks + 100), 0, "ниже нуля остаток не уходит")
	timing.reset()
	assert_true(timing.can_attack(0), "новый раунд снимает всё")
