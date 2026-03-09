#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Hardware Acceleration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture current active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
# Hardware acceleration changes are saved immediately to Preferences, but
# closing ensures all writes are flushed
echo "Closing Chrome to ensure preferences are saved..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."

# Try multiple possible Chrome profile locations
PROFILE_PATHS=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
    "/home/ga/.config/chromium/Default"
)

PREFS_FOUND=false

for CHROME_PROFILE in "${PROFILE_PATHS[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "✓ Found Preferences at: $CHROME_PROFILE/Preferences"
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported to /tmp/chrome_preferences.json"
        
        # Extract just the relevant setting for debugging
        if command -v jq &> /dev/null; then
            echo "Hardware acceleration setting in Preferences:"
            jq '.hardware_acceleration_mode // "not found"' /tmp/chrome_preferences.json || true
            # Also check legacy location
            jq '.hardware // "not found (legacy path)"' /tmp/chrome_preferences.json || true
        fi
        
        PREFS_FOUND=true
        break
    fi
done

if [ "$PREFS_FOUND" = false ]; then
    echo "⚠ Warning: Preferences file not found in any known location"
    echo "Searched locations:"
    for path in "${PROFILE_PATHS[@]}"; do
        echo "  - $path/Preferences"
    done
fi

echo "✅ Export complete"