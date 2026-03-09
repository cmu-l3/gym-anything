#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Advanced Link Opening Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq wmctrl || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

echo "Capturing browser state via CDP..."

# Capture all tabs and windows via CDP
if curl -s http://localhost:9222/json > /tmp/chrome_all_targets.json 2>/dev/null; then
    echo "✓ Successfully captured CDP target information"
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_targets.json > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for verification
    jq -r '.[] | "\(.url)|\(.title)"' /tmp/chrome_page_tabs.json > /tmp/tab_list.txt
    
    # Count unique windows (approximate by grouping webSocketDebuggerUrl)
    # In Chrome CDP, tabs in the same window share similar debugger URL patterns
    WINDOW_COUNT=$(jq -r '.[].webSocketDebuggerUrl' /tmp/chrome_page_tabs.json | cut -d'/' -f3 | sort -u | wc -l || echo "unknown")
    echo "✓ Estimated window count: $WINDOW_COUNT"
    
    echo ""
    echo "Tab information:"
    cat /tmp/tab_list.txt | head -20
    
    # Additional detailed export for verifier
    jq -r '.[] | {url, title, id, webSocketDebuggerUrl}' /tmp/chrome_page_tabs.json > /tmp/chrome_tabs_detailed.json || true
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs.json
    touch /tmp/tab_list.txt
fi

# Capture active tab specifically
echo ""
echo "Capturing active tab information..."
if curl -s http://localhost:9222/json > /tmp/chrome_active_tab_check.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_active_tab_check.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_active_tab_check.json)
    echo "Active tab URL: $ACTIVE_URL"
    echo "Active tab title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > /tmp/active_tab_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# List all Chrome windows for debugging
echo ""
echo "Chrome windows (from wmctrl):"
wmctrl -l | grep -i 'Google Chrome\|Chromium' || echo "No Chrome windows found via wmctrl"

echo ""
echo "✅ Export complete"
echo "Verification files available:"
echo "  - /tmp/chrome_page_tabs.json (main tab data)"
echo "  - /tmp/tab_list.txt (URL|Title list)"
echo "  - /tmp/active_tab_url.txt (active tab URL)"