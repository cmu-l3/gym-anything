#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Offline Mode Simulation Task Setup ==="
echo "Task: Simulate offline mode using DevTools Network panel"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick tesseract-ocr sqlite3 || true

# Install Python libraries for image analysis
pip3 install -q pillow pytesseract numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://example.com" &
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

# Navigate to a test page (example.com)
echo "Navigating to: https://example.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://example.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Create a directory for screenshots during task execution
mkdir -p /tmp/offline_task_screenshots
chown -R ga:ga /tmp/offline_task_screenshots

echo "=== Setup complete ==="
echo "Chrome is ready on: https://example.com"
echo ""
echo "Agent should:"
echo "  1. Press F12 to open DevTools"
echo "  2. Click on 'Network' tab"
echo "  3. Click throttling dropdown (shows 'No throttling')"
echo "  4. Select 'Offline' from the dropdown"
echo "  5. Refresh the page (Ctrl+R) or navigate to a URL"
echo "  6. Observe offline error page (dinosaur game)"
echo "  7. Return to Network panel throttling dropdown"
echo "  8. Select 'No throttling' or 'Online' to restore"
echo "  9. Refresh page to verify it loads successfully"