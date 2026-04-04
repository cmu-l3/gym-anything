#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Browsing History Task Setup ==="
echo "Task: Clear all browsing history while preserving cookies and cache"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python dependencies for verification
pip3 install -q --no-cache-dir 2>/dev/null || true

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

# Define baseline URLs to populate history
BASELINE_URLS=(
    "https://www.wikipedia.org"
    "https://news.ycombinator.com"
    "https://github.com"
    "https://stackoverflow.com"
    "https://www.reddit.com"
    "https://www.python.org"
    "https://developer.mozilla.org"
)

echo "Populating browsing history with baseline URLs..."

# Navigate to each URL to populate history
for url in "${BASELINE_URLS[@]}"; do
    echo "Visiting: $url"
    
    # Focus Chrome
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    
    # Open address bar
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    
    # Type URL
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    
    # Press Enter
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2.5
done

# Navigate to Google as the final page (neutral starting point for task)
echo "Navigating to Google as starting page..."
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

# Save baseline URLs to file for verification
echo "Saving baseline URLs for verification..."
mkdir -p /tmp/history_task_data
for url in "${BASELINE_URLS[@]}"; do
    echo "$url" >> /tmp/history_task_data/baseline_urls.txt
done

# Verify history was populated
echo "Verifying history population..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Wait a moment for Chrome to write to History database
sleep 2

if [ -f "$CHROME_PROFILE/History" ]; then
    HISTORY_COUNT=$(sqlite3 "$CHROME_PROFILE/History" "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "0")
    echo "✓ History entries in database: $HISTORY_COUNT"
    
    if [ "$HISTORY_COUNT" -lt 5 ]; then
        echo "⚠ Warning: Fewer than 5 history entries detected. Task may not work correctly."
    fi
elif [ -f "$ALT_PROFILE/History" ]; then
    HISTORY_COUNT=$(sqlite3 "$ALT_PROFILE/History" "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "0")
    echo "✓ History entries in database (alt location): $HISTORY_COUNT"
else
    echo "⚠ Warning: Could not verify history database"
fi

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying Google homepage"
echo "History has been populated with ${#BASELINE_URLS[@]} URLs"
echo ""
echo "Agent should now:"
echo "  1. Open Chrome settings (chrome://settings or Ctrl+, or three-dot menu → Settings)"
echo "  2. Navigate to 'Privacy and security' section"
echo "  3. Click 'Clear browsing data'"
echo "  4. Select 'All time' as the time range"
echo "  5. Ensure ONLY 'Browsing history' is checked (uncheck cookies, cache, etc.)"
echo "  6. Click 'Clear data' button"
echo ""
echo "Alternative: Use Ctrl+Shift+Delete shortcut to open dialog directly"