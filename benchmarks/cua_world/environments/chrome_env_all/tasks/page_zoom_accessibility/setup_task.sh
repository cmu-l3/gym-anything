#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Zoom Accessibility Task Setup ==="
echo "Task: Increase page zoom to 125-150% for better readability"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python libraries for verification
pip3 install -q requests 2>/dev/null || true

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

# Navigate to Wikipedia article (text-heavy content ideal for zoom task)
ARTICLE_URL="https://en.wikipedia.org/wiki/Web_browser"
echo "Navigating to: $ARTICLE_URL"

su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$ARTICLE_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Wait for page to fully load
echo "Waiting for page to load..."
sleep 2

# Reset zoom to 100% to ensure clean starting state
echo "Resetting zoom to 100% (Ctrl+0)..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+0" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Log current page URL for verification
    CURRENT_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Current page: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Store the task URL for verifier
echo "$ARTICLE_URL" > /tmp/zoom_task_url.txt

echo "=== Setup complete ==="
echo "Chrome is displaying the Wikipedia article at default zoom (100%)"
echo ""
echo "Agent should now:"
echo "  Option A (Keyboard): Press Ctrl++ multiple times (2-5 times) to zoom to 125-150%"
echo "  Option B (Menu): Click Chrome menu (⋮) → Click + button next to zoom percentage"
echo ""
echo "Target: Increase zoom to approximately 125-150% for improved readability"