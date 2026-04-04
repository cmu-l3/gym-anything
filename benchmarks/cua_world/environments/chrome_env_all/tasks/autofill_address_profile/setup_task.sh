#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome AutoFill Address Profile Task Setup ==="
echo "Task: Create AutoFill address profile with Sarah Mitchell's information"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python libraries for verification
pip3 install -q pypdf pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Record task start time for verification (Chrome uses microseconds since epoch)
TASK_START_TIME=$(date +%s)
echo "$TASK_START_TIME" > /tmp/autofill_task_start_time.txt
echo "Task start time recorded: $TASK_START_TIME"

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

# Navigate to the starting URL (Google homepage as neutral starting point)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Verify Chrome profile directories exist
CHROME_PROFILE_CDP="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -d "$CHROME_PROFILE_CDP" ]; then
    echo "✓ Chrome profile found at: $CHROME_PROFILE_CDP"
elif [ -d "$CHROME_PROFILE" ]; then
    echo "✓ Chrome profile found at: $CHROME_PROFILE"
else
    echo "⚠ Warning: Chrome profile directories not found"
fi

echo "=== Setup complete ==="
echo "Chrome is ready. Agent should now:"
echo "  1. Navigate to chrome://settings/addresses"
echo "  2. Click 'Add' button to create new address profile"
echo "  3. Fill in the following information:"
echo "     - Name: Sarah Mitchell"
echo "     - Address: 742 Evergreen Terrace, Apt 3B"
echo "     - City: Springfield"
echo "     - State: Illinois (IL)"
echo "     - ZIP: 62704"
echo "     - Phone: 217-555-0147"
echo "     - Email: sarah.mitchell@example.com"
echo "  4. Click 'Save' to create the profile"