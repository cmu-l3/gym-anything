#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Experimental Features Configuration Task Setup ==="
echo "Task: Enable specific Chrome flags for enhanced browsing"

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

# Navigate to about:blank as starting point (neutral state)
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

# Capture initial Local State for comparison (optional)
echo "Capturing initial Chrome flags state..."
CHROME_CONFIG="/home/ga/.config/google-chrome-cdp"
if [ -f "$CHROME_CONFIG/Local State" ]; then
    cp "$CHROME_CONFIG/Local State" /tmp/local_state_initial.json 2>/dev/null || true
    echo "✓ Initial state captured"
elif [ -f "/home/ga/.config/google-chrome/Local State" ]; then
    cp "/home/ga/.config/google-chrome/Local State" /tmp/local_state_initial.json 2>/dev/null || true
    echo "✓ Initial state captured from alternative location"
else
    echo "⚠ Could not find Local State file for baseline"
fi

echo "=== Setup complete ==="
echo "Chrome is ready on: about:blank"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://flags"
echo "  2. Search for 'smooth scrolling' and enable it"
echo "  3. Search for 'parallel downloading' and enable it"
echo "  4. Search for 'heavy ad intervention' and enable it"
echo "  5. Click 'Relaunch' button (optional - verification checks file)"