#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reading List Management Task Setup: reading_list_organize@1 ==="
echo "Task: Add articles to Reading List and manage read/unread status"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python SQLite support
pip3 install -q pysqlite3 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Clean Reading List database to start fresh
echo "Preparing clean Reading List state..."
CHROME_PROFILE_CDP="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE_STD="/home/ga/.config/google-chrome/Default"

# Try both possible profile locations
for PROFILE in "$CHROME_PROFILE_CDP" "$CHROME_PROFILE_STD"; do
    if [ -d "$PROFILE" ]; then
        READING_LIST_DB="$PROFILE/Reading List"
        if [ -f "$READING_LIST_DB" ]; then
            echo "Backing up existing Reading List: $READING_LIST_DB"
            mv "$READING_LIST_DB" "${READING_LIST_DB}.backup_$(date +%s)" || true
        fi
    fi
done

# Ensure Chrome is stopped before starting
echo "Ensuring Chrome is stopped..."
pkill -f "chrome.*remote-debugging-port" || true
pkill -f "google-chrome" || true
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
sleep 3

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

# Close any extra tabs to ensure we start clean
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

echo "=== Setup complete ==="
echo "Chrome should be focused on: https://www.google.com"
echo ""
echo "Agent task:"
echo "  1. Navigate to en.wikipedia.org/wiki/Python_(programming_language)"
echo "  2. Add to Reading List (Ctrl+D → 'Add to Reading List' or star icon → 'Add to Reading List')"
echo "  3. Navigate to techcrunch.com (any article)"
echo "  4. Add to Reading List"
echo "  5. Navigate to developer.mozilla.org/en-US/docs/Web/JavaScript"
echo "  6. Add to Reading List"
echo "  7. Open Reading List side panel (Ctrl+Shift+E or click side panel icon)"
echo "  8. Mark the first item (Wikipedia) as read by clicking its checkmark"
echo ""
echo "Reading List should contain 3 items: 1 read, 2 unread"