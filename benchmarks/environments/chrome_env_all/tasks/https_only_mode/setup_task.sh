#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome HTTPS-Only Mode Configuration Task Setup ==="
echo "Task: Enable HTTPS-First Mode for improved browsing security"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python JSON processing (usually already available)
pip3 install -q --upgrade pip 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
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

# Navigate to the starting URL (Google homepage as neutral starting point)
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

# Check current HTTPS-Only mode status for debugging
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    echo "Checking current HTTPS-Only mode status..."
    CURRENT_STATUS=$(python3 -c "
import json
try:
    with open('$CHROME_PROFILE/Preferences', 'r') as f:
        prefs = json.load(f)
    # Check multiple possible locations
    https_enabled = prefs.get('generated', {}).get('https_only_mode_enabled', False)
    if not https_enabled:
        https_enabled = prefs.get('https_only_mode_enabled', False)
    if not https_enabled:
        https_enabled = prefs.get('generated', {}).get('https_first_mode_enabled', False)
    print('enabled' if https_enabled else 'disabled')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
    echo "Current HTTPS-Only mode status: $CURRENT_STATUS"
else
    echo "Preferences file not found (first run)"
fi

echo "=== Setup complete ==="
echo "Chrome is ready. Agent should:"
echo "  1. Navigate to chrome://settings or use menu (⋮ → Settings)"
echo "  2. Go to Privacy and Security section"
echo "  3. Click on Security"
echo "  4. Enable 'Always use secure connections' toggle"
echo "  5. Setting will save automatically"