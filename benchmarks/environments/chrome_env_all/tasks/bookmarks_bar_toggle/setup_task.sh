#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarks Bar Toggle Task Setup ==="
echo "Task: Toggle bookmarks bar visibility through Settings > Appearance"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://settings/appearance" &
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

# Navigate to Chrome settings appearance page
echo "Navigating to: chrome://settings/appearance"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings/appearance'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "unknown")
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Store initial bookmarks bar state for reference (optional)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    echo "✓ Chrome profile found at: $CHROME_PROFILE"
    # Check initial state
    if command -v jq &> /dev/null && [ -f "$CHROME_PROFILE/Preferences" ]; then
        INITIAL_STATE=$(jq -r '.bookmark_bar.show_on_all_tabs // "not_set"' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "unknown")
        echo "Initial bookmarks bar state: $INITIAL_STATE"
    fi
else
    echo "⚠ Chrome profile not found, trying alternative location"
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "✓ Found profile at alternative location: $CHROME_PROFILE"
    fi
fi

echo "=== Setup complete ==="
echo "Chrome should be on: chrome://settings/appearance"
echo "Agent should:"
echo "  1. Locate 'Show bookmarks bar' toggle in Appearance section"
echo "  2. Click the toggle to change its state (show/hide)"
echo "  3. The change should save automatically"