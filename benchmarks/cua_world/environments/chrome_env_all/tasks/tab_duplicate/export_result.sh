#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Duplication Task Export: tab_duplicate@1 ==="

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
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs.json > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for easy debugging
    jq -r '.[] | "[\(.id)] \(.url) | \(.title)"' /tmp/chrome_page_tabs.json > /tmp/tab_list.txt
    
    echo "Tab information:"
    cat /tmp/tab_list.txt
    
    # Count tabs with example.com URL
    EXAMPLE_COUNT=$(jq '[.[] | select(.url | test("example\\.com"; "i"))] | length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $EXAMPLE_COUNT tab(s) with example.com URL"
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs.json
    touch /tmp/tab_list.txt
fi

# Capture the active tab info separately
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    ACTIVE_TAB=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")] | sort_by(.id) | last | {id, url, title}')
    echo "$ACTIVE_TAB" > /tmp/active_tab.json
    echo "Active tab info saved"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
echo "Verification files available in /tmp/"