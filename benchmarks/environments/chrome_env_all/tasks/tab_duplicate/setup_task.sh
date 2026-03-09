#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Duplication Task Setup: tab_duplicate@1 ==="
echo "Task: Navigate to example.com and duplicate the tab"

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

# Navigate to example.com
TARGET_URL="https://example.com"
echo "Navigating to: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TARGET_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Close any extra tabs to ensure we start with exactly one tab on example.com
echo "Closing extra tabs to ensure clean starting state..."
for i in {1..5}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        echo "Found $TAB_COUNT tabs, closing extras..."
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.5
    else
        break
    fi
done

# Ensure we're back on the example.com tab
echo "Ensuring focus on example.com tab..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5

# Verify the correct page is loaded via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check current tab URL
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
    echo "Current active URL: $CURRENT_URL"
    
    if [[ "$CURRENT_URL" == *"example.com"* ]]; then
        echo "✓ Correctly positioned on example.com"
    else
        echo "⚠ Warning: Not on example.com, attempting to navigate again..."
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
        sleep 0.3
        su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TARGET_URL'" || true
        sleep 0.3
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
        sleep 3
    fi
    
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $INITIAL_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Final focus to ensure Chrome is active and ready for agent interaction
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

echo "=== Setup complete ==="
echo "Chrome should be focused with one tab displaying: example.com"
echo "Agent should now:"
echo "  1. Right-click on the active tab in the tab strip"
echo "  2. Select 'Duplicate' from the context menu"
echo "  OR use keyboard shortcut if available"
echo "Expected result: 2 tabs both showing example.com"