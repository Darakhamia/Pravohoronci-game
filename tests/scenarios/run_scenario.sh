#!/usr/bin/env bash
# Сценарный тест: выделенный сервер и несколько ботов-клиентов играют по сценарию.
#   tests/scenarios/run_scenario.sh <имя>
# Сценарий — пара файлов рядом: <имя>.gd (бот, наследник ScenarioBot) и <имя>.cfg:
#   PLAYERS=3                       сколько ботов (Bot1..BotN)
#   SERVER_ARGS="--traitors=1 ..."  флаги сервера (см. server/dedicated_server.gd)
#   TIMEOUT_SEC=60                  предел на весь прогон
#   GODOT=<путь к godot>     по умолчанию "godot" из PATH
#   SCENARIO_PORT=<порт>     по умолчанию 17790
set -u

GODOT="${GODOT:-godot}"
# Относительный путь к Godot считаем от папки, откуда запустили скрипт, а не от корня проекта.
case "$GODOT" in
	*/*)
		godot_dir="$(cd "$(dirname "$GODOT")" 2>/dev/null && pwd)"
		if [ -n "$godot_dir" ]; then
			GODOT="$godot_dir/$(basename "$GODOT")"
		fi
		;;
esac

cd "$(dirname "$0")/../.." || exit 1
NAME="${1:-}"
CONFIG="tests/scenarios/$NAME.cfg"
if [ -z "$NAME" ] || [ ! -f "$CONFIG" ]; then
	echo "SCENARIO: нет файла $CONFIG. Запуск: tests/scenarios/run_scenario.sh <имя>"
	exit 1
fi

PLAYERS=2
SERVER_ARGS=""
TIMEOUT_SEC=60
# shellcheck disable=SC1090
. "$CONFIG"

PORT="${SCENARIO_PORT:-17790}"
LOG_DIR="tests/.logs"
SERVER_LOG="$LOG_DIR/scenario_${NAME}_server.log"
BOT_SCENE="res://tests/scenarios/scenario_bot.tscn"
SERVER_READY_TIMEOUT_SEC=10
# Сверх предела самих ботов — на запуск движка.
START_MARGIN_SEC=20
LOG_TAIL_LINES=40
# Ошибки скриптов и движка в логах Godot.
ERROR_PATTERN='SCRIPT ERROR|^ERROR:'

SERVER_PID=""
BOT_PIDS=()
BOT_LOGS=()
FAILED=0

is_running() {
	[ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

stop_process() {
	if is_running "$1"; then
		kill "$1" 2>/dev/null
	fi
	if [ -n "$1" ]; then
		wait "$1" 2>/dev/null
	fi
}

# Сервер и боты не должны пережить тест, чем бы он ни кончился.
cleanup() {
	for pid in "${BOT_PIDS[@]:-}"; do
		stop_process "$pid"
	done
	stop_process "$SERVER_PID"
	BOT_PIDS=()
	SERVER_PID=""
}
trap cleanup EXIT
trap 'exit 130' INT TERM

fail() {
	echo "SCENARIO $NAME: $1"
	FAILED=1
}

finish() {
	cleanup
	for log in "$SERVER_LOG" "${BOT_LOGS[@]:-}"; do
		if [ -f "$log" ] && grep -n -E "$ERROR_PATTERN" "$log" >/dev/null; then
			fail "ошибки в $log:"
			grep -n -E "$ERROR_PATTERN" "$log"
		fi
	done
	if [ "$FAILED" -ne 0 ]; then
		for log in "$SERVER_LOG" "${BOT_LOGS[@]:-}"; do
			if [ -f "$log" ]; then
				echo "----- $log (последние $LOG_TAIL_LINES строк) -----"
				tail -n "$LOG_TAIL_LINES" "$log"
			fi
		done
		echo "SCENARIO $NAME: FAILED"
		exit 1
	fi
	echo "SCENARIO $NAME: OK"
	exit 0
}

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "SCENARIO: не найден Godot (\"$GODOT\"). Укажи путь: GODOT=/путь/к/godot"
	exit 1
fi

mkdir -p "$LOG_DIR"
rm -f "$SERVER_LOG"

echo "SCENARIO $NAME: сервер на порту $PORT, ботов: $PLAYERS"
# SERVER_ARGS намеренно без кавычек: это список флагов.
# shellcheck disable=SC2086
"$GODOT" --headless --server --port="$PORT" --min-players="$PLAYERS" $SERVER_ARGS >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

waited_sec=0
until grep -q "\[server\] ready" "$SERVER_LOG" 2>/dev/null; do
	if ! is_running "$SERVER_PID"; then
		fail "сервер завершился, не начав слушать порт $PORT (порт занят или ошибка во флагах)"
		finish
	fi
	if [ "$waited_sec" -ge "$SERVER_READY_TIMEOUT_SEC" ]; then
		fail "сервер не готов за $SERVER_READY_TIMEOUT_SEC с"
		finish
	fi
	sleep 1
	waited_sec=$((waited_sec + 1))
done

for number in $(seq 1 "$PLAYERS"); do
	bot_log="$LOG_DIR/scenario_${NAME}_bot${number}.log"
	rm -f "$bot_log"
	"$GODOT" --headless "$BOT_SCENE" -- --scenario="$NAME" --port="$PORT" --name="Bot$number" \
		--players="$PLAYERS" --deadline="$TIMEOUT_SEC" >"$bot_log" 2>&1 &
	BOT_PIDS+=("$!")
	BOT_LOGS+=("$bot_log")
done

any_bot_running() {
	for pid in "${BOT_PIDS[@]}"; do
		if is_running "$pid"; then
			return 0
		fi
	done
	return 1
}

waited_sec=0
while any_bot_running; do
	if [ "$waited_sec" -ge $((TIMEOUT_SEC + START_MARGIN_SEC)) ]; then
		fail "боты не завершились за $((TIMEOUT_SEC + START_MARGIN_SEC)) с"
		break
	fi
	sleep 1
	waited_sec=$((waited_sec + 1))
done

# Сервер должен был дожить до конца: проверяем до того, как сами его остановим.
if ! is_running "$SERVER_PID"; then
	fail "сервер завершился во время теста"
fi

for index in "${!BOT_PIDS[@]}"; do
	number=$((index + 1))
	stop_process "${BOT_PIDS[$index]}"
	code=$?
	if [ "$code" -ne 0 ]; then
		fail "Bot$number завершился с кодом $code"
	fi
	if ! grep -q "^SCENARIO OK $NAME Bot$number\$" "${BOT_LOGS[$index]}"; then
		fail "в логе Bot$number нет строки SCENARIO OK"
		grep -E "^SCENARIO FAIL" "${BOT_LOGS[$index]}"
	fi
done
BOT_PIDS=()

finish
