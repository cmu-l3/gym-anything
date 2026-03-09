#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarks Bar Toggle Task Export ==="

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

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file for verification
echo "Exporting Chrome Preferences..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported to /tmp/chrome_preferences.json"
    
    # Extract and display bookmark bar setting for debugging
    if command -v jq &> /dev/null; then
        BOOKMARK_BAR_STATE=$(jq -r '.bookmark_bar.show_on_all_tabs // "not_found"' /tmp/chrome_preferences.json 2>/dev/null || echo "error")
        echo "Bookmarks bar state in exported file: $BOOKMARK_BAR_STATE"
    fi
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE"
    else
        echo "✗ Could not find Preferences file in any known location"
        # Create a marker file to indicate failure
        echo "preferences_not_found" > /tmp/chrome_preferences_status.txt
    fi
fi

# Create a timestamp marker for verification
date +%s > /tmp/export_timestamp.txt

echo "✅ Export complete"