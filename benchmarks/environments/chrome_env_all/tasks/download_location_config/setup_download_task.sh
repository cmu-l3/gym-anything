#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Download Location Configuration Task Setup ==="
echo "Task: Configure Chrome to use a custom download directory"

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

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Check current download directory for reference
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    CURRENT_DL=$(grep -o '"default_directory":"[^"]*"' "$CHROME_PROFILE/Preferences" | cut -d'"' -f4 || echo "/home/ga/Downloads")
    echo "Current download directory: $CURRENT_DL"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    CURRENT_DL=$(grep -o '"default_directory":"[^"]*"' "$ALT_PROFILE/Preferences" | cut -d'"' -f4 || echo "/home/ga/Downloads")
    echo "Current download directory: $CURRENT_DL"
else
    echo "Default download directory: /home/ga/Downloads (default)"
fi

echo "=== Setup complete ==="
echo "Chrome is ready at: https://www.google.com"
echo ""
echo "Agent should:"
echo "  1. Navigate to chrome://settings/downloads (or use Settings menu)"
echo "  2. Click 'Change' button next to Location"
echo "  3. Create a new folder (e.g., MyDownloads, CustomDownloads, BrowserDownloads)"
echo "  4. Select the new folder as download location"
echo "  5. Chrome will automatically save the setting"