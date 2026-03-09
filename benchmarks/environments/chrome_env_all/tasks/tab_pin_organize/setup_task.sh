#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Pinning and Management Task Setup: tab_pin_organize@1 ==="
echo "Task: Open and organize tabs with pinning for workspace management"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip python3-requests || true

# Install protobuf tools for session parsing (optional, best effort)
pip3 install -q protobuf 2>/dev/null || echo "Note: protobuf not installed, session parsing will use fallback"

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
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

# Navigate to the starting URL (Google homepage)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Close any extra tabs to ensure we start with exactly one tab
echo "Closing extra tabs to start fresh..."
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

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $INITIAL_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Record initial session state timestamp for verification
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Current Session" ]; then
    stat "$CHROME_PROFILE/Current Session" > /tmp/initial_session_stat.txt 2>/dev/null || true
fi

echo "=== Setup complete ==="
echo "Chrome is focused with one tab on: https://www.google.com"
echo ""
echo "Agent task steps:"
echo "  1. Open new tab (Ctrl+T) and navigate to https://developer.mozilla.org"
echo "  2. Open new tab (Ctrl+T) and navigate to https://stackoverflow.com"
echo "  3. Open new tab (Ctrl+T) and navigate to https://github.com"
echo "  4. Right-click MDN tab and select 'Pin tab'"
echo "  5. Right-click Stack Overflow tab and select 'Pin tab'"
echo "  6. Right-click GitHub tab and select 'Pin tab'"
echo "  7. Open new tab (Ctrl+T) and navigate to https://reddit.com"
echo "  8. Open new tab (Ctrl+T) and navigate to https://news.ycombinator.com"
echo "  9. Right-click GitHub tab and select 'Unpin tab'"
echo ""
echo "Expected final state: 5 tabs total, 2 pinned (MDN, StackOverflow), 3 unpinned (GitHub, Reddit, HN)"