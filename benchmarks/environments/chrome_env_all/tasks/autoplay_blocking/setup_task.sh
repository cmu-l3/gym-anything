#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Media Autoplay Blocking Task Setup ==="
echo "Task: Block auto-playing media on a news website using site-specific permissions"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Define the target website with autoplay content
TARGET_URL="https://www.bbc.com/news"
echo "Target URL with autoplay content: $TARGET_URL"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
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

# Navigate to the target news site
echo "Navigating to: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TARGET_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    # Get current URL to confirm navigation
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Current URL: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Take initial screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/initial_screenshot.png" 2>/dev/null || true
    echo "Initial screenshot saved to /tmp/initial_screenshot.png"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying: $TARGET_URL"
echo ""
echo "Agent should now:"
echo "  1. Click the site permissions icon (lock/info) in the address bar (left of URL)"
echo "  2. Click 'Site settings' at the bottom of the dropdown"
echo "  3. Scroll to find 'Sound' or 'Autoplay' permission"
echo "  4. Change the setting from 'Allow' to 'Block'"
echo "  5. The setting will automatically save"
echo ""
echo "Note: This blocks auto-playing media specifically for $TARGET_URL"