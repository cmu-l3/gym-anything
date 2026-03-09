#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Resource Preloading Configuration Task Export ==="

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
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are flushed to disk
echo "Closing Chrome to save preferences..."
pkill -TERM chrome || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_export.json"
    
    # Show relevant section for debugging
    if command -v jq &> /dev/null; then
        echo "Network prediction settings:"
        jq '.net // "No net settings found"' /tmp/chrome_preferences_export.json 2>/dev/null || echo "Could not parse preferences"
    fi
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE"
        
        if command -v jq &> /dev/null; then
            echo "Network prediction settings:"
            jq '.net // "No net settings found"' /tmp/chrome_preferences_export.json 2>/dev/null || true
        fi
    else
        echo "✗ Could not find Preferences file in any known location"
        # Create empty JSON to prevent verifier errors
        echo '{}' > /tmp/chrome_preferences_export.json
    fi
fi

echo "✅ Export complete"