#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Media-Playing Tab Detection Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all tabs via CDP with detailed information
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs.json > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract tab details with media status
    echo "" > /tmp/tab_details.txt
    echo "Tab Information:" >> /tmp/tab_details.txt
    jq -r '.[] | "URL: \(.url)\nTitle: \(.title)\nAudible: \(.audible // false)\n---"' /tmp/chrome_page_tabs.json >> /tmp/tab_details.txt
    
    cat /tmp/tab_details.txt
    
    # Count audible tabs
    AUDIBLE_COUNT=$(jq '[.[] | select(.audible == true)] | length' /tmp/chrome_page_tabs.json)
    echo ""
    echo "Summary:"
    echo "  Total tabs: $TAB_COUNT"
    echo "  Audible tabs: $AUDIBLE_COUNT"
    
    # Save media tab info separately
    jq '[.[] | select(.audible == true)]' /tmp/chrome_page_tabs.json > /tmp/media_tabs.json
    echo "  Media tab info saved to: /tmp/media_tabs.json"
    
    # Get the currently active tab (first in list typically)
    ACTIVE_URL=$(jq -r '.[0].url // "unknown"' /tmp/chrome_page_tabs.json)
    ACTIVE_TITLE=$(jq -r '.[0].title // "unknown"' /tmp/chrome_page_tabs.json)
    echo ""
    echo "Active Tab:"
    echo "  URL: $ACTIVE_URL"
    echo "  Title: $ACTIVE_TITLE"
    
    # Save active tab info
    echo "$ACTIVE_URL" > /tmp/active_tab_url.txt
    echo "$ACTIVE_TITLE" > /tmp/active_tab_title.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs.json
    echo "[]" > /tmp/media_tabs.json
    touch /tmp/tab_details.txt
    echo "unknown" > /tmp/active_tab_url.txt
    echo "unknown" > /tmp/active_tab_title.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
echo "Verification files ready for analysis"