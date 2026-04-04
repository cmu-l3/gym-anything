#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Find in Page Navigation Task Setup ==="
echo "Task: Use Find in Page to locate and navigate to the 5th occurrence of 'temperature'"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python requests library for CDP access
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

# Navigate to Wikipedia Climate Change article
ARTICLE_URL="https://en.wikipedia.org/wiki/Climate_change"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$ARTICLE_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true

# Wait for page to load completely (Wikipedia can take a moment)
echo "Waiting for Wikipedia article to load..."
sleep 5

# Verify page loaded by checking title via CDP
for i in {1..10}; do
    PAGE_TITLE=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].title // ""' || echo "")
    if [[ "$PAGE_TITLE" == *"Climate change"* ]]; then
        echo "✓ Wikipedia article loaded successfully"
        break
    fi
    echo "Waiting for page to fully load... (attempt $i/10)"
    sleep 1
done

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Current URL: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Wikipedia Climate Change article loaded"
echo "Agent should now:"
echo "  1. Press Ctrl+F to open find bar"
echo "  2. Type 'temperature' in the search box"
echo "  3. Press Enter 4 times to navigate to the 5th match"
echo "  4. Keep find bar open showing '5 of X' in match counter"