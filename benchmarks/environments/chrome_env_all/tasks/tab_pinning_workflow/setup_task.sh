#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Pinning Workflow Task Setup: tab_pinning_workflow@1 ==="
echo "Task: Pin Gmail and Calendar tabs for persistent workspace organization"

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

# Close any extra tabs to ensure clean start
echo "Closing extra tabs to start fresh..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        echo "Found $TAB_COUNT tabs, closing extras..."
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.3
    else
        break
    fi
done
sleep 1

# Navigate first tab to Gmail
echo "Setting up Tab 1: Gmail..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://mail.google.com'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Open second tab for Google Calendar
echo "Setting up Tab 2: Google Calendar..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://calendar.google.com'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Open third tab for Wikipedia
echo "Setting up Tab 3: Wikipedia article..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://en.wikipedia.org/wiki/Chrome'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Open fourth tab for Hacker News
echo "Setting up Tab 4: Hacker News..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://news.ycombinator.com'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Switch back to first tab to provide starting context
echo "Switching to first tab (Gmail)..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+1" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP and check tab count
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Setup complete with $TAB_COUNT tab(s)"
    
    # Log tab URLs for debugging
    echo "Current tabs:"
    curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")] | .[] | "  - \(.url)"' || true
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should have 4 tabs open:"
echo "  1. Gmail (https://mail.google.com)"
echo "  2. Google Calendar (https://calendar.google.com)"
echo "  3. Wikipedia - Chrome article"
echo "  4. Hacker News"
echo ""
echo "Agent task: Pin Gmail and Calendar tabs (first two tabs)"
echo "Methods:"
echo "  - Right-click on tab → 'Pin tab'"
echo "  - Or select tab and press Ctrl+Shift+P (Linux shortcut)"