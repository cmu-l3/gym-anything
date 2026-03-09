#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome History Search and Recovery Task Setup ==="
echo "Task: Find previously visited webpage using history search"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 sqlite3 bc || true

# Wait for environment to be ready
sleep 2

# Define target and distractor URLs
TARGET_URL="https://example.com/energy-stats/renewable-2024"
DISTRACTOR_URLS=(
    "https://example.com/energy-stats/fossil-2024"
    "https://example.com/climate/renewable-future"
    "https://example.org/solar-power-guide"
    "https://example.com/wind-energy-trends"
)

echo "Setting up Chrome history with target and distractor URLs..."

# Ensure Chrome is running
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

# Function to navigate to URL and wait
navigate_to_url() {
    local url="$1"
    echo "  Visiting: $url"
    
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2
}

# Visit target URL first
echo "Seeding history with TARGET URL..."
navigate_to_url "$TARGET_URL"

# Visit distractor URLs to add noise
echo "Seeding history with DISTRACTOR URLs..."
for distractor in "${DISTRACTOR_URLS[@]}"; do
    navigate_to_url "$distractor"
done

# Visit a few more random pages to add more realistic history
echo "Adding additional browsing history for realism..."
navigate_to_url "https://www.wikipedia.org"
navigate_to_url "https://news.ycombinator.com"

# Verify Chrome is still responsive via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Close Chrome gracefully to flush history to disk
echo "Closing Chrome to save history..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Modify history timestamps to make them appear 2-3 days old
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
HISTORY_DB="$CHROME_PROFILE/History"

if [ ! -f "$HISTORY_DB" ]; then
    echo "⚠ Warning: History database not found at $HISTORY_DB"
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    HISTORY_DB="$CHROME_PROFILE/History"
fi

if [ -f "$HISTORY_DB" ]; then
    echo "Modifying history timestamps to simulate visits 2-3 days ago..."
    
    # Chrome uses WebKit timestamp format: microseconds since 1601-01-01
    # Current time in Chrome format
    CURRENT_TIME_SECONDS=$(date +%s)
    # Convert to Chrome epoch (seconds since 1601-01-01)
    CHROME_EPOCH_OFFSET=11644473600
    CURRENT_CHROME_TIME=$(echo "($CURRENT_TIME_SECONDS + $CHROME_EPOCH_OFFSET) * 1000000" | bc)
    
    # Calculate time 2.5 days ago (216000 seconds = 2.5 days)
    DAYS_AGO_SECONDS=216000
    OLD_CHROME_TIME=$(echo "$CURRENT_CHROME_TIME - ($DAYS_AGO_SECONDS * 1000000)" | bc | cut -d'.' -f1)
    
    echo "  Current Chrome time: $CURRENT_CHROME_TIME"
    echo "  Target visit time: $OLD_CHROME_TIME (2.5 days ago)"
    
    # Backup history database
    cp "$HISTORY_DB" "$HISTORY_DB.backup"
    
    # Update timestamps for target and distractor URLs
    sqlite3 "$HISTORY_DB" <<EOF
UPDATE urls 
SET last_visit_time = $OLD_CHROME_TIME 
WHERE url IN (
    '$TARGET_URL',
    '${DISTRACTOR_URLS[0]}',
    '${DISTRACTOR_URLS[1]}',
    '${DISTRACTOR_URLS[2]}',
    '${DISTRACTOR_URLS[3]}'
);

UPDATE visits 
SET visit_time = $OLD_CHROME_TIME 
WHERE url IN (
    SELECT id FROM urls WHERE url IN (
        '$TARGET_URL',
        '${DISTRACTOR_URLS[0]}',
        '${DISTRACTOR_URLS[1]}',
        '${DISTRACTOR_URLS[2]}',
        '${DISTRACTOR_URLS[3]}'
    )
);
EOF
    
    echo "✓ History timestamps updated"
    
    # Verify target URL is in history
    TARGET_COUNT=$(sqlite3 "$HISTORY_DB" "SELECT COUNT(*) FROM urls WHERE url='$TARGET_URL';")
    echo "✓ Target URL appears $TARGET_COUNT time(s) in history"
    
else
    echo "✗ Could not find History database to modify timestamps"
fi

# Restart Chrome on a neutral page
echo "Restarting Chrome for task..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Wait for Chrome to be fully ready
sleep 2

# Click at center to select desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window after restart"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to Google as clean starting point
echo "Navigating to starting page: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Current URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo ""
echo "SCENARIO: User remembers visiting a useful renewable energy statistics page"
echo "          about 2-3 days ago, but forgot to bookmark it."
echo "          They recall keywords like 'renewable', 'energy', 'solar', 'wind'."
echo ""
echo "TARGET URL: $TARGET_URL"
echo ""
echo "Agent should:"
echo "  1. Press Ctrl+H to open Chrome history"
echo "  2. Use search box to search for 'renewable energy' or similar keywords"
echo "  3. Identify and click on the correct history entry"
echo "  4. Navigate to the target URL: $TARGET_URL"