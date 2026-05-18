#!/usr/bin/env bash
set -euo pipefail

osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
pkill -x Safari 2>/dev/null || true
sleep 3

# Web Inspector Audit tab requires developer extras enabled
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitPreferences.developerExtrasEnabled -bool true
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
killall cfprefsd 2>/dev/null || true

rm -f "/Users/lume/Documents/federal_accessibility_audit.json"

date +%s > /tmp/a11y_task_start_timestamp

mkdir -p /Users/lume/Documents

open -a Safari
sleep 4

TIMEOUT=30
ELAPSED=0
while ! lsappinfo info -only name Safari 2>/dev/null | grep -q Safari; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "WARNING: Safari did not start within ${TIMEOUT}s" >&2
        break
    fi
done

screencapture -x /tmp/a11y_task_start.png 2>/dev/null || true

echo "safari_federal_accessibility_audit setup complete"
