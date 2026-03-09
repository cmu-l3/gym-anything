#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Resource-Heavy Tab Cleanup Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Close Task Manager if it's still open (ensure clean state)
echo "Ensuring Chrome Task Manager is closed..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" || true
sleep 0.5

# Capture final tab state via CDP
echo "Capturing final tab state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs_final.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs_final.json > /tmp/final_tabs.json
    
    FINAL_TAB_COUNT=$(jq 'length' /tmp/final_tabs.json)
    echo "✓ Final state: $FINAL_TAB_COUNT tab(s) remaining"
    
    # Log final URLs for debugging
    echo "Final tabs:"
    jq -r '.[] | "  - \(.url)"' /tmp/final_tabs.json
    
    # Extract URLs and titles for easy verification
    jq -r '.[] | "\(.url)|\(.title)"' /tmp/final_tabs.json > /tmp/final_tab_list.txt
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/final_tabs.json
    touch /tmp/final_tab_list.txt
fi

# Ensure initial state file exists (should have been created in setup)
if [ ! -f /tmp/initial_tabs.json ]; then
    echo "⚠ Warning: Initial tab state not found, verification may be limited"
    echo "[]" > /tmp/initial_tabs.json
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
echo "Verification files ready:"
echo "  - /tmp/initial_tabs.json (initial state)"
echo "  - /tmp/final_tabs.json (final state)"
echo "  - /tmp/final_tab_list.txt (final URLs and titles)"