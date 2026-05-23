#!/bin/zsh
set -euo pipefail

LABEL="com.mino.postgres"
TARGET_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
rm -f "$TARGET_PLIST"

echo "$LABEL stopped and removed"
