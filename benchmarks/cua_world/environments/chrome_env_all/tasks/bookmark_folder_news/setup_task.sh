#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Folder Organization Task Setup ==="
echo "Task: Create 'News' folder in bookmarks bar and add news websites"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

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

# Navigate to starting URL (Google as neutral starting point)
echo "Navigating to: https://www.google.com"
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
    
    # Check initial bookmark state
    CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
    if [ ! -f "$CHROME_PROFILE/Bookmarks" ]; then
        CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    fi
    
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        echo "✓ Bookmarks file found at: $CHROME_PROFILE"
        # Backup original bookmarks
        cp "$CHROME_PROFILE/Bookmarks" "$CHROME_PROFILE/Bookmarks.backup.pre_task" 2>/dev/null || true
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Ensure bookmarks bar is visible (important for bookmark manager interaction)
echo "Ensuring bookmarks bar visibility..."
# The bookmarks bar should be visible by default, but we can verify via preferences
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    # Check if bookmark bar is shown
    BOOKMARK_BAR_SHOWN=$(python3 -c "
import json
try:
    with open('$CHROME_PROFILE/Preferences', 'r') as f:
        prefs = json.load(f)
    shown = prefs.get('bookmark_bar', {}).get('show_on_all_tabs', False)
    print('true' if shown else 'false')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
    
    echo "Bookmark bar visibility: $BOOKMARK_BAR_SHOWN"
fi

echo "=== Setup complete ==="
echo "Chrome is ready at Google homepage"
echo ""
echo "Agent should now:"
echo "  1. Press Ctrl+Shift+O to open Bookmark Manager"
echo "  2. Navigate to Bookmark Bar in left sidebar"
echo "  3. Create new folder named 'News'"
echo "  4. Add bookmark 'Hacker News' → https://news.ycombinator.com"
echo "  5. Add bookmark 'BBC News' → https://www.bbc.com/news"
echo "  6. Add bookmark 'Reuters' → https://www.reuters.com"