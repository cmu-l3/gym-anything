#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific JavaScript Control Task Setup ==="
echo "Task: Block JavaScript on ads.example.com using site settings"

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
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://settings/content/javascript" &
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

# Navigate to JavaScript settings page to make task easier
echo "Navigating to JavaScript settings page..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings/content/javascript'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Check current Preferences to see if JavaScript blocking already exists (for debugging)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "$CHROME_PROFILE" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    echo "✓ Chrome Preferences file found at: $CHROME_PROFILE/Preferences"
    # Backup original preferences
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup_before_task" || true
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
fi

echo "=== Setup complete ==="
echo "Chrome is on JavaScript settings page: chrome://settings/content/javascript"
echo "Agent should:"
echo "  1. Locate 'Not allowed to use JavaScript' section"
echo "  2. Click 'Add' button next to it"
echo "  3. Enter 'https://ads.example.com' in the site URL field"
echo "  4. Click 'Add' to confirm"
echo "  5. Verify ads.example.com appears in the blocked list"