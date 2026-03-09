#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Groups Organization Task Setup ==="
echo "Task: Organize 12 tabs into 4 logical tab groups"

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

# Close any extra tabs to start fresh
echo "Closing extra tabs to start fresh..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.5
    else
        break
    fi
done

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Function to open a tab with a URL
open_tab() {
    local url="$1"
    echo "Opening tab: $url"
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2
}

# Ensure Chrome window is focused
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 1

echo "Opening 12 tabs across 4 categories..."

# Category 1: News sites (3 tabs)
echo "Opening News tabs..."
open_tab "https://www.bbc.com/news"
open_tab "https://www.cnn.com"
open_tab "https://www.reuters.com"

# Category 2: Shopping sites (3 tabs)
echo "Opening Shopping tabs..."
open_tab "https://www.amazon.com"
open_tab "https://www.ebay.com"
open_tab "https://www.etsy.com"

# Category 3: Documentation sites (3 tabs)
echo "Opening Documentation tabs..."
open_tab "https://developer.mozilla.org/en-US/"
open_tab "https://docs.python.org/3/"
open_tab "https://stackoverflow.com"

# Category 4: Social media sites (3 tabs)
echo "Opening Social tabs..."
open_tab "https://twitter.com"
open_tab "https://www.reddit.com"
open_tab "https://www.linkedin.com"

# Wait for all pages to load
sleep 3

# Focus Chrome one final time
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify tab count via CDP
TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
echo "✓ Setup complete with $TAB_COUNT tabs open"

# Save initial tab state for verification reference
curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")]' > /tmp/initial_tabs.json || true

echo "=== Setup complete ==="
echo "Chrome has 12 tabs open across 4 categories:"
echo "  - News: BBC, CNN, Reuters"
echo "  - Shopping: Amazon, eBay, Etsy"
echo "  - Documentation: MDN, Python Docs, Stack Overflow"
echo "  - Social: Twitter, Reddit, LinkedIn"
echo ""
echo "Agent should:"
echo "  1. Create tab group 'News' with 3 news tabs"
echo "  2. Create tab group 'Shopping' with 3 shopping tabs"
echo "  3. Create tab group 'Documentation' with 3 doc tabs"
echo "  4. Create tab group 'Social' with 3 social tabs"
echo "  5. Assign distinct colors to each group"