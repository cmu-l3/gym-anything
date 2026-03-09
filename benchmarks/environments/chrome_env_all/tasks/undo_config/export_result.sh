#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Extension Shortcuts Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification context
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
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file for keyboard shortcuts verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported to /tmp/chrome_preferences.json"
    
    # Log file size for verification
    PREFS_SIZE=$(stat -f%z "$CHROME_PROFILE/Preferences" 2>/dev/null || stat -c%s "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "unknown")
    echo "Preferences file size: $PREFS_SIZE bytes"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file in any known location"
    fi
fi

# Also export Extensions state file if available (contains extension metadata)
if [ -f "$CHROME_PROFILE/Extensions" ]; then
    cp -r "$CHROME_PROFILE/Extensions" /tmp/chrome_extensions_dir 2>/dev/null || true
fi

# Copy extension ID reference file
if [ -f "/tmp/extension_id.txt" ]; then
    cp /tmp/extension_id.txt /tmp/extension_name.txt
    echo "Extension reference copied for verification"
fi

echo "✅ Export complete"
echo "Verification files prepared in /tmp/"