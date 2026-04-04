#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Save Webpage Complete Task Setup: save_page_complete@1 ==="
echo "Task: Save Wikipedia article as complete webpage with all resources"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python libraries for verification (do this early)
pip3 install -q beautifulsoup4 lxml 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Clean up any previous test artifacts
echo "Cleaning up previous test files..."
rm -f /home/ga/Downloads/web_archiving_complete.html 2>/dev/null || true
rm -rf /home/ga/Downloads/web_archiving_complete_files/ 2>/dev/null || true
rm -f /tmp/save_complete_verification.txt 2>/dev/null || true

# Ensure Downloads directory exists with correct permissions
mkdir -p /home/ga/Downloads
chown -R ga:ga /home/ga/Downloads
echo "✓ Downloads directory ready"

# Ensure Chrome is properly focused and on correct URL
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
TARGET_URL="https://en.wikipedia.org/wiki/Web_archiving"
echo "Navigating to: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://en.wikipedia.org/wiki/Web_archiving'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true

# Wait for page to fully load (important for complete resource capture)
echo "Waiting for page to load completely..."
sleep 5

# Verify page loaded by checking title via CDP
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_setup.json 2>/dev/null; then
    CURRENT_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_setup.json)
    CURRENT_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs_setup.json)
    echo "✓ Current page: $CURRENT_TITLE"
    echo "✓ Current URL: $CURRENT_URL"
    
    if [[ "$CURRENT_URL" == *"wikipedia.org/wiki/Web_archiving"* ]]; then
        echo "✓ Successfully navigated to Wikipedia article"
    else
        echo "⚠ Warning: May not be on correct page"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Final focus to ensure Chrome is active and ready for agent
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome displaying Wikipedia article on Web Archiving"
echo ""
echo "Agent should now:"
echo "  1. Press Ctrl+S to open Save dialog"
echo "  2. Change 'Save as type' to 'Webpage, Complete'"
echo "  3. Set filename to: web_archiving_complete"
echo "  4. Verify save location is /home/ga/Downloads"
echo "  5. Click Save button"
echo ""
echo "Expected result:"
echo "  - File: /home/ga/Downloads/web_archiving_complete.html"
echo "  - Folder: /home/ga/Downloads/web_archiving_complete_files/"