#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_FILE="${ANTHROPIC_API_KEY_FILE:-$PROJECT_ROOT/.state/anthropic_api_key}"

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [ANTHROPIC_API_KEY]" >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  API_KEY="$1"
else
  printf "Anthropic API key: " >&2
  stty -echo
  IFS= read -r API_KEY
  stty echo
  printf "\n" >&2
fi

API_KEY="${API_KEY//$'\r'/}"
API_KEY="${API_KEY//$'\n'/}"
API_KEY="${API_KEY#"${API_KEY%%[![:space:]]*}"}"
API_KEY="${API_KEY%"${API_KEY##*[![:space:]]}"}"
API_KEY="${API_KEY#\"}"
API_KEY="${API_KEY%\"}"
API_KEY="${API_KEY#\'}"
API_KEY="${API_KEY%\'}"

if [[ -z "$API_KEY" ]]; then
  echo "No API key provided." >&2
  exit 1
fi

if [[ "$API_KEY" != sk-ant-* ]]; then
  echo "Warning: key does not start with sk-ant-; saving anyway." >&2
fi

mkdir -p "$(dirname "$KEY_FILE")"
chmod 700 "$(dirname "$KEY_FILE")"
umask 077
printf "%s" "$API_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

echo "Saved Anthropic API key to $KEY_FILE"
