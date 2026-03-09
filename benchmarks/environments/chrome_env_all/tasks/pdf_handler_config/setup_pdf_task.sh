#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome PDF Handler Configuration Task Setup ==="
echo "Task: Configure PDF download behavior in Chrome settings"

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
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Check current PDF handler setting (for debugging)
echo "Checking initial PDF handler setting..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    INITIAL_SETTING=$(python3 -c "
import json
try:
    with open('$CHROME_PROFILE/Preferences', 'r') as f:
        prefs = json.load(f)
    val = prefs.get('plugins', {}).get('always_open_pdf_externally', False)
    print('download' if val else 'open_in_chrome')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
    echo "✓ Initial PDF setting: $INITIAL_SETTING"
else
    echo "⚠ Preferences file not found, checking alternative location"
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "✓ Found Preferences at alternative location"
    fi
fi

echo "=== Setup complete ==="
echo "Chrome is ready at: https://www.google.com"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings (Ctrl+L, type 'chrome://settings')"
echo "  2. Click 'Privacy and security' in sidebar"
echo "  3. Click 'Site Settings'"
echo "  4. Scroll to find 'PDF documents' under 'Additional content settings'"
echo "  5. Click on 'PDF documents'"
echo "  6. Toggle 'Download PDF files instead of automatically opening them in Chrome' to ON"
echo "  7. The setting saves automatically"