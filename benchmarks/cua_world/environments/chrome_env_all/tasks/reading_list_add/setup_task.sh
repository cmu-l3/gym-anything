#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reading List Task Setup: reading_list_add@1 ==="
echo "Task: Add a Wikipedia article to Chrome's Reading List"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 sqlite3 || true

# Wait for environment to be ready
sleep 2

# Record task start time for verification
echo "$(date +%s)" > /tmp/task_start_time.txt

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the target Wikipedia article
TARGET_URL="https://en.wikipedia.org/wiki/Artificial_intelligence"
echo "Navigating to: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TARGET_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true

# Wait for page to load
echo "Waiting for page to load..."
sleep 5

# Verify page loaded by checking title via CDP
echo "Verifying page load via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_check.json 2>/dev/null; then
    CURRENT_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_check.json)
    CURRENT_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs_check.json)
    echo "Current URL: $CURRENT_URL"
    echo "Current Title: $CURRENT_TITLE"
    
    if [[ "$CURRENT_URL" == *"wikipedia.org"* ]]; then
        echo "✓ Wikipedia page loaded successfully"
    else
        echo "⚠ Warning: Expected Wikipedia URL, got: $CURRENT_URL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying: $TARGET_URL"
echo ""
echo "Agent should now:"
echo "  1. Click the star icon (bookmark) in the address bar"
echo "  2. In the popup, select 'Add to Reading List' option"
echo "  3. Confirm the addition"
echo ""
echo "Note: The star icon is typically at the right end of the address bar"