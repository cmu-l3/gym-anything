#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reopen Closed Tab Task Export: reopen_closed_tab@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's active
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all currently open tabs via CDP
echo "Capturing current tab state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_tabs_final.json > /tmp/chrome_page_tabs_final.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs_final.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs for easy verification
    jq -r '.[] | .url' /tmp/chrome_page_tabs_final.json > /tmp/tab_urls_final.txt
    
    echo "Current open tabs:"
    cat /tmp/tab_urls_final.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs_final.json
    touch /tmp/tab_urls_final.txt
fi

# Copy the target URL info for verifier
if [ -f /tmp/closed_tab_url.txt ]; then
    echo "✓ Target URL info available for verification"
    cat /tmp/closed_tab_url.txt
else
    echo "⚠ Warning: Target URL info not found"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"