#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome History Search and Bulk Bookmark Task Setup ==="
echo "Task: Search history for 'python', select multiple entries, bulk bookmark to 'Python Resources' folder"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python libraries for verification
pip3 install -q requests 2>/dev/null || true

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

# Navigate to Python-related websites to populate history
echo "Populating history with Python-related websites..."

PYTHON_URLS=(
    "https://www.python.org/"
    "https://docs.python.org/3/"
    "https://pypi.org/"
    "https://github.com/python"
    "https://stackoverflow.com/questions/tagged/python"
    "https://realpython.com/"
)

for url in "${PYTHON_URLS[@]}"; do
    echo "Navigating to: $url"
    
    # Focus Chrome and navigate
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    
    # Wait for page to load and be recorded in history
    sleep 3
done

# Navigate back to Google as starting point for agent
echo "Navigating to Google as starting point..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Verify history was populated
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/History" ]; then
    HISTORY_COUNT=$(sqlite3 "$CHROME_PROFILE/History" "SELECT COUNT(*) FROM urls WHERE url LIKE '%python%';" 2>/dev/null || echo "0")
    echo "✓ History populated with $HISTORY_COUNT Python-related entries"
else
    echo "⚠ Warning: History file not found at expected location"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with Python-related browsing history populated."
echo ""
echo "Agent task:"
echo "  1. Navigate to chrome://history (or press Ctrl+H)"
echo "  2. Search for 'python' in the history search box"
echo "  3. Select multiple matching entries (at least 3)"
echo "  4. Right-click and choose 'Bookmark' or use bulk bookmark option"
echo "  5. Create a new folder named 'Python Resources'"
echo "  6. Save the selected entries to this folder"