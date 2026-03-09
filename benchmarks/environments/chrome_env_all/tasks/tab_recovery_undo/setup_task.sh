#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Recovery Task Setup: tab_recovery_undo@1 ==="
echo "Task: Close a specific tab and recover it using Ctrl+Shift+T"

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

# Close any extra tabs to ensure we start fresh
echo "Closing extra tabs to start fresh..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 0 ]; then
        echo "Found $TAB_COUNT tabs, closing all..."
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.5
    else
        break
    fi
done

sleep 1

# Now open the 3 required tabs
echo "Opening Tab 1: Wikipedia - Computer article..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://en.wikipedia.org/wiki/Computer'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Open Tab 2: GitHub Linux repository
echo "Opening Tab 2: GitHub - Linux repository..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://github.com/torvalds/linux'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Open Tab 3: Stack Overflow question
echo "Opening Tab 3: Stack Overflow question..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://stackoverflow.com/questions/11227809'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP and check tab count
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $INITIAL_TAB_COUNT tab(s)"
    
    # Display tab URLs for verification
    echo "Initial tabs:"
    curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")] | .[] | "  - \(.url)"' || true
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should have 3 tabs open:"
echo "  1. Wikipedia - Computer article"
echo "  2. GitHub - Linux repository (TARGET for closing)"
echo "  3. Stack Overflow question"
echo ""
echo "Agent should now:"
echo "  1. Identify and close the GitHub tab (middle tab)"
echo "  2. Use Ctrl+Shift+T to recover the closed tab"
echo "  3. Verify all 3 tabs are present again"