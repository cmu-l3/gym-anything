#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Responsive Design Mode Testing Task Setup ==="
echo "Task: Use DevTools device emulation to test mobile viewport"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python CDP libraries
pip3 install -q websocket-client 2>/dev/null || {
    echo "⚠ Warning: Could not install websocket-client, some verification features may be limited"
}

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

# Navigate to a responsive design test page
# Using Wikipedia as it has good responsive design for testing
TEST_URL="https://en.wikipedia.org/wiki/Responsive_web_design"
echo "Navigating to responsive test page: $TEST_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TEST_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Get initial viewport dimensions for logging
    INITIAL_DIMS=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '.[0].url' || echo "unknown")
    echo "✓ Initial page loaded: $INITIAL_DIMS"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the responsive design test page"
echo ""
echo "Agent should now:"
echo "  1. Press F12 or Ctrl+Shift+I to open DevTools"
echo "  2. Click the device toolbar icon (phone/tablet) or press Ctrl+Shift+M"
echo "  3. Select a mobile device from the dropdown (e.g., 'iPhone 12 Pro' or 'iPhone SE')"
echo "  4. Verify the viewport changes to mobile dimensions (width ≤ 500px)"
echo ""
echo "The verifier will check viewport dimensions via Chrome DevTools Protocol"