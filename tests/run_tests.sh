#!/usr/bin/env bash
# Все проверки перед PR одной командой: импорт проекта, модульные тесты, дымовой тест.
#   GODOT=<путь к godot>   по умолчанию "godot" из PATH
# Останавливается на первом провале. Код выхода 0 — всё прошло, 1 — нет.
set -u

cd "$(dirname "$0")/.." || exit 1

GODOT="${GODOT:-godot}"
export GODOT
LOG_DIR="tests/.logs"
IMPORT_LOG="$LOG_DIR/import.log"
UNIT_LOG="$LOG_DIR/unit.log"
IMPORT_TIMEOUT_SEC=180
UNIT_TIMEOUT_SEC=60
LOG_TAIL_LINES=40

RUN_PID=""

# Если скрипт прервали, Godot не должен остаться висеть.
cleanup() {
	if [ -n "$RUN_PID" ] && kill -0 "$RUN_PID" 2>/dev/null; then
		kill "$RUN_PID" 2>/dev/null
		wait "$RUN_PID" 2>/dev/null
	fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

failed() {
	echo "TESTS: FAILED ($1)"
	exit 1
}

# run_godot <лог> <предел в секундах> <аргументы godot...>
# Пишет вывод в лог и возвращает код выхода Godot. Зависший процесс убивает:
# после ошибки разбора скрипта Godot сам не завершается.
run_godot() {
	local log="$1"
	local timeout_sec="$2"
	shift 2
	"$GODOT" "$@" >"$log" 2>&1 &
	RUN_PID=$!
	local waited_sec=0
	while kill -0 "$RUN_PID" 2>/dev/null; do
		if [ "$waited_sec" -ge "$timeout_sec" ]; then
			echo "TESTS: Godot не завершился за $timeout_sec с, останавливаем"
			kill "$RUN_PID" 2>/dev/null
			break
		fi
		sleep 1
		waited_sec=$((waited_sec + 1))
	done
	wait "$RUN_PID" 2>/dev/null
	local code=$?
	RUN_PID=""
	return "$code"
}

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "TESTS: не найден Godot (\"$GODOT\"). Укажи путь: GODOT=/путь/к/godot"
	failed "нет Godot"
fi

mkdir -p "$LOG_DIR"

# На свежем клоне без импорта нет кэша class_name, и скрипты не разбираются.
echo "TESTS: импорт проекта"
run_godot "$IMPORT_LOG" "$IMPORT_TIMEOUT_SEC" --headless --import
import_code=$?
if [ "$import_code" -ne 0 ] || grep -q "SCRIPT ERROR" "$IMPORT_LOG"; then
	grep -n -A 3 "SCRIPT ERROR" "$IMPORT_LOG"
	echo "TESTS: импорт завершился с кодом $import_code, полный лог: $IMPORT_LOG"
	failed "импорт проекта"
fi

echo "TESTS: модульные тесты"
run_godot "$UNIT_LOG" "$UNIT_TIMEOUT_SEC" --headless res://tests/unit/unit_tests.tscn
unit_code=$?
grep -E "^(FAIL|UNIT:)" "$UNIT_LOG"
# Ошибка скрипта обрывает тест посередине, и он выглядит пройденным: ловим её отдельно.
if [ "$unit_code" -ne 0 ] || grep -q "SCRIPT ERROR" "$UNIT_LOG" || ! grep -q "^UNIT:" "$UNIT_LOG"; then
	echo "----- $UNIT_LOG (последние $LOG_TAIL_LINES строк) -----"
	tail -n "$LOG_TAIL_LINES" "$UNIT_LOG"
	failed "модульные тесты"
fi

echo "TESTS: дымовой тест"
if ! bash tests/smoke/run_smoke.sh; then
	failed "дымовой тест"
fi

echo "TESTS: OK"
exit 0
