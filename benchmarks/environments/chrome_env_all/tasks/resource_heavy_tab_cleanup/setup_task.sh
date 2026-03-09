#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Resource-Heavy Tab Cleanup Task Setup ==="
echo "Task: Use Chrome Task Manager to identify and close resource-heavy tabs"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly started
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

# Function to open a new tab and navigate
open_tab() {
    local url="$1"
    echo "Opening tab: $url"
    
    # Open new tab
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 1
    
    # Type URL
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    
    # Press Enter
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2.5
}

# Close any existing tabs except the first one
echo "Clearing existing tabs..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.5
    else
        break
    fi
done
sleep 1

# Navigate first tab to an important work tab (Google Docs)
echo "Setting up initial tab..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://docs.google.com/document'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Open additional tabs - mix of high-resource, important, and neutral tabs
echo "Opening additional tabs..."

# Important work tabs (should be preserved)
open_tab "https://mail.google.com/mail"
open_tab "https://github.com/features"

# High-resource tabs (should be closed)
open_tab "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
open_tab "https://www.cnn.com/"
open_tab "https://giphy.com/"

# Neutral/simple tabs
open_tab "https://en.wikipedia.org/wiki/Computer"
open_tab "https://example.com/"

# Another high-resource tab
open_tab "https://threejs.org/benchmarks/environments/#webgl_animation_keyframes"

# Wait for all tabs to load
echo "Waiting for tabs to load completely..."
sleep 5

# Focus Chrome window again
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP and capture initial state
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Capture initial tab state
    curl -s http://localhost:9222/json | jq '[.[] | select(.type == "page")]' > /tmp/initial_tabs.json
    
    INITIAL_TAB_COUNT=$(jq 'length' /tmp/initial_tabs.json)
    echo "✓ Initial state: $INITIAL_TAB_COUNT tabs open"
    
    # Log initial URLs for debugging
    echo "Initial tabs:"
    jq -r '.[] | "  - \(.url)"' /tmp/initial_tabs.json | head -15
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome has $INITIAL_TAB_COUNT tabs open including:"
echo "  - Important work tabs: Google Docs, Gmail, GitHub"
echo "  - Resource-heavy tabs: YouTube, CNN, GIPHY, Three.js demo"
echo "  - Neutral tabs: Wikipedia, Example.com"
echo ""
echo "Agent should:"
echo "  1. Press Shift+Esc to open Chrome Task Manager"
echo "  2. Sort by CPU or Memory to identify resource-heavy tabs"
echo "  3. Close 2-3 resource-heavy tabs (YouTube, CNN, GIPHY, Three.js)"
echo "  4. Preserve important work tabs (Docs, Gmail, GitHub)"
echo "  5. Close Task Manager when done"