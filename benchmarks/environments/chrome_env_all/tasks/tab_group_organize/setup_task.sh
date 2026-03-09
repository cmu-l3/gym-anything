#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Group Organization Task Setup: tab_group_organize@1 ==="
echo "Task: Organize multiple tabs into logical groups with names and colors"

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

# Close any extra tabs to start fresh
echo "Closing extra tabs to start clean..."
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

# Function to open a new tab and navigate
open_tab() {
    local url="$1"
    echo "Opening tab: $url"
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 1.5
}

# Open tabs for ML Research category (5 tabs)
echo "Opening ML Research tabs..."
open_tab "https://arxiv.org/"
open_tab "https://paperswithcode.com/"
open_tab "https://huggingface.co/"
open_tab "https://github.com/trending/python"
open_tab "https://scholar.google.com/"

# Open tabs for Travel Planning category (4 tabs)
echo "Opening Travel Planning tabs..."
open_tab "https://www.booking.com/"
open_tab "https://www.tripadvisor.com/"
open_tab "https://www.kayak.com/"
open_tab "https://www.airbnb.com/"

# Open tabs for Shopping category (3 tabs)
echo "Opening Shopping tabs..."
open_tab "https://www.amazon.com/"
open_tab "https://www.ebay.com/"
open_tab "https://www.etsy.com/"

# Open tabs for News category (3 tabs)
echo "Opening News tabs..."
open_tab "https://news.ycombinator.com/"
open_tab "https://www.reuters.com/"
open_tab "https://www.bbc.com/news"

# Navigate back to first tab to have a neutral starting point
echo "Returning to first tab..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+1" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP and count tabs
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    FINAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Setup complete with $FINAL_TAB_COUNT tab(s) open"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome has multiple tabs open across different categories:"
echo "  - ML Research: arxiv, paperswithcode, huggingface, github, scholar"
echo "  - Travel: booking, tripadvisor, kayak, airbnb"
echo "  - Shopping: amazon, ebay, etsy"
echo "  - News: hackernews, reuters, bbc"
echo ""
echo "Agent task: Create tab groups and organize these tabs"
echo "  1. Right-click tabs and select 'Add tab to new group'"
echo "  2. Name groups (e.g., 'ML Research', 'Travel', 'Shopping', 'News')"
echo "  3. Assign colors to each group"
echo "  4. Drag tabs into their appropriate groups"
echo "  5. Create at least 3 distinct groups with meaningful names"