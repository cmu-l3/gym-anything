#!/usr/bin/env bash
# set -euo pipefail

echo "=== OSWorld Chrome Task Export: b4f95342-463e-4179-8c3f-193cd7241fb2 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt

    # Also get the full tab info for more complex verifications
    jq '[.[] | select(.type == "page")][0]' /tmp/chrome_tabs.json > /tmp/active_tab_info.json
fi

# Capture HTML content via CDP
echo "Capturing HTML content..."
if [ -f /tmp/active_tab_info.json ]; then
    TAB_ID=$(jq -r '.id' /tmp/active_tab_info.json)
    if [ -n "$TAB_ID" ] && [ "$TAB_ID" != "null" ]; then
        # Get the page HTML using CDP
        curl -s "http://localhost:9222/json/protocol" > /dev/null 2>&1 || true
        # Note: Full CDP HTML capture would require websocket, so we'll rely on verifier to do it
        echo "Tab ID: $TAB_ID" > /tmp/tab_id.txt
    fi
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
