#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Homepage Button Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are committed
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Give Chrome a moment to auto-save any pending preference changes
echo "Waiting for Chrome to commit settings..."
sleep 2

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
echo "Closing Chrome to save preferences..."
pkill -SIGTERM chrome || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, forcing shutdown..."
    pkill -9 -f "google-chrome" || true
    pkill -9 -f "chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome preferences..."

# Try multiple possible Chrome profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
    "/home/ga/.config/chromium/Default"
)

PREFS_EXPORTED=false

for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "Found Preferences at: $CHROME_PROFILE"
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported to /tmp/chrome_preferences_export.json"
        
        # Also save the profile path for verification
        echo "$CHROME_PROFILE" > /tmp/chrome_profile_path.txt
        
        # Show file size for debugging
        ls -lh "$CHROME_PROFILE/Preferences"
        
        PREFS_EXPORTED=true
        break
    fi
done

if [ "$PREFS_EXPORTED" = false ]; then
    echo "⚠ Warning: Could not find Preferences file in any known location"
    echo "Searched locations:"
    for prof in "${CHROME_PROFILES[@]}"; do
        echo "  - $prof/Preferences"
    done
    
    # List all Chrome config directories for debugging
    echo ""
    echo "Available Chrome config directories:"
    find /home/ga/.config -maxdepth 2 -name "Default" -type d 2>/dev/null || true
fi

# Create a marker file to indicate export completed
echo "$(date +%s)" > /tmp/export_complete.txt

echo "✅ Export complete"