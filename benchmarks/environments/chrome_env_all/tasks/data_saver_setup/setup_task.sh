#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Data Saver Configuration Task Setup ==="
echo "Task: Configure bandwidth optimization settings for slow/metered connections"

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
    # Log initial active URL for debugging
    INITIAL_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "unknown")
    echo "✓ Chrome displaying: $INITIAL_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Create a marker file to track initial settings state (for verification comparison)
CHROME_PROFILE_PRIMARY="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE_PRIMARY/Preferences" ]; then
    cp "$CHROME_PROFILE_PRIMARY/Preferences" /tmp/initial_preferences_backup.json 2>/dev/null || true
    echo "✓ Backed up initial preferences from primary location"
elif [ -f "$CHROME_PROFILE_ALT/Preferences" ]; then
    cp "$CHROME_PROFILE_ALT/Preferences" /tmp/initial_preferences_backup.json 2>/dev/null || true
    echo "✓ Backed up initial preferences from alternative location"
else
    echo "⚠ Warning: Could not locate Preferences file for backup"
fi

echo "=== Setup complete ==="
echo "Chrome is ready at Google homepage."
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings (Ctrl+L, type 'chrome://settings', Enter)"
echo "  2. Use the search box or navigate to 'Performance' or 'Privacy and security' sections"
echo "  3. Find and disable 'Preload pages for faster browsing'"
echo "  4. Optionally disable 'Enhanced Safe Browsing' (under Security)"
echo "  5. Optionally enable 'Memory Saver' mode (under Performance)"
echo "  6. Settings auto-save, so changes take effect immediately"
echo ""
echo "Note: The agent should aim to configure settings that reduce bandwidth usage."