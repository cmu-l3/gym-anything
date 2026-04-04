#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Recovery Task Export: tab_recovery_undo@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all tabs via CDP
echo "Capturing final tab state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs_final.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs_final.json > /tmp/chrome_page_tabs_final.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs_final.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for verification
    echo "Final tab information:"
    jq -r '.[] | "  Tab: \(.title[:50])... | URL: \(.url)"' /tmp/chrome_page_tabs_final.json || true
    
    # Create a simple list of URLs for easy verification
    jq -r '.[] | .url' /tmp/chrome_page_tabs_final.json > /tmp/tab_urls_final.txt
    
    # Check specifically for GitHub URL presence
    if grep -i "github.com/torvalds/linux" /tmp/tab_urls_final.txt > /dev/null 2>&1; then
        echo "✓ GitHub tab detected in final state"
        echo "true" > /tmp/github_tab_present.txt
    else
        echo "✗ GitHub tab NOT detected in final state"
        echo "false" > /tmp/github_tab_present.txt
    fi
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs_final.json
    touch /tmp/tab_urls_final.txt
    echo "false" > /tmp/github_tab_present.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_recovery.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot_recovery.png"
fi

# Export tab count for quick verification
echo "$TAB_COUNT" > /tmp/final_tab_count.txt

echo "✅ Export complete"
echo "Summary:"
echo "  - Final tab count: $TAB_COUNT"
echo "  - GitHub tab present: $(cat /tmp/github_tab_present.txt)"