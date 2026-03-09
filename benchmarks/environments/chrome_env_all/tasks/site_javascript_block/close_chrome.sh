#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific JavaScript Blocking Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture final tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if agent was on settings page
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent was on Chrome settings page"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save JavaScript blocking settings..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for verification..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_final.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_final.json"
    
    # Get file size for debugging
    PREFS_SIZE=$(stat -f%z "$CHROME_PROFILE/Preferences" 2>/dev/null || stat -c%s "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "unknown")
    echo "  Preferences file size: $PREFS_SIZE bytes"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_final.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE"
    else
        echo "✗ Could not find Preferences file at any known location"
        # Create empty file to prevent verification errors
        echo "{}" > /tmp/chrome_preferences_final.json
    fi
fi

# Also check if there's a backup or temporary preferences file
if [ -f "$CHROME_PROFILE/Preferences~" ]; then
    cp "$CHROME_PROFILE/Preferences~" /tmp/chrome_preferences_backup.json 2>/dev/null || true
fi

echo "✅ Export complete"
echo "Verification files ready in /tmp/"