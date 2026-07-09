#!/usr/bin/env bash
set -euo pipefail

# Quit any running Safari instance cleanly
osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
pkill -x Safari 2>/dev/null || true
sleep 3

# Ensure Safari preferences allow developer features
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitPreferences.developerExtrasEnabled -bool true
killall cfprefsd 2>/dev/null || true

# Remove any prior output file so verifier cannot mistake a stale result
rm -f "/Users/lume/Documents/edgar_cybersecurity_audit.json"

# Record task-start wall-clock time AFTER removing output (Anti-Pattern 3)
date +%s > /tmp/edgar_task_start_timestamp

# Ensure output directories exist
mkdir -p /Users/lume/Documents

# Launch Safari and wait for it to be ready
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

# Capture a baseline screenshot for diagnostics
screencapture -x /tmp/edgar_task_start.png 2>/dev/null || true

echo "sec_edgar_cybersecurity_disclosure_audit setup complete"
