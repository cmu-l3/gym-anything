#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Multi-Tab Session Task Export: multi_tab_session@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Wait a moment for any pending page loads
sleep 2

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture ALL tabs via CDP
echo "Capturing all open tabs via CDP..."
if curl -s http://localhost:9222/json > /tmp/all_chrome_tabs.json 2>/dev/null; then
    # Filter to only page type tabs (excludes extensions, background pages, etc.)
    jq '[.[] | select(.type == "page")]' /tmp/all_chrome_tabs.json > /tmp/all_tabs.json
    
    TAB_COUNT=$(jq '. | length' /tmp/all_tabs.json)
    echo "✓ Captured $TAB_COUNT tabs"
    
    # Log tab URLs for debugging
    echo "Tab URLs:"
    jq -r '.[].url' /tmp/all_tabs.json | while read -r url; do
        echo "  - $url"
    done
else
    echo "⚠ Warning: Failed to capture tabs via CDP"
    echo "[]" > /tmp/all_tabs.json
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"