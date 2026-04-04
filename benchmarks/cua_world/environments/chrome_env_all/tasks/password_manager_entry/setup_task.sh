#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Password Manager Manual Entry Task Setup ==="
echo "Task: Manually add password entry via chrome://settings/passwords"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python SQLite3 support (usually built-in but ensure it's available)
pip3 install -q --upgrade pip 2>/dev/null || true

# Record task start timestamp for verification (Unix timestamp in seconds)
TASK_START_TIME=$(date +%s)
echo "$TASK_START_TIME" > /tmp/task_start_time.txt
echo "✓ Task start time recorded: $TASK_START_TIME"

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

# Navigate to the starting URL (about:blank for clean start)
echo "Navigating to: about:blank"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'about:blank'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Create a marker file to indicate setup completion
echo "setup_complete" > /tmp/password_task_setup.txt

echo "=== Setup complete ==="
echo "Chrome is ready at about:blank"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings/passwords (Ctrl+L, type URL, Enter)"
echo "  2. Click the 'Add' button to open password entry dialog"
echo "  3. Fill in Site: https://example-testsite.com"
echo "  4. Fill in Username: testuser@example.com"
echo "  5. Fill in Password: SecureP@ssw0rd!123"
echo "  6. Click 'Save' button to commit the entry"