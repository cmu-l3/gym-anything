#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Local Storage Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture CDP targets information
echo "Capturing CDP state..."
if curl -s http://localhost:9222/json > /tmp/cdp_targets.json 2>/dev/null; then
    echo "✓ CDP targets captured"
    
    # Count pages
    PAGE_COUNT=$(jq '[.[] | select(.type == "page")] | length' /tmp/cdp_targets.json)
    echo "✓ Found $PAGE_COUNT page(s)"
    
    # Find test page
    TEST_PAGE_URL=$(jq -r '.[] | select(.url | contains("localstorage_test")) | .url' /tmp/cdp_targets.json | head -1)
    if [ -n "$TEST_PAGE_URL" ]; then
        echo "✓ Test page found: $TEST_PAGE_URL"
    fi
else
    echo "⚠ Warning: Could not capture CDP state"
    echo "[]" > /tmp/cdp_targets.json
fi

# Capture active tab URL
ACTIVE_URL=$(jq -r '.[0].url // ""' /tmp/cdp_targets.json 2>/dev/null || echo "")
echo "Active URL: $ACTIVE_URL"
echo "$ACTIVE_URL" > /tmp/final_url.txt

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
echo "Verifier will use CDP to inspect localStorage state"