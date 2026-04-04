#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Profile Customization Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    echo "Focusing Chrome window..."
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    echo "Capturing final screenshot..."
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved to /tmp/final_screenshot.png"
fi

# Capture active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save profile preferences..."
# First try graceful shutdown
pkill -TERM -f "google-chrome" 2>/dev/null || true
sleep 3

# Check if Chrome closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, forcing close..."
    pkill -9 -f "google-chrome" 2>/dev/null || true
    sleep 2
fi

echo "✓ Chrome closed"

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences file..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    
    # Show file size for debugging
    ls -lh "$CHROME_PROFILE/Preferences" | awk '{print "  File size:", $5}'
    
    # Extract profile name for quick check
    if command -v jq &> /dev/null; then
        PROFILE_NAME=$(jq -r '.profile.name // "not found"' /tmp/chrome_preferences_export.json)
        PROFILE_ICON=$(jq -r '.profile.avatar_icon // "not found"' /tmp/chrome_preferences_export.json)
        echo "  Current profile name: '$PROFILE_NAME'"
        echo "  Current profile icon: '$PROFILE_ICON'"
    fi
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location
    CHROME_ALT="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_ALT/Preferences" ]; then
        cp "$CHROME_ALT/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location: $CHROME_ALT/Preferences"
    else
        echo "✗ Could not find Preferences file in any known location"
        
        # List available files for debugging
        echo "Checking available Chrome profile files..."
        find /home/ga/.config -name "Preferences" -type f 2>/dev/null || echo "No Preferences files found"
        
        # Create empty file to prevent verification errors
        echo "{}" > /tmp/chrome_preferences_export.json
    fi
fi

# Create a marker file indicating export is complete
touch /tmp/export_complete.marker
echo "$(date)" > /tmp/export_timestamp.txt

echo "✅ Export complete"
echo "Preferences file ready for verification at: /tmp/chrome_preferences_export.json"