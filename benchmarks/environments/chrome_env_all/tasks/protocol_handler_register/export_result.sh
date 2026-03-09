#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Protocol Handler Registration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure any pending changes are saved
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
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

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save Preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."

# Try multiple possible Chrome profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
    "/home/ga/.config/chromium/Default"
)

PREFS_EXPORTED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
        PREFS_EXPORTED=true
        
        # Also save the profile path for debugging
        echo "$CHROME_PROFILE" > /tmp/chrome_profile_path.txt
        
        # Extract and display protocol_handler section if present (for debugging)
        if command -v jq &> /dev/null; then
            echo "Protocol handler configuration:"
            jq '.protocol_handler // {}' /tmp/chrome_preferences.json || echo "  (not found or invalid JSON)"
        fi
        
        break
    fi
done

if [ "$PREFS_EXPORTED" = false ]; then
    echo "⚠ Warning: Could not find Preferences file in any known location"
    echo "  Searched locations:"
    for loc in "${CHROME_PROFILES[@]}"; do
        echo "    - $loc/Preferences"
    done
    # Create empty file to prevent verification errors
    echo "{}" > /tmp/chrome_preferences.json
fi

echo "✅ Export complete"
echo "Verification files available in /tmp/"