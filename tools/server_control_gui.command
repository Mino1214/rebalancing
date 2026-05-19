#!/bin/zsh
set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="$PROJECT_ROOT/.state"
PID_FILE="$STATE_DIR/status_server.pid"
LOG_FILE="$STATE_DIR/status_server.log"
PORT="${ENGINE_PORT:-8788}"
HOST="${ENGINE_HOST:-127.0.0.1}"
LOCAL_URL="http://$HOST:$PORT"
TUNNEL_URL="https://engine.medicalnewshub.info"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python)}"

mkdir -p "$STATE_DIR"

dialog() {
  local title="$1"
  local message="$2"
  osascript - "$title" "$message" <<'OSA'
on run argv
  display dialog (item 2 of argv) with title (item 1 of argv) buttons {"OK"} default button "OK"
end run
OSA
}

choose_action() {
  local message="$1"
  osascript - "$message" <<'OSA'
on run argv
  set choices to {"Start Server", "Stop Server", "Restart Server", "Open Status", "Open Log", "Refresh", "Quit"}
  set selected to choose from list choices with title "Mino Engine Server" with prompt (item 1 of argv) default items {"Refresh"} OK button name "Run" cancel button name "Quit"
  if selected is false then
    return "Quit"
  end if
  return item 1 of selected
end run
OSA
}

pid_is_alive() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
}

pid_command() {
  local pid="$1"
  ps -p "$pid" -o command= 2>/dev/null || true
}

managed_pid() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if pid_is_alive "$pid"; then
      echo "$pid"
      return 0
    fi
  fi

  local port_pid
  port_pid="$(lsof -ti tcp:"$PORT" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$port_pid" ]] && pid_command "$port_pid" | grep -q "rebalancing.status_server"; then
    echo "$port_pid"
    return 0
  fi

  return 1
}

health_ok() {
  curl -fsS --max-time 3 "$LOCAL_URL/health" >/dev/null 2>&1
}

tunnel_ok() {
  curl -fsS --max-time 5 "$TUNNEL_URL/health" >/dev/null 2>&1
}

status_summary() {
  local pid local_status tunnel_status payload summary
  pid="$(managed_pid || true)"

  if health_ok; then
    local_status="OK"
  else
    local_status="OFF"
  fi

  if tunnel_ok; then
    tunnel_status="OK"
  else
    tunnel_status="OFF"
  fi

  if [[ "$local_status" != "OK" ]]; then
    cat <<EOF
Local server: $local_status
Tunnel: $tunnel_status
Port: $PORT
PID: ${pid:-none}

Server is not responding.
EOF
    return 0
  fi

  payload="$(mktemp)"
  if ! curl -fsS --max-time 25 "$LOCAL_URL/status" >"$payload" 2>/dev/null; then
    rm -f "$payload"
    cat <<EOF
Local server: $local_status
Tunnel: $tunnel_status
Port: $PORT
PID: ${pid:-unknown}

/status did not respond.
EOF
    return 0
  fi

  summary="$("$PYTHON_BIN" - "$payload" "$local_status" "$tunnel_status" "${pid:-unknown}" "$PORT" <<'PY'
import json
import sys

path, local_status, tunnel_status, pid, port = sys.argv[1:]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

internals = payload.get("market_internals", {})
lines = [
    f"Local server: {local_status}",
    f"Tunnel: {tunnel_status}",
    f"Port: {port}",
    f"PID: {pid}",
    "",
    f"Source: {payload.get('source', '-')}",
    f"Equity: {payload.get('equity', 0)} USDT",
    f"Regime / Mode: {payload.get('regime', '-')} / {payload.get('mode', '-')}",
    f"Exposure: {payload.get('current_exposure', 0)} -> {payload.get('target_exposure', 0)}",
    f"Positions / Orders: {len(payload.get('positions', []))} / {len(payload.get('orders', []))}",
    f"Live trading: {payload.get('live_trading_enabled', False)}",
    "",
    f"Internals: {internals.get('source', '-')} / {internals.get('risk_label', '-')}",
    f"Stable.D: {internals.get('stable_dominance_pct')}",
    f"Top10.D: {internals.get('top10_dominance_total_pct')}",
    f"Breadth: {internals.get('volume_breadth_pct')}",
]
print("\n".join(lines))
PY
)"
  rm -f "$payload"
  echo "$summary"
}

start_server() {
  if health_ok; then
    dialog "Mino Engine Server" "Server is already running on $LOCAL_URL"
    return 0
  fi

  cd "$PROJECT_ROOT" || exit 1
  : >"$LOG_FILE"

  nohup env \
    PYTHONPATH="$PROJECT_ROOT/src" \
    ENGINE_HOST="$HOST" \
    ENGINE_PORT="$PORT" \
    ENGINE_CORS_ORIGIN="*" \
    FALLBACK_EQUITY="${FALLBACK_EQUITY:-3300}" \
    FALLBACK_WALLET_BALANCE="${FALLBACK_WALLET_BALANCE:-3300}" \
    DAY_START_EQUITY="${DAY_START_EQUITY:-3300}" \
    WEEK_START_EQUITY="${WEEK_START_EQUITY:-3300}" \
    MONTH_START_EQUITY="${MONTH_START_EQUITY:-3300}" \
    BINANCE_LIVE_TRADING="false" \
    BINANCE_ENABLE_ORDERS="false" \
    BINANCE_POSITION_MODE="${BINANCE_POSITION_MODE:-ONE_WAY}" \
    MARKET_INTERNALS_CACHE_SECONDS="${MARKET_INTERNALS_CACHE_SECONDS:-300}" \
    MARKET_INTERNALS_UNIVERSE_LIMIT="${MARKET_INTERNALS_UNIVERSE_LIMIT:-200}" \
    MARKET_INTERNALS_BREADTH_LIMIT="${MARKET_INTERNALS_BREADTH_LIMIT:-100}" \
    MARKET_INTERNALS_BREADTH_WORKERS="${MARKET_INTERNALS_BREADTH_WORKERS:-8}" \
    "$PYTHON_BIN" -m rebalancing.status_server >>"$LOG_FILE" 2>&1 &

  echo "$!" >"$PID_FILE"
  sleep 1

  if health_ok; then
    dialog "Mino Engine Server" "Started.\n\n$LOCAL_URL/status\n$TUNNEL_URL/status"
  else
    dialog "Mino Engine Server" "Start command was sent, but health check failed.\n\nLog:\n$LOG_FILE"
  fi
}

stop_server() {
  local pid
  pid="$(managed_pid || true)"
  if [[ -z "$pid" ]]; then
    dialog "Mino Engine Server" "No managed status server is running."
    return 0
  fi

  if ! pid_command "$pid" | grep -q "rebalancing.status_server"; then
    dialog "Mino Engine Server" "PID $pid is not a rebalancing status server. Not stopping it."
    return 0
  fi

  kill "$pid" >/dev/null 2>&1 || true
  sleep 1
  if pid_is_alive "$pid"; then
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$PID_FILE"
  dialog "Mino Engine Server" "Stopped server PID $pid."
}

open_status() {
  open "$TUNNEL_URL/status"
}

open_log() {
  touch "$LOG_FILE"
  open -a TextEdit "$LOG_FILE"
}

while true; do
  summary="$(status_summary)"
  action="$(choose_action "$summary")"

  case "$action" in
    "Start Server")
      start_server
      ;;
    "Stop Server")
      stop_server
      ;;
    "Restart Server")
      stop_server
      start_server
      ;;
    "Open Status")
      open_status
      ;;
    "Open Log")
      open_log
      ;;
    "Refresh")
      ;;
    "Quit")
      exit 0
      ;;
  esac
done
