#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Extension Load Unpacked Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if agent reached extensions page
    if [[ "$ACTIVE_URL" == *"chrome://extensions"* ]]; then
        echo "✓ Agent navigated to chrome://extensions"
    else
        echo "⚠ Agent did not reach chrome://extensions (current: $ACTIVE_URL)"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure extension data is persisted to disk
echo "Closing Chrome to save extension state..."
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE_PRIMARY="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE_FALLBACK="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE_PRIMARY/Preferences" ]; then
    cp "$CHROME_PROFILE_PRIMARY/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported from: $CHROME_PROFILE_PRIMARY"
    PROFILE_USED="$CHROME_PROFILE_PRIMARY"
elif [ -f "$CHROME_PROFILE_FALLBACK/Preferences" ]; then
    cp "$CHROME_PROFILE_FALLBACK/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported from fallback: $CHROME_PROFILE_FALLBACK"
    PROFILE_USED="$CHROME_PROFILE_FALLBACK"
else
    echo "⚠ Warning: Preferences file not found at any known location"
    PROFILE_USED=""
fi

# Check if Extensions directory exists (indicates extensions were loaded)
if [ -n "$PROFILE_USED" ]; then
    EXTENSIONS_DIR="$PROFILE_USED/Extensions"
    if [ -d "$EXTENSIONS_DIR" ]; then
        EXT_COUNT=$(find "$EXTENSIONS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        echo "✓ Extensions directory found with $EXT_COUNT extension(s)"
        
        # List extension IDs for debugging
        if [ $EXT_COUNT -gt 0 ]; then
            echo "Extension IDs present:"
            ls -1 "$EXTENSIONS_DIR" | head -10
        fi
    else
        echo "⚠ No Extensions directory found at: $EXTENSIONS_DIR"
    fi
fi

# Create a marker file with profile location for verifier
echo "$PROFILE_USED" > /tmp/chrome_profile_location.txt

echo "✅ Export complete"
echo "Verification files available at /tmp/"