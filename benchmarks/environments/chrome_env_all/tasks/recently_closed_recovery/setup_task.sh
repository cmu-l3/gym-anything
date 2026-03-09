#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Recently Closed Tabs Recovery Task Setup: recently_closed_recovery@1 ==="
echo "Task: Open 4 tabs, close 3, then selectively recover 2 using Recently Closed"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests sqlite3 || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
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

# Close any extra tabs to ensure we start with exactly one blank tab
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
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $INITIAL_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with one blank tab"
echo ""
echo "Agent task instructions:"
echo "  1. Open Tab 1: Navigate to https://en.wikipedia.org/wiki/Artificial_intelligence"
echo "  2. Open Tab 2: Press Ctrl+T, navigate to https://github.com/trending"
echo "  3. Open Tab 3: Press Ctrl+T, navigate to https://news.ycombinator.com"
echo "  4. Open Tab 4: Press Ctrl+T, navigate to https://stackoverflow.com/questions"
echo "  5. Close Tab 4 (Stack Overflow) with Ctrl+W"
echo "  6. Close Tab 3 (Hacker News) with Ctrl+W"
echo "  7. Close Tab 2 (GitHub) with Ctrl+W"
echo "  8. Right-click on tab bar OR use Menu > History > Recently Closed"
echo "  9. Recover GitHub trending tab"
echo "  10. Recover Hacker News tab"
echo "  11. Do NOT recover Stack Overflow tab"
echo ""
echo "Expected final state: 3 tabs (Wikipedia, GitHub, Hacker News)"