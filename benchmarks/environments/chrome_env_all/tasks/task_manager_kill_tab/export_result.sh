#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Task Manager Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Close any Task Manager window that might still be open
echo "Ensuring Task Manager is closed..."
su - ga -c "DISPLAY=:1 xdotool search --name 'Task Manager' windowkill" 2>/dev/null || true
sleep 0.5

# Capture all tabs via CDP
echo "Capturing final tab state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs_final.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs_final.json > /tmp/chrome_page_tabs_final.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs_final.json)
    echo "✓ Found $TAB_COUNT page tab(s) in final state"
    
    # Extract URLs and titles for verification
    jq -r '.[] | "\(.url)|\(.title)"' /tmp/chrome_page_tabs_final.json > /tmp/final_tab_list.txt
    
    echo "Final tab information:"
    cat /tmp/final_tab_list.txt
    
    # Check if GitHub tab is still present
    if jq -r '.[].url' /tmp/chrome_page_tabs_final.json | grep -qi "github.com"; then
        echo "⚠ WARNING: GitHub tab still present - task may not be complete"
    else
        echo "✓ GitHub tab not detected - appears to be closed"
    fi
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs_final.json
    touch /tmp/final_tab_list.txt
fi

# Verify Chrome main process is still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "✓ Chrome main process is still running"
else
    echo "✗ WARNING: Chrome main process not detected - browser may have crashed"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/task_manager_final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/task_manager_final_screenshot.png"
fi

echo "✅ Export complete"
echo "Verification data saved to /tmp/chrome_page_tabs_final.json"