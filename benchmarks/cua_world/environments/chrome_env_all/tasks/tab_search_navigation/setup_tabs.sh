#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Search and Navigation Task Setup ==="
echo "Task: Use tab search (Ctrl+Shift+A) to find and navigate to a specific tab"

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

# Close any extra tabs to ensure clean slate
echo "Closing extra tabs to start fresh..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.3
    else
        break
    fi
done

# Function to open a new tab with URL
open_tab_with_url() {
    local url="$1"
    echo "Opening tab: $url"
    
    # Focus Chrome
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    
    # Open new tab
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 0.5
    
    # Navigate to URL
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2
}

# Open first tab with a neutral starting page
echo "Opening initial tab..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://news.ycombinator.com'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Open diverse tabs
echo "Opening multiple tabs for the task..."

# Tab 2: GitHub Chrome Extensions Samples
open_tab_with_url "https://github.com/GoogleChrome/chrome-extensions-samples"

# Tab 3: Chrome Developers Documentation
open_tab_with_url "https://developer.chrome.com/docs/extensions/"

# Tab 4: TARGET - Wikipedia Browser Extension article
open_tab_with_url "https://en.wikipedia.org/wiki/Browser_extension"

# Tab 5: MDN Web Docs
open_tab_with_url "https://developer.mozilla.org/en-US/"

# Tab 6: Stack Overflow
open_tab_with_url "https://stackoverflow.com/questions/tagged/browser-extension"

# Save target tab information for verification
echo "Saving target tab information..."
mkdir -p /tmp/tab_search_task
echo "https://en.wikipedia.org/wiki/Browser_extension" > /tmp/tab_search_task/target_url.txt
echo "Browser extension" > /tmp/tab_search_task/target_keywords.txt

# Navigate back to first tab to ensure agent starts from a non-target tab
echo "Returning to first tab..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 0.5

# Use keyboard shortcut to go to first tab
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+1" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    FINAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Setup complete with $FINAL_TAB_COUNT tabs"
    
    # List all tabs for debugging
    echo "Tab list:"
    curl -s http://localhost:9222/json 2>/dev/null | jq -r '.[] | select(.type == "page") | "  - \(.title)"' || true
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Target tab: Wikipedia - Browser extension"
echo "Agent should:"
echo "  1. Press Ctrl+Shift+A to open tab search"
echo "  2. Search for 'Browser extension' or 'Wikipedia extension'"
echo "  3. Select and navigate to the Wikipedia tab"