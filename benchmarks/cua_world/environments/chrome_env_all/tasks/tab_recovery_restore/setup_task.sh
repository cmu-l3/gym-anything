#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Recovery Task Setup: tab_recovery_restore@1 ==="
echo "Task: Recover 3 accidentally closed research tabs"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

echo "Setting up Chrome for tab recovery task..."

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

# Close any existing tabs except one to start fresh
echo "Cleaning up existing tabs..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.3
    else
        break
    fi
done

sleep 1

# Now we'll open and then close 3 specific tabs to populate "recently closed" list
echo "Creating tab history for recovery task..."

# Define the 3 target URLs that need to be "accidentally closed"
WIKIPEDIA_URL="https://en.wikipedia.org/wiki/Quantum_computing"
STACKOVERFLOW_URL="https://stackoverflow.com/questions/1011431/how-to-implement-binary-search-in-python"
GITHUB_URL="https://github.com/facebook/react"

# Function to open a URL in a new tab
open_tab_with_url() {
    local url=$1
    echo "  Opening: $url"
    
    # Open new tab with Ctrl+T
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 0.5
    
    # Navigate to URL
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2.5  # Wait for page to load
}

# Open the 3 research tabs
echo "Opening research tabs that will be 'accidentally closed'..."
open_tab_with_url "$WIKIPEDIA_URL"
open_tab_with_url "$STACKOVERFLOW_URL"
open_tab_with_url "$GITHUB_URL"

# Let all pages finish loading
sleep 2

# Verify we have the expected number of tabs before closing
CURRENT_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "0")
echo "Current tab count before closing: $CURRENT_TAB_COUNT (expected 4: original + 3 research)"

# Now close these tabs to simulate "accidental closure"
# Close them in reverse order so they appear in the right order in recently-closed
echo "Simulating accidental tab closures..."
for i in {1..3}; do
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.2
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
    sleep 0.5
done

# Wait a moment for Chrome to register the closures
sleep 1

# Verify we're back to 1 tab
FINAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "0")
echo "Tab count after closures: $FINAL_TAB_COUNT (expected 1)"

# Navigate the remaining tab to Google as a neutral starting point
echo "Setting up starting state with Google homepage..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Open one more generic tab so agent doesn't accidentally close the last tab
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'about:blank'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    STARTING_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $STARTING_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo ""
echo "=== Setup complete ==="
echo "✓ Chrome is focused with $STARTING_TAB_COUNT generic tab(s)"
echo "✓ 3 research tabs have been 'accidentally closed' and are in recently-closed list:"
echo "   - Quantum Computing - Wikipedia"
echo "   - How to implement binary search in Python - Stack Overflow"
echo "   - facebook/react repository - GitHub"
echo ""
echo "Agent task: Recover these 3 tabs using Chrome's recovery features"
echo "  Methods available:"
echo "   • Press Ctrl+Shift+T three times"
echo "   • Menu → History → Recently closed"
echo "   • Right-click tab bar → Reopen closed tab"