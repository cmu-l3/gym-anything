#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Folder Organization Task Setup ==="
echo "Task: Create 'Tech Resources' folder with GitHub, Stack Overflow, and MDN bookmarks"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

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

# Navigate to Bookmark Manager
echo "Opening Chrome Bookmark Manager..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5

# Use Ctrl+Shift+O to open Bookmark Manager
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+o" || true
sleep 2

# Alternative: Navigate directly to chrome://bookmarks/ if shortcut doesn't work
echo "Ensuring Bookmark Manager is open via URL..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://bookmarks/'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Capture active URL to verify Bookmark Manager is open
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
    echo "Active URL: $ACTIVE_URL"
    
    if [[ "$ACTIVE_URL" == *"chrome://bookmarks"* ]]; then
        echo "✓ Bookmark Manager is open"
    else
        echo "⚠ Warning: Bookmark Manager may not be open (URL: $ACTIVE_URL)"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Ensure bookmarks bar is visible by setting preference
echo "Ensuring bookmarks bar is visible..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -f "$CHROME_PROFILE/Preferences" ]; then
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    # Backup existing preferences
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup_$(date +%s)" 2>/dev/null || true
    echo "✓ Preferences backed up"
fi

echo "=== Setup complete ==="
echo "Chrome Bookmark Manager should be open"
echo "Agent should:"
echo "  1. Create a new folder named 'Tech Resources' in Bookmark Bar"
echo "  2. Add bookmark: GitHub → https://github.com"
echo "  3. Add bookmark: Stack Overflow → https://stackoverflow.com"
echo "  4. Add bookmark: MDN Web Docs → https://developer.mozilla.org"