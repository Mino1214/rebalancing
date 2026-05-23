#!/bin/zsh

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PROJECT_ROOT
export PYTHON_BIN="${PYTHON_BIN:-$PROJECT_ROOT/.venv/bin/python}"
export NODE_BIN="${NODE_BIN:-/Applications/Codex.app/Contents/Resources/node}"
export NPM_CLI="${NPM_CLI:-$PROJECT_ROOT/.tools/npm/bin/npm-cli.js}"

if [[ -d "$PROJECT_ROOT/.venv/bin" ]]; then
  export PATH="$PROJECT_ROOT/.venv/bin:$PATH"
fi

echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "PYTHON_BIN=$PYTHON_BIN"
echo "NODE_BIN=$NODE_BIN"
echo "NPM_CLI=$NPM_CLI"
