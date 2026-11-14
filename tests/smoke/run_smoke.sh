#!/usr/bin/env bash
# Дымовой тест: выделенный сервер и два бота-клиента проходят лобби -> матч -> выход.
# Это автоматический вариант проверки перед PR из CLAUDE.md, раздел 8.
#   GODOT=<путь к godot>   по умолчанию "godot" из PATH
#   SMOKE_PORT=<порт>      по умолчанию 17777
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
PORT="${SMOKE_PORT:-17777}"
LOG_DIR="tests/.logs"
SERVER_LOG="$LOG_DIR/smoke_server.log"
BOT_A_LOG="$LOG_DIR/smoke_bot_a.log"
BOT_B_LOG="$LOG_DIR/smoke_bot_b.log"
BOT_SCENE="res://tests/smoke/smoke_client.tscn"
PLAYERS=2
SERVER_READY_TIMEOUT_SEC=10
# У бота свой предел (около 36 с для двух ботов); запас — на запуск движка.
BOTS_TIMEOUT_SEC=60
LOG_TAIL_LINES=40
# Ошибки скриптов и движка в логах Godot.
ERROR_PATTERN='SCRIPT ERROR|^ERROR:'

SERVER_PID=""
BOT_A_PID=""
BOT_B_PID=""
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
	stop_process "$BOT_A_PID"
	stop_process "$BOT_B_PID"
	stop_process "$SERVER_PID"
	BOT_A_PID=""
	BOT_B_PID=""
	SERVER_PID=""
}
trap cleanup EXIT
trap 'exit 130' INT TERM

fail() {
	echo "SMOKE: $1"
	FAILED=1
}

finish() {
	cleanup
	for log in "$SERVER_LOG" "$BOT_A_LOG" "$BOT_B_LOG"; do
		if [ -f "$log" ] && grep -n -E "$ERROR_PATTERN" "$log" >/dev/null; then
			fail "ошибки в $log:"
			grep -n -E "$ERROR_PATTERN" "$log"
		fi
	done
	if [ "$FAILED" -ne 0 ]; then
		for log in "$SERVER_LOG" "$BOT_A_LOG" "$BOT_B_LOG"; do
			if [ -f "$log" ]; then
				echo "----- $log (последние $LOG_TAIL_LINES строк) -----"
				tail -n "$LOG_TAIL_LINES" "$log"
			fi
		done
		echo "SMOKE: FAILED"
		exit 1
	fi
	echo "SMOKE: OK"
	exit 0
}

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "SMOKE: не найден Godot (\"$GODOT\"). Укажи путь: GODOT=/путь/к/godot"
	echo "SMOKE: FAILED"
	exit 1
fi

mkdir -p "$LOG_DIR"
rm -f "$SERVER_LOG" "$BOT_A_LOG" "$BOT_B_LOG"

echo "SMOKE: сервер на порту $PORT"
# Без паузы на показ ролей: боты начинают ходить сразу после старта матча.
"$GODOT" --headless --server --port="$PORT" --min-players="$PLAYERS" --set=role_reveal_seconds=0 >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

waited_sec=0
until grep -q "\[server\] ready" "$SERVER_LOG" 2>/dev/null; do
	if ! is_running "$SERVER_PID"; then
		fail "сервер завершился, не начав слушать порт $PORT (порт занят? проверь, не остался ли процесс godot от прошлого запуска)"
		finish
	fi
	if [ "$waited_sec" -ge "$SERVER_READY_TIMEOUT_SEC" ]; then
		fail "сервер не готов за $SERVER_READY_TIMEOUT_SEC с"
		finish
	fi
	sleep 1
	waited_sec=$((waited_sec + 1))
done

echo "SMOKE: два бота"
"$GODOT" --headless "$BOT_SCENE" -- --port="$PORT" --name=BotA --players="$PLAYERS" >"$BOT_A_LOG" 2>&1 &
BOT_A_PID=$!
"$GODOT" --headless "$BOT_SCENE" -- --port="$PORT" --name=BotB --players="$PLAYERS" >"$BOT_B_LOG" 2>&1 &
BOT_B_PID=$!

waited_sec=0
while is_running "$BOT_A_PID" || is_running "$BOT_B_PID"; do
	if [ "$waited_sec" -ge "$BOTS_TIMEOUT_SEC" ]; then
		fail "боты не завершились за $BOTS_TIMEOUT_SEC с"
		break
	fi
	sleep 1
	waited_sec=$((waited_sec + 1))
done

# Сервер должен был дожить до конца: проверяем до того, как сами его остановим.
if ! is_running "$SERVER_PID"; then
	fail "сервер завершился во время теста"
fi

stop_process "$BOT_A_PID"
bot_a_code=$?
stop_process "$BOT_B_PID"
bot_b_code=$?
BOT_A_PID=""
BOT_B_PID=""
if [ "$bot_a_code" -ne 0 ]; then
	fail "BotA завершился с кодом $bot_a_code"
fi
if [ "$bot_b_code" -ne 0 ]; then
	fail "BotB завершился с кодом $bot_b_code"
fi
if ! grep -q "^SMOKE OK BotA" "$BOT_A_LOG"; then
	fail "в логе BotA нет строки SMOKE OK"
fi
if ! grep -q "^SMOKE OK BotB" "$BOT_B_LOG"; then
	fail "в логе BotB нет строки SMOKE OK"
fi

finish
