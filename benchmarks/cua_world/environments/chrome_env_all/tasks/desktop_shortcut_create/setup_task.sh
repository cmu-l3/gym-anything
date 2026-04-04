#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Desktop Shortcut Creation Task Setup ==="
echo "Task: Create desktop shortcut for Wikipedia with custom name and window mode"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Record task start time for verification timestamp filtering
date +%s > /tmp/task_start_time.txt

# Clean up any old Wikipedia shortcuts from previous runs
echo "Cleaning up old shortcuts..."
rm -f /home/ga/Desktop/*wiki*.desktop 2>/dev/null || true
rm -f /home/ga/Desktop/*Wiki*.desktop 2>/dev/null || true
rm -f /home/ga/.local/share/applications/*wiki*.desktop 2>/dev/null || true
rm -f /home/ga/.local/share/applications/*Wiki*.desktop 2>/dev/null || true

# Ensure Desktop directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop || true

# Ensure applications directory exists
mkdir -p /home/ga/.local/share/applications
chown -R ga:ga /home/ga/.local/share/applications || true

# Ensure Chrome is properly focused and on correct URL
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.wikipedia.org/" &
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

# Navigate to Wikipedia homepage
echo "Navigating to: https://www.wikipedia.org/"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.wikipedia.org/'" || true
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

echo "=== Setup complete ==="
echo "Chrome is displaying Wikipedia homepage"
echo "Agent should now:"
echo "  1. Click Chrome menu (three dots ⋮ in top-right corner)"
echo "  2. Navigate to 'More tools' → 'Create shortcut...'"
echo "  3. Change shortcut name to 'Wiki Reference'"
echo "  4. Check the 'Open as window' checkbox"
echo "  5. Click 'Create' button"