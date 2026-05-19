#!/bin/zsh
set -u

PROJECT_ROOT="/Users/myno/Desktop/rebalancing"
STATE_DIR="$PROJECT_ROOT/.state"
LOG_FILE="$STATE_DIR/status_server.log"

mkdir -p "$STATE_DIR"
cd "$PROJECT_ROOT" || exit 78

echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') starting rebalancing.status_server" >>"$LOG_FILE"

exec env \
  PYTHONPATH="$PROJECT_ROOT/src" \
  ENGINE_HOST="127.0.0.1" \
  ENGINE_PORT="8788" \
  ENGINE_CORS_ORIGIN="*" \
  ENGINE_WEBHOOK_TOKEN_FILE="$STATE_DIR/engine_webhook_token" \
  ENGINE_SIGNAL_STORE_PATH="$STATE_DIR/tradingview_alerts.json" \
  ENGINE_SIGNAL_STORE_MAX_RECORDS="200" \
  ENGINE_TV_MAX_ALERT_AGE_SECONDS="0" \
  FALLBACK_EQUITY="3300" \
  FALLBACK_WALLET_BALANCE="3300" \
  DAY_START_EQUITY="3300" \
  WEEK_START_EQUITY="3300" \
  MONTH_START_EQUITY="3300" \
  BINANCE_LIVE_TRADING="false" \
  BINANCE_ENABLE_ORDERS="false" \
  BINANCE_POSITION_MODE="ONE_WAY" \
  MARKET_INTERNALS_CACHE_SECONDS="300" \
  MARKET_INTERNALS_UNIVERSE_LIMIT="200" \
  MARKET_INTERNALS_BREADTH_LIMIT="100" \
  MARKET_INTERNALS_BREADTH_WORKERS="8" \
  /opt/local/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python -m rebalancing.status_server
