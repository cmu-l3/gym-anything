#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Safe Browsing Configuration Task Setup ==="
echo "Task: Configure Safe Browsing to Enhanced protection level"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

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

# Navigate directly to Security settings page to help the agent
# This is the page where Safe Browsing configuration is located
echo "Navigating to: chrome://settings/security"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings/security'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    # Check current URL to confirm we're on settings page
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
    echo "Current URL: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Display current Safe Browsing configuration status for debugging
echo "Checking current Safe Browsing configuration..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    PREFS_FILE="$CHROME_PROFILE/Preferences"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    PREFS_FILE="$ALT_PROFILE/Preferences"
else
    echo "⚠ Could not find Preferences file"
    PREFS_FILE=""
fi

if [ -n "$PREFS_FILE" ]; then
    SB_ENABLED=$(jq -r '.safebrowsing.enabled // "not_set"' "$PREFS_FILE" 2>/dev/null || echo "parse_error")
    SB_ENHANCED=$(jq -r '.safebrowsing.enhanced // "not_set"' "$PREFS_FILE" 2>/dev/null || echo "parse_error")
    echo "Current Safe Browsing status:"
    echo "  - safebrowsing.enabled: $SB_ENABLED"
    echo "  - safebrowsing.enhanced: $SB_ENHANCED"
fi

echo "=== Setup complete ==="
echo "Chrome is on the Security settings page: chrome://settings/security"
echo ""
echo "Agent should:"
echo "  1. Locate the 'Safe Browsing' section on the page"
echo "  2. Click on 'Enhanced protection' radio button"
echo "  3. The setting will be saved automatically"
echo ""
echo "Safe Browsing protection levels:"
echo "  • Enhanced protection: Most secure, shares more data with Google"
echo "  • Standard protection: Default, balanced security"
echo "  • No protection: Not recommended"