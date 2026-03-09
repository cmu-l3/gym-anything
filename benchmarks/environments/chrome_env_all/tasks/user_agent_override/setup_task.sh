#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome User Agent Override Task Setup ==="
echo "Task: Configure DevTools to override user agent to simulate mobile device"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python WebSocket library for CDP interaction
pip3 install -q websocket-client 2>/dev/null || true

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

# Navigate to the starting URL (example.com)
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
    
    # Get current user agent for comparison
    INITIAL_UA=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url' 2>/dev/null || echo "unknown")
    echo "✓ Chrome is ready with initial page"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready at https://example.com"
echo ""
echo "Agent should now:"
echo "  1. Press F12 or Ctrl+Shift+I to open DevTools"
echo "  2. Navigate to Network conditions panel (Network tab > 3-dot menu > Network conditions)"
echo "  3. Uncheck 'Use browser default' under User agent section"
echo "  4. Select a mobile user agent preset (e.g., iPhone, Android device)"
echo "  5. Optionally verify by navigating to a user agent display page"