#!/usr/bin/env bash
# set -euo pipefail

echo "=== Example Chrome Task Export: Capture Final URL ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Wait a moment for any pending navigation
sleep 2

# Get active tab URL via CDP
echo "Capturing active tab URL via CDP..."
ACTIVE_URL=""

# Try to get URL from CDP
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    # Parse the first page-type tab's URL
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL from CDP: $ACTIVE_URL"
    
    # Save to a result file for verifier
    echo "$ACTIVE_URL" > /tmp/final_url.txt
else
    echo "⚠️  CDP not accessible, URL capture may fail"
fi

# Optional: Take a screenshot for visual verification
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete. Final URL: $ACTIVE_URL"

