#!/bin/bash
# Setup script for Chrome multi-tab session task
# Ensures Chrome is running and starts with a clean single tab

set -e

echo "Setting up Chrome multi-tab session task..."

# Verify Chrome is running with CDP access
CDP_PORT=9222
MAX_RETRIES=10
RETRY_COUNT=0

echo "Checking Chrome CDP availability on port ${CDP_PORT}..."

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s "http://localhost:${CDP_PORT}/json" > /dev/null 2>&1; then
        echo "Chrome CDP is accessible"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for Chrome CDP... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "ERROR: Chrome CDP not accessible after $MAX_RETRIES attempts"
    exit 1
fi

# Get current tabs
TABS_JSON=$(curl -s "http://localhost:${CDP_PORT}/json")
TAB_COUNT=$(echo "$TABS_JSON" | jq -r '[.[] | select(.type == "page")] | length')

echo "Current number of tabs: $TAB_COUNT"

# If there are too many tabs, close all but one to start fresh
if [ "$TAB_COUNT" -gt 3 ]; then
    echo "Closing extra tabs to start with clean state..."
    
    # Get all tab IDs except the first one
    TAB_IDS=$(echo "$TABS_JSON" | jq -r '[.[] | select(.type == "page")][1:] | .[].id')
    
    # Close extra tabs using CDP
    for TAB_ID in $TAB_IDS; do
        echo "Closing tab: $TAB_ID"
        curl -s "http://localhost:${CDP_PORT}/json/close/$TAB_ID" > /dev/null || true
    done
    
    sleep 1
    echo "Extra tabs closed"
fi

# Ensure we have at least one tab open (navigate to blank page if needed)
TABS_JSON=$(curl -s "http://localhost:${CDP_PORT}/json")
TAB_COUNT=$(echo "$TABS_JSON" | jq -r '[.[] | select(.type == "page")] | length')

if [ "$TAB_COUNT" -eq 0 ]; then
    echo "No tabs open, Chrome may have closed. Attempting to open new tab..."
    # Use xdotool to open new tab
    export DISPLAY=:1
    CHROME_WINDOW=$(wmctrl -l | grep -i "chrome" | head -1 | awk '{print $1}')
    if [ -n "$CHROME_WINDOW" ]; then
        wmctrl -i -a "$CHROME_WINDOW"
        sleep 0.5
        xdotool key ctrl+t
        sleep 1
    fi
fi

echo "Chrome is ready for multi-tab session task"
echo "Current state: $(curl -s http://localhost:${CDP_PORT}/json | jq -r '[.[] | select(.type == "page")] | length') tab(s) open"
echo "Task: Open 4 tabs with Wikipedia, GitHub, Stack Overflow, and MDN"
echo ""
echo "Instructions:"
echo "1. Press Ctrl+T to open new tab"
echo "2. Type URL in address bar and press Enter"
echo "3. Repeat for all 4 URLs:"
echo "   - https://en.wikipedia.org"
echo "   - https://github.com"
echo "   - https://stackoverflow.com"
echo "   - https://developer.mozilla.org"

exit 0