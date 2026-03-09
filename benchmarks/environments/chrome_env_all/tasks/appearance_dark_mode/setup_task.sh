#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Appearance Dark Mode Configuration Task Setup ==="
echo "Task: Enable dark mode in Chrome's appearance settings"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome starts with light/default theme (reset if needed)
echo "Resetting Chrome theme to light mode..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Function to reset theme to light mode in Preferences
reset_theme_to_light() {
    local prefs_file="$1"
    if [ -f "$prefs_file" ]; then
        echo "Resetting theme in: $prefs_file"
        # Backup original preferences
        cp "$prefs_file" "${prefs_file}.backup_$(date +%s)" || true
        
        # Use Python to safely modify JSON and set theme to light (color_scheme: 1)
        python3 << 'RESET_THEME_PYTHON'
import json
import sys

prefs_file = sys.argv[1]

try:
    with open(prefs_file, 'r', encoding='utf-8') as f:
        prefs = json.load(f)
    
    # Ensure browser.theme.color_scheme is set to 1 (Light mode)
    if 'browser' not in prefs:
        prefs['browser'] = {}
    if 'theme' not in prefs['browser']:
        prefs['browser']['theme'] = {}
    
    prefs['browser']['theme']['color_scheme'] = 1  # 1 = Light mode
    
    # Also reset any NTP theme settings that might affect appearance
    if 'ntp' in prefs and 'theme_background_color' in prefs['ntp']:
        del prefs['ntp']['theme_background_color']
    
    with open(prefs_file, 'w', encoding='utf-8') as f:
        json.dump(prefs, f, indent=2)
    
    print("✓ Theme reset to light mode successfully")
except Exception as e:
    print(f"⚠ Warning: Could not reset theme: {e}", file=sys.stderr)

RESET_THEME_PYTHON "$prefs_file"
    fi
}

# Try to reset theme in both possible profile locations
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    reset_theme_to_light "$CHROME_PROFILE/Preferences"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    reset_theme_to_light "$ALT_PROFILE/Preferences"
else
    echo "⚠ Note: No existing Preferences file found, Chrome will start with defaults"
fi

# Wait a moment for file system to sync
sleep 1

# Ensure Chrome is properly focused and on correct URL
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

# Navigate to about:blank as a neutral starting point
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

echo "=== Setup complete ==="
echo "Chrome is ready in light mode. Agent should navigate to chrome://settings/appearance"
echo "and enable dark mode by selecting 'Dark' from the Theme dropdown."
echo ""
echo "Expected agent actions:"
echo "  1. Navigate to chrome://settings (Ctrl+, or address bar)"
echo "  2. Click on 'Appearance' in left sidebar"
echo "  3. Find 'Theme' dropdown"
echo "  4. Select 'Dark' from the dropdown"
echo "  5. Optionally enable 'Show home button' and 'Show bookmarks bar'"