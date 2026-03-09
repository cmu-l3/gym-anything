#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Homepage Button Configuration Task Setup ==="
echo "Task: Enable home button and set Wikipedia as homepage"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

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

# Navigate to Chrome settings page to help the agent start the task
echo "Navigating to: chrome://settings"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Get current tab to verify settings page loaded
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Ensure we have a clean baseline by checking current preferences
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -f "$CHROME_PROFILE/Preferences" ]; then
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    # Backup current preferences
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup.$(date +%s)" 2>/dev/null || true
    echo "✓ Backed up current preferences"
fi

echo "=== Setup complete ==="
echo "Chrome is on Settings page. Agent should now:"
echo "  1. Navigate to 'Appearance' section in settings"
echo "  2. Enable 'Show home button' toggle"
echo "  3. Configure homepage URL to: https://www.wikipedia.org"
echo ""
echo "Both settings should be in the Appearance section or nearby."