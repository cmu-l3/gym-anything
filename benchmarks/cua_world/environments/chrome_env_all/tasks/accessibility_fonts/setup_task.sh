#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Accessibility Font Configuration Task Setup ==="
echo "Task: Configure Chrome font sizes for improved accessibility"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Reset Chrome font sizes to defaults to ensure clean starting state
echo "Resetting font sizes to default values..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Function to reset font sizes in Preferences file
reset_font_sizes() {
    local prefs_file="$1"
    
    if [ ! -f "$prefs_file" ]; then
        echo "Preferences file not found: $prefs_file"
        return 1
    fi
    
    # Backup current preferences
    cp "$prefs_file" "${prefs_file}.backup" || true
    
    # Reset font sizes using jq (defaults: 16, 0, 13)
    jq '.webkit.webprefs.default_font_size = 16 | 
        .webkit.webprefs.minimum_font_size = 0 | 
        .webkit.webprefs.default_fixed_font_size = 13' \
        "$prefs_file" > "${prefs_file}.tmp"
    
    if [ $? -eq 0 ] && [ -s "${prefs_file}.tmp" ]; then
        mv "${prefs_file}.tmp" "$prefs_file"
        echo "✓ Font sizes reset to defaults (16, 0, 13)"
        return 0
    else
        echo "⚠ Failed to reset font sizes"
        rm -f "${prefs_file}.tmp"
        return 1
    fi
}

# Try primary profile location
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    reset_font_sizes "$CHROME_PROFILE/Preferences"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    reset_font_sizes "$ALT_PROFILE/Preferences"
else
    echo "⚠ Warning: Could not find Preferences file to reset"
fi

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
    # If Chrome is running, we need to restart it to load the reset preferences
    echo "Restarting Chrome to apply reset preferences..."
    pkill -f "google-chrome" || true
    sleep 2
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
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

echo "=== Setup complete ==="
echo "Chrome is ready with default font settings (16, 0, 13)"
echo ""
echo "Agent task:"
echo "  1. Navigate to chrome://settings"
echo "  2. Find Appearance section"
echo "  3. Click 'Customize fonts'"
echo "  4. Set Font size (default) to 20"
echo "  5. Set Minimum font size to 12"
echo "  6. Set Fixed-width font size to 16"
echo ""
echo "Expected final values: default=20px, minimum=12px, fixed=16px"