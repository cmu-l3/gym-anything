#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Device Mode Emulation and Capture Task Setup ==="
echo "Task: Use DevTools Device Mode to emulate iPhone SE and capture screenshot"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PIL/Pillow for image dimension verification
pip3 install -q Pillow pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Clear Downloads folder to avoid confusion with pre-existing screenshots
echo "Clearing Downloads folder..."
DOWNLOADS_DIR="/home/ga/Downloads"
mkdir -p "$DOWNLOADS_DIR"
rm -f "$DOWNLOADS_DIR"/*.png "$DOWNLOADS_DIR"/*.jpg "$DOWNLOADS_DIR"/*.jpeg 2>/dev/null || true
chown -R ga:ga "$DOWNLOADS_DIR"
echo "✓ Downloads folder cleared"

# Record task start time for verifier
date +%s > /tmp/task_start_time.txt
echo "✓ Task start time recorded: $(date)"

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

# Navigate to a neutral starting page (about:blank or Google)
echo "Navigating to starting page..."
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
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Chrome has $TAB_COUNT tab(s) open"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo ""
echo "Chrome is ready. Agent should now:"
echo "  1. Press F12 or Ctrl+Shift+I to open DevTools"
echo "  2. Press Ctrl+Shift+M to toggle Device Toolbar"
echo "  3. Select 'iPhone SE' from device dropdown (375x667 viewport)"
echo "  4. Navigate to: https://example.com"
echo "  5. Capture screenshot using Device Mode screenshot button"
echo "  6. Screenshot will be saved to Downloads folder"
echo ""
echo "Expected screenshot dimensions: 375 x 667 pixels"