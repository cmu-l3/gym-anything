#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Media Autoplay Configuration Task Setup ==="
echo "Task: Block media autoplay for news.example.com"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python JSON parsing utilities
pip3 install -q jsonschema 2>/dev/null || true

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

# Check initial Preferences state for debugging
echo "Checking initial autoplay configuration..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -f "$CHROME_PROFILE/Preferences" ]; then
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    # Check if sound exceptions already exist
    SOUND_EXCEPTIONS=$(jq -r '.profile.content_settings.exceptions.sound // {}' "$CHROME_PROFILE/Preferences" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    echo "Current sound exceptions count: $SOUND_EXCEPTIONS"
else
    echo "⚠ Warning: Preferences file not yet created at $CHROME_PROFILE/Preferences"
fi

echo "=== Setup complete ==="
echo "Chrome is ready. Agent should:"
echo "  1. Navigate to chrome://settings or use three-dot menu → Settings"
echo "  2. Go to Privacy and security → Site Settings"
echo "  3. Navigate to Additional content settings → Sound"
echo "  4. Add 'news.example.com' to 'Not allowed to play sound' list"
echo "  5. Or directly navigate to: chrome://settings/content/sound"