#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Search Emergency Task Export: tab_search_emergency@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all tabs via CDP
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs_export.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs_export.json > /tmp/chrome_page_tabs_final.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs_final.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for logging
    echo "Final tab state:"
    jq -r '.[] | "  [\(.id[0:8])] \(.title[0:40]) | \(.url[0:60])"' /tmp/chrome_page_tabs_final.json || true
    
    # Identify which tab is currently active by checking for specific markers
    # Active tab often doesn't have a parentId or has specific state
    echo "Attempting to identify active tab..."
    
    # Try to get active tab using CDP Target domain
    # For simplicity, we'll rely on the verifier to determine this from the full data
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs_final.json
fi

# Capture just the active tab URL separately using a simple heuristic
# The most recently accessed tab is often first in the CDP list
if [ -f /tmp/chrome_page_tabs_final.json ]; then
    ACTIVE_TAB_URL=$(jq -r '.[0].url // "unknown"' /tmp/chrome_page_tabs_final.json)
    ACTIVE_TAB_TITLE=$(jq -r '.[0].title // "unknown"' /tmp/chrome_page_tabs_final.json)
    echo "Most likely active tab: $ACTIVE_TAB_TITLE"
    echo "  URL: $ACTIVE_TAB_URL"
    echo "$ACTIVE_TAB_URL" > /tmp/active_tab_url.txt
    echo "$ACTIVE_TAB_TITLE" > /tmp/active_tab_title.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/tab_search_final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/tab_search_final_screenshot.png"
fi

echo "✅ Export complete"
echo "Verification files ready for analysis"