#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$PROJECT_ROOT/.venv/bin/python}"
NODE_BIN="${NODE_BIN:-/Applications/Codex.app/Contents/Resources/node}"
NPM_CLI="${NPM_CLI:-$PROJECT_ROOT/.tools/npm/bin/npm-cli.js}"

cd "$PROJECT_ROOT"
"$PYTHON_BIN" -m unittest discover -s tests

cd "$PROJECT_ROOT/workers/tradingview-webhook"
"$NODE_BIN" "$NPM_CLI" run check
