#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Zoom Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
echo "Capturing active tab information via CDP..."
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
echo "Closing Chrome to save zoom preferences..."
pkill -SIGTERM chrome || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    pkill -9 -f "chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for zoom verification..."

# Try multiple possible Chrome profile locations
CHROME_PROFILE_PATHS=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

PREFS_FOUND=false
for CHROME_PROFILE in "${CHROME_PROFILE_PATHS[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "✓ Found Preferences at: $CHROME_PROFILE/Preferences"
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported to /tmp/chrome_preferences.json"
        
        # Extract and display per-site zoom levels for debugging
        if command -v jq &> /dev/null; then
            echo ""
            echo "Per-site zoom levels found:"
            jq -r '.profile.per_host_zoom_levels // {} | to_entries[] | "  \(.key): \(.value)"' /tmp/chrome_preferences.json 2>/dev/null || echo "  (none or failed to parse)"
        fi
        
        PREFS_FOUND=true
        break
    fi
done

if [ "$PREFS_FOUND" = false ]; then
    echo "⚠ Warning: Preferences file not found in any expected location"
    echo "Searched locations:"
    for path in "${CHROME_PROFILE_PATHS[@]}"; do
        echo "  - $path/Preferences"
    done
    
    # Create empty JSON file to prevent verification errors
    echo '{"profile":{"per_host_zoom_levels":{}}}' > /tmp/chrome_preferences.json
fi

echo "✅ Export complete"