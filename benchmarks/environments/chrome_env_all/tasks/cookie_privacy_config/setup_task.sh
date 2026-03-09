#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Third-Party Cookie Blocking Configuration Task Setup ==="
echo "Task: Configure Chrome to block third-party cookies for enhanced privacy"

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

# Navigate directly to Chrome's cookie settings page
echo "Navigating to: chrome://settings/cookies"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings/cookies'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    # Log current active tab URL
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Check current cookie policy before task
echo "Checking current cookie policy..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    CURRENT_COOKIE_MODE=$(jq -r '.profile.cookie_controls_mode // 0' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "0")
    echo "Current cookie_controls_mode: $CURRENT_COOKIE_MODE (0=allow all, 1=block third-party, 2=block in incognito)"
    
    # Backup preferences for comparison
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup_before_task" 2>/dev/null || true
fi

echo "=== Setup complete ==="
echo "Chrome is ready at cookie settings page."
echo ""
echo "Agent task:"
echo "  1. Locate the 'Third-party cookies' section (should already be visible)"
echo "  2. Select the radio button for 'Block third-party cookies'"
echo "  3. Chrome will automatically save this setting"
echo ""
echo "Alternative approach:"
echo "  - Navigate to chrome://settings/privacy"
echo "  - Click on 'Third-party cookies'"
echo "  - Select 'Block third-party cookies'"