#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Default Font Customization Task Setup ==="
echo "Task: Customize Chrome's default font families (Standard, Serif, Sans-serif)"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install verification libraries
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

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

# Navigate to Chrome font settings page
FONT_SETTINGS_URL="chrome://settings/fonts"
echo "Navigating to: $FONT_SETTINGS_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$FONT_SETTINGS_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Get active URL to confirm we're on font settings
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "Active URL: $ACTIVE_URL"
    
    if [[ "$ACTIVE_URL" == *"chrome://settings/fonts"* ]]; then
        echo "✓ Successfully navigated to font settings page"
    else
        echo "⚠ Warning: Not on font settings page (URL: $ACTIVE_URL)"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Backup current preferences before task
CHROME_PROFILE_CDP="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE_STANDARD="/home/ga/.config/google-chrome/Default"

for CHROME_PROFILE in "$CHROME_PROFILE_CDP" "$CHROME_PROFILE_STANDARD"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "Backing up Chrome Preferences from: $CHROME_PROFILE"
        cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup.fontconfig" 2>/dev/null || true
        
        # Log current font settings for debugging
        if command -v jq &> /dev/null; then
            echo "Current font settings:"
            jq -r '.webkit.webprefs.fonts // "No font settings found"' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "Could not extract font settings"
        fi
        break
    fi
done

echo "=== Setup complete ==="
echo "Chrome is displaying the font customization page (chrome://settings/fonts)"
echo ""
echo "Agent should now:"
echo "  1. Locate the 'Standard font' dropdown"
echo "  2. Select a different font (e.g., Liberation Sans, DejaVu Sans)"
echo "  3. Locate the 'Serif font' dropdown"
echo "  4. Select a different serif font (e.g., Liberation Serif, DejaVu Serif)"
echo "  5. Locate the 'Sans-serif font' dropdown"
echo "  6. Select a different sans-serif font"
echo ""
echo "Note: Font changes in Chrome settings auto-save immediately"