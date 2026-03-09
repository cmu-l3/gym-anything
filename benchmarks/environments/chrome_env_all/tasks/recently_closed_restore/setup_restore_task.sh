#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Recently Closed Tabs Restoration Task Setup ==="
echo "Task: Restore previously closed tabs using Recently Closed feature"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

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

# Navigate to first URL (example.com)
echo "Opening Tab 1: https://example.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://example.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Open second tab and navigate to wikipedia.org
echo "Opening Tab 2: https://wikipedia.org"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://wikipedia.org'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Open third tab and navigate to github.com
echo "Opening Tab 3: https://github.com"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://github.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Verify all three tabs are open
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Chrome CDP accessible - $TAB_COUNT tabs currently open"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Close the GitHub tab (currently active)
echo "Closing GitHub tab..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
sleep 1

# Close the Wikipedia tab (now active after GitHub closed)
echo "Closing Wikipedia tab..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify final state (should be 1 tab remaining)
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    FINAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Setup complete - $FINAL_TAB_COUNT tab(s) currently open (example.com should remain)"
    
    # Log current tab URL for verification
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // "unknown"')
    echo "  Current tab URL: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome has 1 tab open (example.com). Two tabs were closed (Wikipedia, GitHub)."
echo ""
echo "Agent task: Restore the 2 closed tabs using one of these methods:"
echo "  Method 1: Click menu (⋮) → History → Recently closed → Click on tabs"
echo "  Method 2: Press Ctrl+Shift+T twice to restore tabs sequentially"
echo ""
echo "Expected final state: 3 tabs open (example.com, wikipedia.org, github.com)"