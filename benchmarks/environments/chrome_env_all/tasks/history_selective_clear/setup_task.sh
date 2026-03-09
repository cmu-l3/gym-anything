#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Selective History Deletion Task Setup ==="
echo "Task: Create history entries and test selective deletion"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 sqlite3 || true

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

# Function to navigate to URL and wait
navigate_to_url() {
    local url="$1"
    echo "Navigating to: $url"
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2
}

# Close any existing tabs except the first one
echo "Closing extra tabs to start fresh..."
for i in {1..5}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.5
    else
        break
    fi
done
sleep 1

# Navigate to URLs containing "example" keyword (these should be deleted)
echo "Creating history entries with 'example' keyword (target for deletion)..."
navigate_to_url "https://www.example.com"
navigate_to_url "https://example.org"
navigate_to_url "https://example-test.net"

# Navigate to URLs NOT containing "example" (these should be preserved)
echo "Creating history entries without 'example' keyword (should be preserved)..."
navigate_to_url "https://www.wikipedia.org"
navigate_to_url "https://www.github.com"
navigate_to_url "https://www.python.org"
navigate_to_url "https://developer.mozilla.org"
navigate_to_url "https://stackoverflow.com"

# Final navigation to a neutral page
echo "Navigating to final neutral page..."
navigate_to_url "https://www.google.com"

# Wait for history to be fully written to database
echo "Waiting for history to be written to database..."
sleep 3

# Close extra tabs, leaving just one
echo "Closing extra tabs..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.3
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
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Capture baseline history for verification
echo "Capturing baseline history state..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/history_baseline.db || true
    echo "✓ Baseline history captured from primary profile"
elif [ -f "$ALT_PROFILE/History" ]; then
    cp "$ALT_PROFILE/History" /tmp/history_baseline.db || true
    echo "✓ Baseline history captured from alternative profile"
fi

# Count entries with and without keyword for logging
if [ -f "/tmp/history_baseline.db" ]; then
    EXAMPLE_COUNT=$(sqlite3 /tmp/history_baseline.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%example%' OR title LIKE '%example%';" 2>/dev/null || echo "0")
    OTHER_COUNT=$(sqlite3 /tmp/history_baseline.db "SELECT COUNT(*) FROM urls WHERE url NOT LIKE '%example%' AND title NOT LIKE '%example%';" 2>/dev/null || echo "0")
    echo "✓ Baseline: $EXAMPLE_COUNT entries with 'example', $OTHER_COUNT other entries"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with populated history."
echo ""
echo "Agent task:"
echo "  1. Press Ctrl+H to open history"
echo "  2. Search for 'example' in the search field"
echo "  3. Select entries containing 'example'"
echo "  4. Delete the selected entries"
echo "  5. Verify other entries remain"