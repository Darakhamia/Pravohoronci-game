extends TestCase
## Регистрация игрока: длинное имя не должно занимать сервер.


func test_raw_name_is_cut_before_sanitizing() -> void:
	var huge: String = "\t".repeat(200000) + "Ваня"
	var started_msec: int = Time.get_ticks_msec()
	var cleaned: String = PlayerName.sanitize(huge.left(Net.MAX_RAW_NAME_LENGTH))
	var spent_msec: int = Time.get_ticks_msec() - started_msec
	assert_eq(cleaned, PlayerName.FALLBACK, "имя из одних пробелов заменяется запасным")
	assert_true(spent_msec < 100, "разбор обрезанного имени занял %d мс" % spent_msec)
	assert_true(Net.MAX_RAW_NAME_LENGTH >= PlayerName.MAX_LENGTH, "обрезка не короче допустимого имени")
