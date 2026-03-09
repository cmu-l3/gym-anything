#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Download Configuration Task Setup ==="
echo "Task: Configure custom download location (MyDownloads) and optional auto-open settings"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Clean up any existing MyDownloads directory for fresh start
echo "Cleaning up any existing MyDownloads directory..."
rm -rf /home/ga/MyDownloads 2>/dev/null || true
rm -rf /home/webuser/MyDownloads 2>/dev/null || true

# Ensure default Downloads directory exists
mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads

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

# Navigate to about:blank as starting point
echo "Navigating to: about:blank"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'about:blank'" || true
sleep 0.5
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

# Check current download location (for debugging)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    CURRENT_DL=$(jq -r '.download.default_directory // "not set"' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "not set")
    echo "Current download location: $CURRENT_DL"
else
    echo "Preferences file not yet created"
fi

echo "=== Setup complete ==="
echo "Chrome is ready on about:blank"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings or use menu (⋮ → Settings)"
echo "  2. Scroll down or search for 'Downloads' section"
echo "  3. Click 'Change' button next to Location"
echo "  4. Navigate to /home/ga and create 'MyDownloads' folder"
echo "  5. Select the MyDownloads folder"
echo "  6. Optionally configure auto-open for PDFs (if available)"
echo ""
echo "Target: Set download location to /home/ga/MyDownloads"