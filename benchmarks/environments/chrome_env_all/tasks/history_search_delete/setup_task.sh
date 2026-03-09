#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome History Search and Selective Deletion Task Setup ==="
echo "Task: Search for and delete shopping history while preserving other entries"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python libraries for verifier
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Function to navigate to URL and wait for load
navigate_to_url() {
    local url="$1"
    local wait_time="${2:-3}"
    
    echo "Navigating to: $url"
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" 2>/dev/null || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep "$wait_time"
}

# Ensure Chrome is properly set up
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
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" 2>/dev/null || true
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

# Navigate to starting page
navigate_to_url "https://www.google.com" 2

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Close any extra tabs to ensure clean state
echo "Closing extra tabs..."
for i in {1..3}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" 2>/dev/null || true
        sleep 0.5
    else
        break
    fi
done

# Populate history with test URLs
echo "=== Populating browsing history with test data ==="

# Shopping URLs (to be deleted)
navigate_to_url "https://www.example-shopping-site.com/products/camera" 2
navigate_to_url "https://www.example-shopping-site.com/products/laptop" 2

# News URLs (to be preserved)
navigate_to_url "https://www.news-website.com/technology" 2
navigate_to_url "https://www.news-website.com/sports" 2

# Work URLs (to be preserved)
navigate_to_url "https://www.work-related-site.com/dashboard" 2
navigate_to_url "https://www.work-related-site.com/reports" 2

# Navigate back to a neutral page
navigate_to_url "https://www.google.com" 2

echo "✓ History populated with 6 test URLs"

# Give Chrome time to write history to disk
sleep 2

# Close Chrome gracefully to ensure history is persisted
echo "Closing Chrome to persist history..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
if pgrep -f "google-chrome" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" 2>/dev/null || true
    sleep 1
fi

# Record initial history state for verification
echo "Recording initial history state..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

HISTORY_PATH=""
if [ -f "$CHROME_PROFILE/History" ]; then
    HISTORY_PATH="$CHROME_PROFILE/History"
elif [ -f "$ALT_PROFILE/History" ]; then
    HISTORY_PATH="$ALT_PROFILE/History"
fi

if [ -n "$HISTORY_PATH" ]; then
    # Copy History database to analyze initial state
    cp "$HISTORY_PATH" /tmp/history_initial.db
    
    # Count URLs
    INITIAL_COUNT=$(sqlite3 /tmp/history_initial.db "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "0")
    SHOPPING_COUNT=$(sqlite3 /tmp/history_initial.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%shopping-site%';" 2>/dev/null || echo "0")
    NEWS_COUNT=$(sqlite3 /tmp/history_initial.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%news-website%';" 2>/dev/null || echo "0")
    WORK_COUNT=$(sqlite3 /tmp/history_initial.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%work-related%';" 2>/dev/null || echo "0")
    
    echo "Initial history state:"
    echo "  Total URLs: $INITIAL_COUNT"
    echo "  Shopping URLs: $SHOPPING_COUNT"
    echo "  News URLs: $NEWS_COUNT"
    echo "  Work URLs: $WORK_COUNT"
    
    # Save to JSON for verifier
    cat > /tmp/initial_history_state.json << EOF
{
    "total_count": $INITIAL_COUNT,
    "shopping_count": $SHOPPING_COUNT,
    "news_count": $NEWS_COUNT,
    "work_count": $WORK_COUNT
}
EOF
    
    chown ga:ga /tmp/initial_history_state.json
else
    echo "⚠ Warning: Could not find History database"
fi

# Restart Chrome for the task
echo "Restarting Chrome for task..."
sleep 1
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Focus Chrome again
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -n "$wid" ]; then
    wmctrl -i -a $wid || true
    sleep 1
fi

# Final focus
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" 2>/dev/null || true
sleep 1

echo "=== Setup complete ==="
echo "Chrome is ready with populated history."
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://history (Ctrl+H or address bar)"
echo "  2. Search for 'shopping' in the search box"
echo "  3. Select the example-shopping-site.com entries"
echo "  4. Delete them using the 'Remove from history' option"
echo "  5. Verify deletion by searching again"
echo "  6. Ensure news and work URLs are still present"