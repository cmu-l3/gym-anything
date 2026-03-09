#!/usr/bin/env bash
# set -euo pipefail

echo "=== OSWorld Chrome Task Export: 06fe7178-4491-4589-810f-2e2bc9502122 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all open tabs via CDP
echo "Capturing all open tabs..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    jq '[.[] | select(.type == "page") | {url: .url, title: .title}]' /tmp/chrome_tabs.json > /tmp/open_tabs.json
    echo "Open tabs exported to /tmp/open_tabs.json"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
