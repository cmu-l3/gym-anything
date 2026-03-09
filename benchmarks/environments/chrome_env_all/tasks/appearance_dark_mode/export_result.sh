#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Appearance Dark Mode Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are in focus
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_dark_mode.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot_dark_mode.png"
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save appearance preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for appearance verification..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    
    # Show file size for debugging
    ls -lh "$CHROME_PROFILE/Preferences"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported from alternative location: $ALT_PROFILE/Preferences"
    ls -lh "$ALT_PROFILE/Preferences"
else
    echo "⚠ Warning: Preferences file not found at any known location"
    echo "Checked locations:"
    echo "  - $CHROME_PROFILE/Preferences"
    echo "  - $ALT_PROFILE/Preferences"
    
    # Create empty JSON as fallback to prevent verification errors
    echo '{}' > /tmp/chrome_preferences_export.json
fi

# Verify the exported file is valid JSON
if [ -f /tmp/chrome_preferences_export.json ]; then
    if jq empty /tmp/chrome_preferences_export.json 2>/dev/null; then
        echo "✓ Exported Preferences file is valid JSON"
        
        # Extract and display theme settings for debugging
        echo "Current theme settings:"
        jq '.browser.theme // "No theme settings found"' /tmp/chrome_preferences_export.json 2>/dev/null || echo "Could not extract theme settings"
    else
        echo "⚠ Warning: Exported Preferences file is not valid JSON"
    fi
fi

echo "✅ Export complete"
echo "Files prepared for verification:"
echo "  - /tmp/chrome_preferences_export.json"
echo "  - /tmp/final_url.txt"
echo "  - /tmp/final_screenshot_dark_mode.png"