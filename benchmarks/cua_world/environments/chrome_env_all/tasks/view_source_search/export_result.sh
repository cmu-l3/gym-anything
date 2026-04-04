#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome View Page Source Task Export ==="

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
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs.json > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs for easy verification
    jq -r '.[] | .url' /tmp/chrome_page_tabs.json > /tmp/tab_urls.txt
    
    echo "Tab URLs:"
    cat /tmp/tab_urls.txt
    
    # Check if any tab has view-source: prefix
    VIEW_SOURCE_COUNT=$(grep -c "^view-source:" /tmp/tab_urls.txt || echo "0")
    echo "✓ View source tabs found: $VIEW_SOURCE_COUNT"
    
    # Extract the view-source URL if present
    if [ "$VIEW_SOURCE_COUNT" -gt 0 ]; then
        VIEW_SOURCE_URL=$(grep "^view-source:" /tmp/tab_urls.txt | head -1)
        echo "View source URL: $VIEW_SOURCE_URL"
        echo "$VIEW_SOURCE_URL" > /tmp/view_source_url.txt
    else
        echo "none" > /tmp/view_source_url.txt
    fi
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs.json
    touch /tmp/tab_urls.txt
    echo "none" > /tmp/view_source_url.txt
fi

# Capture active tab information
echo "Capturing active tab info..."
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    ACTIVE_TAB=$(curl -s http://localhost:9222/json | jq '[.[] | select(.type == "page")][0]')
    echo "$ACTIVE_TAB" > /tmp/active_tab_info.json
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // "unknown"')
    echo "Active tab URL: $ACTIVE_URL"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
echo "Verification files ready in /tmp/"