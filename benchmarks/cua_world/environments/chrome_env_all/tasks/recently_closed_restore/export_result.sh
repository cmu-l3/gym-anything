#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Recently Closed Tabs Restoration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
    echo "✓ Chrome window focused"
fi
sleep 1

# Capture all tabs via CDP
echo "Capturing tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs.json > /tmp/chrome_page_tabs.json 2>/dev/null || echo "[]" > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json 2>/dev/null || echo "0")
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs for easy verification and logging
    jq -r '.[] | .url' /tmp/chrome_page_tabs.json > /tmp/tab_urls.txt 2>/dev/null || touch /tmp/tab_urls.txt
    
    echo "Active tab URLs:"
    cat /tmp/tab_urls.txt | head -10
    
    # Extract titles as well
    jq -r '.[] | .title' /tmp/chrome_page_tabs.json > /tmp/tab_titles.txt 2>/dev/null || touch /tmp/tab_titles.txt
    
    # Create a combined view for debugging
    echo "Tab details:" > /tmp/tab_details.txt
    jq -r '.[] | "[\(.url)] - \(.title)"' /tmp/chrome_page_tabs.json >> /tmp/tab_details.txt 2>/dev/null || echo "No tabs found" >> /tmp/tab_details.txt
    cat /tmp/tab_details.txt
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs.json
    touch /tmp/tab_urls.txt
    touch /tmp/tab_titles.txt
    echo "CDP query failed" > /tmp/tab_details.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Log final state summary
echo ""
echo "=== Export Summary ==="
echo "Tab data exported to:"
echo "  - /tmp/chrome_page_tabs.json (full CDP data)"
echo "  - /tmp/tab_urls.txt (URL list)"
echo "  - /tmp/tab_titles.txt (title list)"
echo "  - /tmp/tab_details.txt (combined view)"
echo "  - /tmp/final_screenshot.png (screenshot)"
echo ""
echo "✅ Export complete"